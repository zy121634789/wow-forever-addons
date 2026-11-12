-- 快速扫描：拍卖行开着时，每分钟逐个搜索“加关注”的材料
-- 全量扫描有服务器 15 分钟冷却；单个物品搜索没有，只限制每分钟约 100 次。
-- 搜索结果带每张挂单的唯一编号，所以销量可以精确统计：
--   * 同一张挂单数量变少 = 被人买走了一部分
--   * 挂单消失、离过期还早、且不比现在的最低价贵 = 被买走（排除过期和取消重挂）
local _, CP = ...

local Qk = { state = "idle", done = 0, total = 0 }
CP.Quick = Qk

local TIMEOUT = 5          -- 单个物品等结果最多几秒
local MAX_MORE = 5         -- 结果分页时最多再请求几次
local USER_PAUSE = 20      -- 你自己在拍卖行操作后，暂停几秒
local MIN_GAP, MAX_GAP = 20, 12 * 3600
local LISTING_FRESH = 10 * 60
local ALERT_COOLDOWN = 30 * 60

local SORTS = { { sortOrder = (Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price) or 0, reverseSort = false } }

local nextRound, cur, queue = 0, nil, nil
local sending, userAt = false, -1000
local alerted = {}

-- ---------------------------------------------------------------- 挂单快照
-- 每张挂单 = { id = 编号, q = 数量, u = 单价, l = 剩余秒数(-1 未知), o = 是否自己的 }
function Qk.Encode(list)
    local parts = {}
    for i, a in ipairs(list) do
        parts[i] = string.format("%d:%d:%d:%d:%d", a.id, a.q, math.floor(a.u + 0.5), a.l, a.o and 1 or 0)
    end
    return table.concat(parts, ",")
end

