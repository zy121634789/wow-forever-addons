-- 拍卖行扫描：全量扫描 + 平时浏览时顺手记录价格；商人价格记录
local _, CP = ...

local COOLDOWN = 15 * 60   -- 服务器对全量扫描的冷却（账号共享）
local FRAME_BUDGET_MS = 12 -- 每帧最多处理多少毫秒，避免卡顿
local MAX_RETRY = 6        -- 物品数据没加载好的行，最多重试几轮

local S = { state = "idle" } -- idle / waiting / processing
CP.Scan = S
CP.auctionOpen = false

local function Supported()
    return C_AuctionHouse and C_AuctionHouse.ReplicateItems and C_AuctionHouse.GetNumReplicateItems
        and C_AuctionHouse.GetReplicateItemInfo and true or false
end

function S.Remaining()
    local left = (CP.db.lastRequest or 0) + COOLDOWN - CP.Now()
    return left > 0 and left or 0
end

local function SetStatus(text)
    S.status = text
    if CP.OnScanStatus then CP.OnScanStatus(text) end
end

-- ---------------------------------------------------------------- 全量扫描
function S.Start()
    if not Supported() then return CP.Print("当前客户端没有全量扫描接口（C_AuctionHouse.ReplicateItems）。") end
    if not CP.auctionOpen then return CP.Print("请先打开拍卖行。") end
    if S.state ~= "idle" then return CP.Print("扫描已经在进行中。") end
    if InCombatLockdown() then return CP.Print("战斗中不能扫描。") end
    local left = S.Remaining()
    if left > 0 then
        return CP.Print(string.format("全扫描冷却中，还要 %d分%02d秒。冷却期间浏览拍卖行时，价格仍会自动记录。",
            math.floor(left / 60), left % 60))
    end
    S.state = "waiting"
    CP.db.lastRequest = CP.Now()
    SetStatus("等待服务器返回…")
    local ok, err = pcall(C_AuctionHouse.ReplicateItems)
    if not ok then
        S.state = "idle"
        SetStatus(nil)
        CP.Print("扫描请求失败：" .. tostring(err))
    end
end

local worker = CreateFrame("Frame")
worker:Hide()

local function Finish(ok, msg)
    worker:Hide()
    S.state = "idle"
    if ok then
        local share = CP.db.settings.share
        local now, n = CP.Now(), 0
        for itemID, samples in pairs(S.samples) do
            local m, low, q = CP.Aggregate(samples, share)
            if m then
                CP.db.prices[itemID] = { m = m, n = low, q = q, t = now }
                n = n + 1
            end
        end
        CP.db.lastScan = now
        if S.skipped == 0 then
            CP.Sales.OnScan(S.listings, S.tracked, now)
        end
        CP.Quant.Record(S.tracked, now)
        SetStatus(nil)
        CP.Print(string.format("扫描完成：%d 条拍卖，%d 种物品有价格%s。", S.total, n,
            S.skipped > 0 and ("，" .. S.skipped .. " 条读取失败已跳过") or ""))
        CP.Quant.Alert()
        CP.Refresh()
    else
        SetStatus(nil)
        CP.Print("扫描中断：" .. tostring(msg) .. "（已有价格保留不变）")
    end
    S.samples, S.pending, S.listings, S.tracked = nil, nil, nil, nil
end

