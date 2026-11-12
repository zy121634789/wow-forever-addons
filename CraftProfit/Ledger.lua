-- 收支记录：监听金币变化，根据当时打开的窗口/刚做的操作自动分类
local _, CP = ...

local L = {}
CP.Ledger = L

-- 分类（顺序即显示顺序）
L.CATS = {
    { key = "ah_sale",     name = "拍卖卖出" },
    { key = "ah_buy",      name = "拍卖购买" },
    { key = "ah_fee",      name = "拍卖押金" },
    { key = "vendor_sell", name = "卖给商人" },
    { key = "vendor_buy",  name = "商人购买" },
    { key = "repair",      name = "修理" },
    { key = "loot",        name = "拾取" },
    { key = "quest",       name = "任务" },
    { key = "mail",        name = "邮件" },
    { key = "trade",       name = "交易" },
    { key = "taxi",        name = "飞行" },
    { key = "trainer",     name = "训练师" },
    { key = "other",       name = "其他" },
}
L.CAT_NAME = {}
for _, c in ipairs(L.CATS) do L.CAT_NAME[c.key] = c.name end

local KEEP_DAYS = 60     -- 每日汇总保留天数
local KEEP_LOG = 100     -- 明细保留条数
local PENDING_TTL = 15   -- 操作发生后多少秒内的金币变化算它的
local CONTEXT_GRACE = 3  -- 窗口关闭后几秒内仍算这个窗口

-- ---------------------------------------------------------------- 状态
L.session = { start = nil, cats = {}, inc = 0, exp = 0 }
local lastMoney
local open, closedAt = {}, {}
local pending = {} -- { {sign, cat, note, t} ... } 先进先出

function L.Today(t)
    return date("%Y-%m-%d", t or time())
end

local function Store()
    local c = CP.CharDB()
    c.ledger = c.ledger or { days = {}, log = {} }
    return c.ledger
end
L.Store = Store

local function AddTo(bucket, cat, delta)
    bucket.cats[cat] = bucket.cats[cat] or { inc = 0, exp = 0 }
    if delta > 0 then
        bucket.cats[cat].inc = bucket.cats[cat].inc + delta
        bucket.inc = bucket.inc + delta
    else
        bucket.cats[cat].exp = bucket.cats[cat].exp - delta
        bucket.exp = bucket.exp - delta
    end
end

-- 记一笔（delta 单位：铜，正=收入 负=支出）
function L.Record(delta, cat, note)
    if delta == 0 then return end
    cat = L.CAT_NAME[cat] and cat or "other"
    local st = Store()
    local day = L.Today()
    st.days[day] = st.days[day] or { cats = {}, inc = 0, exp = 0 }
    AddTo(st.days[day], cat, delta)
    AddTo(L.session, cat, delta)
    table.insert(st.log, 1, { t = time(), d = delta, c = cat, n = note })
    while #st.log > KEEP_LOG do table.remove(st.log) end
    if L.OnChange then L.OnChange() end
end

-- 清理过期的每日数据
local function Prune()
    local st = Store()
    local cutoff = L.Today(time() - KEEP_DAYS * 86400)
    for day in pairs(st.days) do
        if day < cutoff then st.days[day] = nil end
    end
end

-- 汇总最近 n 天（含今天）
function L.Days(n, store)
    store = store or Store()
    local sum = { cats = {}, inc = 0, exp = 0 }
    for i = 0, n - 1 do
        local d = store.days[L.Today(time() - i * 86400)]
        if d then
            for cat, v in pairs(d.cats) do
                if v.inc > 0 then AddTo(sum, cat, v.inc) end
                if v.exp > 0 then AddTo(sum, cat, -v.exp) end
            end
        end
    end
    return sum
end

-- 全账号所有角色今天的净收益
function L.AccountToday()
    local net, day = 0, L.Today()
    for _, c in pairs(CP.db.chars) do
        local d = c.ledger and c.ledger.days[day]
        if d then net = net + d.inc - d.exp end
    end
    return net
end

-- 本次登录每小时净收益（登录不足 1 分钟时不计算）
function L.PerHour()
    local s = L.session
    if not s.start then return nil end
    local secs = GetTime() - s.start
    if secs < 60 then return nil end
    return (s.inc - s.exp) / secs * 3600
end