function Qk.Decode(s)
    local list = {}
    for id, q, u, l, o in string.gmatch(s or "", "(%d+):(%d+):(%d+):(%-?%d+):(%d)") do
        list[#list + 1] = { id = tonumber(id), q = tonumber(q), u = tonumber(u), l = tonumber(l), o = o == "1" }
    end
    return list
end

-- 最近 10 分钟内快速扫描到的挂单；没有则返回 nil
function Qk.Listings(itemID)
    local e = CP.db.quick[itemID]
    if not e or CP.Now() - (e.t or 0) > LISTING_FRESH then return nil end
    return Qk.Decode(e.s)
end

-- 比较两次快照，返回估计卖出数量
function Qk.Compare(prev, cur, gap)
    local curMin, byId = nil, {}
    for _, a in ipairs(cur) do
        byId[a.id] = a
        if not curMin or a.u < curMin then curMin = a.u end
    end
    local sold = 0
    for _, p in ipairs(prev) do
        if not p.o then -- 自己的挂单不算（自己的成交在收支里）
            local c = byId[p.id]
            if c then
                if c.q < p.q then sold = sold + (p.q - c.q) end -- 被买走一部分
            else
                local notExpired
                if p.l < 0 then notExpired = gap <= 2 * 3600 else notExpired = p.l - gap > 30 end
                local cheap = (not curMin) or p.u <= curMin * 1.001
                if notExpired and cheap then sold = sold + p.q end
            end
        end
    end
    return sold
end

-- ---------------------------------------------------------------- 提醒
local function Alert(itemID)
    local a = CP.Quant.Advise(itemID)
    local act = a.action
    local isBuy = act == "buy" or act == "strong_buy"
    local isSell = (act == "sell" or act == "strong_sell") and a.owned > 0
    if not (isBuy or isSell) then
        alerted[itemID] = nil
        return
    end
    local now = CP.Now()
    local last = alerted[itemID]
    local cur = a.stats.cur
    if last and last.action == act and now - last.t < ALERT_COOLDOWN then
        -- 冷却中：价格再往有利方向走 10% 以上才再提醒
        local better = isBuy and cur <= last.price * 0.9 or (not isBuy and cur >= last.price * 1.1)
        if not better then return end
    end
    alerted[itemID] = { action = act, t = now, price = cur }
    local def = CP.Quant.ACTIONS[act]
    local msg = string.format("|cffffd100★|r %s%s|r %s　现价 %s（均价 %s，%+.0f%%）", def.color, def.label,
        CP.ItemName(itemID), CP.Money(cur, true), CP.Money(a.stats.mean, true), a.stats.dev * 100)
    if isBuy and a.qty and a.qty > 0 then
        msg = msg .. string.format("　建议 %s 以下买 %d 个", CP.Money(a.buyPrice, true), a.qty)
    elseif isSell then
        msg = msg .. string.format("　你有 %d 个", a.owned)
    end
    CP.Print(msg)
    if CP.db.settings.quickSound and PlaySound then
        local kit = SOUNDKIT and (SOUNDKIT.RAID_WARNING or SOUNDKIT.UI_RAID_BOSS_WHISPER_WARNING)
        if kit then pcall(PlaySound, kit) end
    end
end
Qk._alerted = alerted

-- ---------------------------------------------------------------- 处理结果
function Qk.Process(itemID, list, full)
    local db, now = CP.db, CP.Now()
    -- 价格
    local samples = {}
    for _, a in ipairs(list) do samples[#samples + 1] = { unit = a.u, qty = a.q } end
    local m, low, q = CP.Aggregate(samples, db.settings.share)
    if m then
        db.prices[itemID] = { m = m, n = low, q = q, t = now }
        CP.Quant.RecordOne(itemID, m, q, now)
    end
    -- 销量（只有拿到完整结果时才比较，否则没拿到的挂单会被误判为卖出）
    if full then
        local prev = db.quick[itemID]
        local gap = prev and prev.t and now - prev.t
        if prev and prev.full and gap and gap >= MIN_GAP and gap <= MAX_GAP then
            local sold = Qk.Compare(Qk.Decode(prev.s), list, gap)
            CP.Sales.AddObs(itemID, now, gap / 3600, sold, true)
        end
    end
    db.quick[itemID] = { t = now, s = Qk.Encode(list), full = full or nil }
    if m then Alert(itemID) end
end

local function Collect(itemID, isCommodity, itemKey)
    local list = {}
    if isCommodity then
        for i = 1, (C_AuctionHouse.GetNumCommoditySearchResults(itemID) or 0) do
            local r = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
            if r and r.auctionID and r.unitPrice and r.unitPrice > 0 and (r.quantity or 0) > 0 then
                list[#list + 1] = { id = r.auctionID, q = r.quantity, u = r.unitPrice,
                    l = r.timeLeftSeconds or -1, o = (r.containsOwnerItem or (r.numOwnerItems or 0) > 0) and true or false }
            end
        end
    else
        for i = 1, (C_AuctionHouse.GetNumItemSearchResults(itemKey) or 0) do
            local r = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
            if r and r.auctionID and r.buyoutAmount and r.buyoutAmount > 0 then
                local qty = (r.quantity and r.quantity > 0) and r.quantity or 1
                local left = r.timeLeftSeconds or CP.Sales.MinSecondsLeft(r.timeLeft)
                list[#list + 1] = { id = r.auctionID, q = qty, u = r.buyoutAmount / qty, l = left, o = r.containsOwnerItem and true or false }
            end
        end
    end
    return list
end

local function HasFull(isCommodity, itemID, itemKey)
    local fn = isCommodity and C_AuctionHouse.HasFullCommoditySearchResults or C_AuctionHouse.HasFullItemSearchResults
    if not fn then return true end
    local ok, full = pcall(fn, isCommodity and itemID or itemKey)
    return not ok or full and true or false
end

local function OnResults(isCommodity, itemID, itemKey)
    if not cur or cur.id ~= itemID then return end
    if not HasFull(isCommodity, itemID, itemKey) and cur.more < MAX_MORE then
        cur.more = cur.more + 1
        cur.deadline = GetTime() + TIMEOUT
        local fn = isCommodity and C_AuctionHouse.RequestMoreCommoditySearchResults or C_AuctionHouse.RequestMoreItemSearchResults
        if fn then
            sending = true
            pcall(fn, isCommodity and itemID or itemKey)
            sending = false
            return
        end
    end
    local full = HasFull(isCommodity, itemID, itemKey)
    local ok, err = pcall(Qk.Process, itemID, Collect(itemID, isCommodity, itemKey), full)
    if not ok then CP.Print("快速扫描处理出错：" .. tostring(err)) end
    cur = nil
    Qk.done = Qk.done + 1
end

CP.On("COMMODITY_SEARCH_RESULTS_UPDATED", function(itemID)
    if CP.Secret(itemID) then return end
    OnResults(true, itemID, nil)
end)
CP.On("ITEM_SEARCH_RESULTS_UPDATED", function(itemKey)
    if not itemKey or CP.Secret(itemKey) then return end
    OnResults(false, itemKey.itemID, itemKey)
end)
CP.On("AUCTION_HOUSE_CLOSED", function()
    Qk.state, cur, queue = "idle", nil, nil
end)
CP.On("AUCTION_HOUSE_SHOW", function()
    nextRound = 0 -- 打开拍卖行立刻扫一轮
end)

-- ---------------------------------------------------------------- 调度
local function UserBusy()
    if GetTime() - userAt < USER_PAUSE then return true end
    -- 你正在购买界面时不要打扰
    local f, modes = AuctionHouseFrame, AuctionHouseFrameDisplayMode
    if f and f.GetDisplayMode and modes then
        local ok, mode = pcall(f.GetDisplayMode, f)
        if ok and mode and (mode == modes.CommoditiesBuy or mode == modes.ItemBuy) then return true end
    end
    return false
end

local function WatchList()
    local ids = {}
    for id in pairs(CP.db.watch) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
end

function Qk.Tick()
    local s = CP.db and CP.db.settings
    if not s or not s.quickScan or not CP.auctionOpen then return end
    if not C_AuctionHouse or not C_AuctionHouse.SendSearchQuery or not C_AuctionHouse.MakeItemKey then return end
    if CP.Scan.state ~= "idle" or InCombatLockdown() or UserBusy() then return end
    local now = GetTime()
    if Qk.state == "idle" then
        if now < nextRound then return end
        local ids = WatchList()
        if #ids == 0 then nextRound = now + 5; return end
        queue, Qk.state, Qk.roundStart, Qk.done, Qk.total = ids, "running", now, 0, #ids
        return
    end
    -- running
    if cur then
        if now > cur.deadline then cur = nil; Qk.done = Qk.done + 1 end -- 超时，跳过
        return
    end
    local id = table.remove(queue, 1)
    if not id then
        Qk.state = "idle"
        nextRound = Qk.roundStart + math.max(30, s.quickInterval or 60)
        CP.Refresh()
        return
    end
    if C_AuctionHouse.IsThrottledMessageSystemReady and not C_AuctionHouse.IsThrottledMessageSystemReady() then
        table.insert(queue, 1, id) -- 服务器还没准备好，下次再发
        return
    end
    cur = { id = id, deadline = now + TIMEOUT, more = 0 }
    sending = true
    local ok = pcall(C_AuctionHouse.SendSearchQuery, C_AuctionHouse.MakeItemKey(id), SORTS, false)
    sending = false
    if not ok then cur = nil; Qk.done = Qk.done + 1 end
end

function Qk.Status()
    local s = CP.db.settings
    if not s.quickScan then return "|cff808080已关闭|r" end
    if not CP.auctionOpen then return "|cff808080等待打开拍卖行|r" end
    if next(CP.db.watch) == nil then return "|cffff8040没有关注的材料|r" end
    if CP.Scan.state ~= "idle" then return "全扫描中，暂停" end
    if UserBusy() then return "|cffffcc33你在操作，暂停|r" end
    if Qk.state == "running" then return string.format("|cff40ff40扫描中 %d/%d|r", Qk.done, Qk.total) end
    return string.format("下次 %d 秒", math.max(0, math.ceil(nextRound - GetTime())))
end

local ticker = CreateFrame("Frame")
local acc = 0
ticker:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 0.2 then return end
    acc = 0
    local ok, err = pcall(Qk.Tick)
    if not ok then CP.Print("快速扫描出错：" .. tostring(err)) end
end)

table.insert(CP.inits, function()
    -- 你自己在拍卖行搜索/购买时，记下时间，让快速扫描让路
    if C_AuctionHouse then
        for _, name in ipairs({ "SendBrowseQuery", "SendSearchQuery", "SendSellSearchQuery", "StartCommoditiesPurchase", "PlaceBid" }) do
            if type(C_AuctionHouse[name]) == "function" then
                hooksecurefunc(C_AuctionHouse, name, function()
                    if not sending then userAt = GetTime() end
                end)
            end
        end
    end
end)

-- 测试用
function Qk._Reset()
    nextRound, cur, queue, userAt = 0, nil, nil, -1000
    Qk.state = "idle"
    for k in pairs(alerted) do alerted[k] = nil end
end