-- 读一行；返回 true=已处理, false=数据还没加载好需要重试
local function ReadRow(i)
    local ok, _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, saleStatus, itemID =
        pcall(C_AuctionHouse.GetReplicateItemInfo, i)
    if not ok then return true end
    if CP.Secret(itemID) or CP.Secret(buyout) or CP.Secret(count) then return true end
    if not itemID then return false end
    if (saleStatus or 0) ~= 0 then return true end      -- 已售出等待结算
    if not buyout or buyout <= 0 then return true end    -- 只能竞拍、没有一口价
    count = (count and count > 0) and count or 1
    local list = S.samples[itemID]
    if not list then list = {}; S.samples[itemID] = list end
    list[#list + 1] = { unit = buyout / count, qty = count }
    -- 配方相关物品额外记下挂单明细，用于两次扫描对比估算销量
    if S.tracked[itemID] then
        local left
        if C_AuctionHouse.GetReplicateItemTimeLeft then
            local okT, v = pcall(C_AuctionHouse.GetReplicateItemTimeLeft, i)
            if okT and not CP.Secret(v) then left = v end
        end
        local l = S.listings[itemID]
        if not l then l = {}; S.listings[itemID] = l end
        l[#l + 1] = { b = buyout, q = count, m = CP.Sales.MinSecondsLeft(left) }
    end
    return true
end

worker:SetScript("OnUpdate", function()
    if not CP.auctionOpen then return Finish(false, "拍卖行被关闭了") end
    local num = C_AuctionHouse.GetNumReplicateItems()
    if num ~= S.total then return Finish(false, "拍卖数据在处理过程中发生变化") end
    local start = debugprofilestop()
    if S.cursor < S.total then
        while S.cursor < S.total do
            if not ReadRow(S.cursor) then S.pending[#S.pending + 1] = S.cursor end
            S.cursor = S.cursor + 1
            if S.cursor % 200 == 0 and debugprofilestop() - start > FRAME_BUDGET_MS then break end
        end
        SetStatus(string.format("处理中 %d%%", math.floor(S.cursor / math.max(1, S.total) * 100)))
        return
    end
    -- 第一轮结束：重试没加载好的行
    if #S.pending == 0 then return Finish(true) end
    if GetTime() < (S.nextRetry or 0) then return end
    S.retry = S.retry + 1
    if S.retry > MAX_RETRY then
        S.skipped = #S.pending
        return Finish(true)
    end
    local again = {}
    for _, i in ipairs(S.pending) do
        if not ReadRow(i) then again[#again + 1] = i end
    end
    S.pending = again
    S.nextRetry = GetTime() + 1
    SetStatus(string.format("等待物品数据 %d 条", #again))
end)

CP.On("REPLICATE_ITEM_LIST_UPDATE", function()
    if S.state == "processing" then return end
    if S.state == "idle" then
        -- 别的插件（如 Auctionator）发起的全扫描：顺便用它的数据。
        -- 同一次扫描里这个事件会因物品数据加载而重复触发，所以 2 分钟内只接一次。
        if not CP.auctionOpen or CP.Now() - (S.lastAccepted or 0) < 120 then return end
        CP.db.lastRequest = CP.Now()
        CP.Print("检测到其他插件的全扫描，顺便记录价格…")
    end
    S.lastAccepted = CP.Now()
    S.state = "processing"
    S.total = C_AuctionHouse.GetNumReplicateItems() or 0
    S.cursor, S.pending, S.samples, S.retry, S.skipped, S.nextRetry = 0, {}, {}, 0, 0, 0
    S.listings, S.tracked = {}, CP.Sales.Tracked()
    if S.total == 0 then return Finish(false, "服务器返回了 0 条拍卖") end
    worker:Show()
end)

-- ---------------------------------------------------------------- 浏览时顺手记录
local function Store(itemID, samples)
    if #samples == 0 then return end
    local m, low, q = CP.Aggregate(samples, CP.db.settings.share)
    if not m then return end
    CP.db.prices[itemID] = { m = m, n = low, q = q, t = CP.Now() }
    CP.Refresh()
end

-- 材料类（可堆叠）物品
CP.On("COMMODITY_SEARCH_RESULTS_UPDATED", function(itemID)
    if not itemID or CP.Secret(itemID) or not C_AuctionHouse.GetNumCommoditySearchResults then return end
    local samples = {}
    for i = 1, C_AuctionHouse.GetNumCommoditySearchResults(itemID) do
        local r = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
        if r and r.unitPrice and r.unitPrice > 0 and r.quantity and r.quantity > 0 then
            samples[#samples + 1] = { unit = r.unitPrice, qty = r.quantity }
        end
    end
    Store(itemID, samples)
end)

-- 装备等单件物品
CP.On("ITEM_SEARCH_RESULTS_UPDATED", function(itemKey)
    if not itemKey or CP.Secret(itemKey) or not C_AuctionHouse.GetNumItemSearchResults then return end
    local itemID = itemKey.itemID
    if not itemID then return end
    local samples = {}
    for i = 1, C_AuctionHouse.GetNumItemSearchResults(itemKey) do
        local r = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
        if r and r.buyoutAmount and r.buyoutAmount > 0 then
            local q = (r.quantity and r.quantity > 0) and r.quantity or 1
            samples[#samples + 1] = { unit = r.buyoutAmount / q, qty = q }
        end
    end
    Store(itemID, samples)
end)

CP.On("AUCTION_HOUSE_SHOW", function()
    CP.auctionOpen = true
    if CP.OnAuctionShow then CP.OnAuctionShow() end
end)
CP.On("AUCTION_HOUSE_CLOSED", function()
    CP.auctionOpen = false
    if S.state == "waiting" then
        S.state = "idle"
        SetStatus(nil)
    end
end)

-- ---------------------------------------------------------------- 商人价格
local function MerchantItem(i)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local ok, info = pcall(C_MerchantFrame.GetItemInfo, i)
        if ok and type(info) == "table" then return info end
    end
    if GetMerchantItemInfo then
        local _, _, price, stack, avail, _, _, ext = GetMerchantItemInfo(i)
        return { price = price, stackCount = stack, numAvailable = avail, hasExtendedCost = ext }
    end
end

local function ScanMerchant()
    local n = 0
    for i = 1, (GetMerchantNumItems() or 0) do
        local id = GetMerchantItemID and GetMerchantItemID(i)
        local info = MerchantItem(i)
        -- 只记无限供应、纯金币购买的商品（限量商品/需要代币的不算）
        if id and info and info.price and info.price > 0 and not info.hasExtendedCost
            and (info.numAvailable == nil or info.numAvailable < 0) then
            CP.db.vendor[id] = info.price / math.max(1, info.stackCount or 1)
            n = n + 1
        end
    end
    if n > 0 then CP.Refresh() end
end

CP.On("MERCHANT_SHOW", ScanMerchant)
CP.On("MERCHANT_UPDATE", ScanMerchant)
