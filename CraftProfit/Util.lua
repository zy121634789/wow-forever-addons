-- 公共工具：命名空间、事件分发、存档默认值、金钱/时间格式化
local ADDON, CP = ...
CP = CP or {}
CP.name = ADDON

-- ---------------------------------------------------------------- 输出
function CP.Print(msg)
    print("|cff33ccff[制造利润]|r " .. tostring(msg))
end

-- “无限”继承了正式服的“秘密值”机制：战斗中部分数据不可读
function CP.Secret(v)
    return issecretvalue ~= nil and issecretvalue(v) or false
end

function CP.Now()
    return (GetServerTime and GetServerTime()) or time()
end

-- ---------------------------------------------------------------- 事件
local eventFrame, handlers = CreateFrame("Frame"), {}
function CP.On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        eventFrame:RegisterEvent(event)
    end
    table.insert(handlers[event], fn)
end
eventFrame:SetScript("OnEvent", function(_, event, ...)
    for _, fn in ipairs(handlers[event]) do
        local ok, err = pcall(fn, ...)
        if not ok then CP.Print("|cffff4040出错|r " .. event .. ": " .. tostring(err)) end
    end
end)

-- 多个模块注册的“数据变了，刷新界面”回调；同一帧内多次调用只执行一次
CP.refreshers = {}
local refreshPending = false
function CP.Refresh()
    if refreshPending then return end
    refreshPending = true
    C_Timer.After(0, function()
        refreshPending = false
        CP.ClearCostCache()
        for _, fn in ipairs(CP.refreshers) do pcall(fn) end
    end)
end

-- ---------------------------------------------------------------- 存档
local DEFAULTS = {
    version = 1,
    prices = {},      -- [itemID] = { m = 市场价, n = 最低价, q = 在售数量, t = 时间 }
    vendor = {},      -- [itemID] = 商人单价（铜）
    recipes = {},     -- [recipeID] = { name, icon, prof, out, qmin, qmax, r = {{id, n}, ...} }
    sales = {},       -- [itemID] = { {t = 时间, h = 间隔小时, s = 估计卖出数}, ... }
    snap = nil,       -- 上次全扫描的挂单快照（只含配方相关物品），用于估算销量
    hist = {},        -- [itemID] = "时间:价格:数量,..." 价格历史（量化交易用）
    watch = {},       -- [itemID] = true 手动关注的物品
    quick = {},       -- [itemID] = { t, s = 挂单快照, full } 快速扫描的上次结果
    chars = {},       -- [角色-服务器] = { profs = { [professionID] = { name, ids = {recipeID...} } } }
    lastScan = 0,     -- 上次完成全扫描的时间
    lastRequest = 0,  -- 上次发起全扫描的时间（服务器 15 分钟冷却）
    settings = {
        cut = 0.05,        -- 拍卖行手续费
        share = 0.2,       -- 市场价取最便宜的多少比例的平均
        sort = "profit",   -- 面板排序字段
        hideUnknown = false,
        autoShow = true,   -- 打开专业窗口时自动显示面板
        panelPos = nil,    -- 面板被拖动后的位置
        ledgerShown = true,       -- 收支窗口是否显示
        ledgerMini = false,       -- 收支窗口是否为迷你条
        ledgerPeriod = "session", -- 收支窗口统计范围
        quantAlert = true,        -- 扫描后在聊天框提示交易机会
        quantFilter = "all",      -- 交易建议窗口筛选
        quickScan = true,         -- 拍卖行开着时快速扫描关注的材料
        quickInterval = 60,       -- 快速扫描间隔（秒）
        quickSound = true,        -- 快速扫描发现机会时播放提示音
    },
}

local function Merge(dst, src)
    if type(dst) ~= "table" then dst = {} end
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = Merge(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

function CP.CharKey()
    local name, realm = UnitFullName("player")
    realm = realm or GetRealmName() or "?"
    return (name or "?") .. "-" .. realm
end

function CP.CharDB()
    local key = CP.CharKey()
    CP.db.chars[key] = CP.db.chars[key] or { profs = {} }
    return CP.db.chars[key]
end

CP.inits = {}
CP.On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    CraftProfitDB = Merge(CraftProfitDB, DEFAULTS)
    CP.db = CraftProfitDB
end)
CP.On("PLAYER_LOGIN", function()
    for _, init in ipairs(CP.inits) do
        local ok, err = pcall(init)
        if not ok then CP.Print("|cffff4040初始化出错|r " .. tostring(err)) end
    end
end)

-- ---------------------------------------------------------------- 格式化
local GOLD = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"
local SILVER = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t"
local COPPER = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"

-- 金额（铜）→ “12金34银”。short=true 时金币够多就省略铜
function CP.Money(copper, short)
    if copper == nil then return "|cff808080--|r" end
    local neg = copper < 0
    copper = math.floor(math.abs(copper) + 0.5)
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. GOLD end
    if s > 0 and not (short and g >= 100) then parts[#parts + 1] = s .. SILVER end
    if (c > 0 or #parts == 0) and not (short and g > 0) then parts[#parts + 1] = c .. COPPER end
    return (neg and "-" or "") .. table.concat(parts, " ")
end

-- 秒数 → “3分钟前 / 2小时前 / 5天前”
function CP.Age(t)
    if not t or t <= 0 then return "从未" end
    local d = CP.Now() - t
    if d < 60 then return "刚刚" end
    if d < 3600 then return math.floor(d / 60) .. "分钟前" end
    if d < 86400 then return math.floor(d / 3600) .. "小时前" end
    return math.floor(d / 86400) .. "天前"
end

function CP.ItemName(itemID)
    local name
    if C_Item and C_Item.GetItemNameByID then name = C_Item.GetItemNameByID(itemID) end
    if not name and GetItemInfo then name = GetItemInfo(itemID) end
    if not name then
        if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
        return "物品#" .. itemID
    end
    return name
end

function CP.ItemIcon(itemID)
    if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(itemID) end
    return GetItemIcon and GetItemIcon(itemID)
end

-- 物品卖给商人的价格（铜）
function CP.VendorSell(itemID)
    local info = { (C_Item and C_Item.GetItemInfo or GetItemInfo)(itemID) }
    local sell = info[11]
    if type(sell) == "number" and sell > 0 then return sell end
    return nil
end

_G.CraftProfit = CP