-- ---------------------------------------------------------------- 分类
-- 记下“接下来的一笔金币变化是什么”
function L.Expect(sign, cat, note)
    pending[#pending + 1] = { sign = sign, cat = cat, note = note, t = GetTime() }
end

local function TakePending(sign)
    local now = GetTime()
    local i = 1
    while i <= #pending do
        local p = pending[i]
        if now - p.t > PENDING_TTL then
            table.remove(pending, i)
        elseif p.sign == sign then
            table.remove(pending, i)
            return p
        else
            i = i + 1
        end
    end
end

local function Ctx(name)
    return open[name] or (closedAt[name] and GetTime() - closedAt[name] <= CONTEXT_GRACE)
end

function L.Classify(delta)
    local sign = delta > 0 and 1 or -1
    local p = TakePending(sign)
    if p then return p.cat, p.note end
    if Ctx("mail") then return "mail" end
    if Ctx("auction") then return delta < 0 and "ah_buy" or "other" end
    if Ctx("merchant") then return delta > 0 and "vendor_sell" or "vendor_buy" end
    if Ctx("trade") then return "trade" end
    if Ctx("taxi") and delta < 0 then return "taxi" end
    if Ctx("trainer") and delta < 0 then return "trainer" end
    if Ctx("quest") and delta > 0 then return "quest" end
    if Ctx("loot") and delta > 0 then return "loot" end
    return "other"
end

local function OnMoney()
    local money = GetMoney()
    if CP.Secret(money) then return end
    if lastMoney == nil then lastMoney = money; return end
    local delta = money - lastMoney
    lastMoney = money
    if delta == 0 then return end
    local cat, note = L.Classify(delta)
    L.Record(delta, cat, note)
end

-- ---------------------------------------------------------------- 上下文事件
local PAIRS = {
    mail     = { "MAIL_SHOW", "MAIL_CLOSED" },
    auction  = { "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED" },
    merchant = { "MERCHANT_SHOW", "MERCHANT_CLOSED" },
    trade    = { "TRADE_SHOW", "TRADE_CLOSED" },
    taxi     = { "TAXIMAP_OPENED", "TAXIMAP_CLOSED" },
    trainer  = { "TRAINER_SHOW", "TRAINER_CLOSED" },
    quest    = { "QUEST_COMPLETE", "QUEST_FINISHED" },
    loot     = { "LOOT_OPENED", "LOOT_CLOSED" },
}

local function Hook(tbl, key, fn)
    if type(tbl) == "table" and type(tbl[key]) == "function" then
        pcall(hooksecurefunc, tbl, key, fn)
    end
end

local function ItemNameSafe(itemID)
    return itemID and CP.ItemName(itemID) or "?"
end

-- 收邮件里的钱：拍卖行卖出的邮件可以读到卖了什么
local function OnTakeMail(index)
    local cat, note = "mail", nil
    if GetInboxInvoiceInfo then
        local ok, invoiceType, itemName = pcall(GetInboxInvoiceInfo, index)
        if ok and invoiceType == "seller" then
            cat, note = "ah_sale", itemName
        elseif ok and invoiceType == "buyer" then
            cat, note = "ah_buy", itemName -- 竞拍被超过退回的钱等
        end
    end
    if not note and GetInboxHeaderInfo then
        local ok, _, _, sender, subject = pcall(GetInboxHeaderInfo, index)
        if ok then note = subject or sender end
    end
    -- 退回的竞拍金是收入，但归到拍卖类；实际金额由 PLAYER_MONEY 给出
    L.Expect(1, cat, note)
end

local function InstallHooks()
    -- 邮件
    Hook(_G, "TakeInboxMoney", OnTakeMail)
    Hook(_G, "AutoLootMailItem", function(index)
        local money
        if GetInboxHeaderInfo then
            local ok, _, _, _, _, m = pcall(GetInboxHeaderInfo, index)
            if ok then money = m end
        end
        if money and money > 0 then OnTakeMail(index) end
    end)
    -- 商人
    Hook(_G, "RepairAllItems", function(guildBank)
        if not guildBank then L.Expect(-1, "repair") end
    end)
    Hook(_G, "BuyMerchantItem", function(index, qty)
        local name
        if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
            local ok, info = pcall(C_MerchantFrame.GetItemInfo, index)
            name = ok and type(info) == "table" and info.name or nil
        end
        if not name and GetMerchantItemInfo then name = GetMerchantItemInfo(index) end
        L.Expect(-1, "vendor_buy", name and (name .. (qty and qty > 1 and (" ×" .. qty) or "")) or nil)
    end)
    -- 拍卖行
    if C_AuctionHouse then
        Hook(C_AuctionHouse, "ConfirmCommoditiesPurchase", function(itemID, qty)
            L.Expect(-1, "ah_buy", ItemNameSafe(itemID) .. " ×" .. tostring(qty or 1))
        end)
        Hook(C_AuctionHouse, "PlaceBid", function() L.Expect(-1, "ah_buy") end)
        Hook(C_AuctionHouse, "PostItem", function() L.Expect(-1, "ah_fee", "上架押金") end)
        Hook(C_AuctionHouse, "PostCommodity", function(itemLocation, duration, qty)
            L.Expect(-1, "ah_fee", "上架押金")
        end)
        Hook(C_AuctionHouse, "CancelAuction", function() L.Expect(-1, "ah_fee", "取消拍卖") end)
    end
end

CP.On("QUEST_TURNED_IN", function(questID, xp, money)
    if money and money > 0 then
        local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)
        L.Expect(1, "quest", title)
    end
end)

table.insert(CP.inits, function()
    local st = Store()
    st.days, st.log = st.days or {}, st.log or {}
    Prune()
    L.session.start = GetTime()
    lastMoney = GetMoney()
    for name, ev in pairs(PAIRS) do
        CP.On(ev[1], function() open[name] = true; closedAt[name] = nil end)
        CP.On(ev[2], function() open[name] = nil; closedAt[name] = GetTime() end)
    end
    InstallHooks()
    CP.On("PLAYER_MONEY", OnMoney)
end)

-- 测试用：重置内部状态
function L._Reset()
    L.session = { start = GetTime(), cats = {}, inc = 0, exp = 0 }
    pending, open, closedAt = {}, {}, {}
    lastMoney = GetMoney()
end
