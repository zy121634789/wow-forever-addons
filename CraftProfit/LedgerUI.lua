-- 实时收支窗口：迷你条（一行）/ 详细模式
local _, CP = ...
local L = CP.Ledger

local LOG_ROWS = 8
local CAT_ROWS = #L.CATS
local WIDTH = 300

local win

local function Signed(v, short)
    if not v then return "|cff808080--|r" end
    local color = v > 0 and "|cff40ff40+" or (v < 0 and "|cffff5050" or "|cffcccccc")
    return color .. CP.Money(v, short) .. "|r"
end

local function Duration(secs)
    secs = math.floor(secs)
    local h, m = math.floor(secs / 3600), math.floor((secs % 3600) / 60)
    if h > 0 then return h .. "小时" .. m .. "分" end
    return m .. "分钟"
end

local PERIODS = { { key = "session", label = "本次" }, { key = "today", label = "今日" }, { key = "week", label = "7天" }, { key = "month", label = "30天" } }

local function PeriodData(key)
    if key == "session" then return L.session end
    if key == "today" then return L.Days(1) end
    if key == "week" then return L.Days(7) end
    return L.Days(30)
end

local function Update()
    if not win or not win:IsShown() then return end
    local s = CP.db.settings
    local sess = L.session
    local net = sess.inc - sess.exp
    local ph = L.PerHour()

    win.mini:SetText("收支 " .. Signed(net, true) .. "  |cff999999每小时|r " .. Signed(ph, true))

    if s.ledgerMini then return end

    local period = s.ledgerPeriod or "session"
    local d = PeriodData(period)
    local lines = {}
    if period == "session" then
        lines[#lines + 1] = "本次登录 " .. Duration(GetTime() - (sess.start or GetTime()))
            .. "　每小时 " .. Signed(ph, true)
    end
    lines[#lines + 1] = "全账号今日 " .. Signed(L.AccountToday(), true)
        .. "　当前金币 " .. CP.Money(GetMoney(), true)
    win.info:SetText(table.concat(lines, "\n"))

    for _, b in ipairs(win.tabs) do
        b:SetEnabled(b.key ~= period)
    end

    -- 分类表：只显示有发生的分类
    local i = 0
    for _, c in ipairs(L.CATS) do
        local v = d.cats[c.key]
        if v and (v.inc > 0 or v.exp > 0) then
            i = i + 1
            local row = win.cats[i]
            row.name:SetText(c.name)
            row.inc:SetText(v.inc > 0 and ("|cff40ff40" .. CP.Money(v.inc, true) .. "|r") or "")
            row.exp:SetText(v.exp > 0 and ("|cffff5050" .. CP.Money(v.exp, true) .. "|r") or "")
            row:Show()
        end
    end
    for j = i + 1, CAT_ROWS do win.cats[j]:Hide() end
    win.empty:SetShown(i == 0)

    win.totalInc:SetText("|cff40ff40" .. CP.Money(d.inc, true) .. "|r")
    win.totalExp:SetText("|cffff5050" .. CP.Money(d.exp, true) .. "|r")
    win.net:SetText("净收益 " .. Signed(d.inc - d.exp))
    -- 拍卖生意：卖出 − 购买 − 押金
    local sale = d.cats.ah_sale and d.cats.ah_sale.inc or 0
    local buy = (d.cats.ah_buy and (d.cats.ah_buy.exp - d.cats.ah_buy.inc) or 0)
    local fee = d.cats.ah_fee and d.cats.ah_fee.exp or 0
    win.ah:SetText((sale > 0 or buy ~= 0 or fee > 0) and ("拍卖行合计 " .. Signed(sale - buy - fee, true)) or "")

    -- 最近明细
    local log = L.Store().log
    for k = 1, LOG_ROWS do
        local e, row = log[k], win.log[k]
        if e then
            row.time:SetText(date("%H:%M", e.t))
            row.amount:SetText(Signed(e.d, true))
            row.what:SetText(L.CAT_NAME[e.c] .. (e.n and ("|cff999999 " .. e.n .. "|r") or ""))
            row:Show()
        else
            row:Hide()
        end
    end
end
L.OnChange = Update
CP.LedgerUpdate = Update

local function Layout()
    local mini = CP.db.settings.ledgerMini
    win.body:SetShown(not mini)
    if mini then
        win:SetSize(230, 26)
        win.mini:ClearAllPoints()
        win.mini:SetPoint("LEFT", 8, 0)
    else
        win:SetSize(WIDTH, 132 + CAT_ROWS * 16 + 36 + LOG_ROWS * 16)
        win.mini:ClearAllPoints()
        win.mini:SetPoint("TOPLEFT", 10, -8)
    end
    win.toggle:SetText(mini and "+" or "-")
    Update()
end

local function Create()
    win = CreateFrame("Frame", "CraftProfitLedger", UIParent, "BackdropTemplate")
    win:SetFrameStrata("MEDIUM")
    win:SetClampedToScreen(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        CP.db.settings.ledgerPos = { p, rp, x, y }
    end)
    if win.SetBackdrop then
        win:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        win:SetBackdropColor(0, 0, 0, 0.8)
        win:SetBackdropBorderColor(0.4, 0.7, 0.9, 1)
    end
    local pos = CP.db.settings.ledgerPos
    if pos then
        win:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        win:SetPoint("TOP", UIParent, "TOP", 0, -120)
    end
    win:Hide()

    win.mini = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    win.mini:SetJustifyH("LEFT")

    win.toggle = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    win.toggle:SetSize(20, 18)
    win.toggle:SetPoint("TOPRIGHT", -26, -4)
    win.toggle:SetScript("OnClick", function()
        CP.db.settings.ledgerMini = not CP.db.settings.ledgerMini
        Layout()
    end)
    local close = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    close:SetSize(20, 18)
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetText("x")
    close:SetScript("OnClick", function() CP.ToggleLedger(false) end)

    -- 详细区
    local body = CreateFrame("Frame", nil, win)
    body:SetPoint("TOPLEFT", 0, -28)
    body:SetPoint("BOTTOMRIGHT")
    win.body = body

    win.tabs = {}
    for i, p in ipairs(PERIODS) do
        local b = CreateFrame("Button", nil, body, "UIPanelButtonTemplate")
        b:SetSize(54, 20)
        b:SetPoint("TOPLEFT", 10 + (i - 1) * 58, -2)
        b:SetText(p.label)
        b.key = p.key
        b:SetScript("OnClick", function()
            CP.db.settings.ledgerPeriod = p.key
            Update()
        end)
        win.tabs[i] = b
    end

    win.info = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.info:SetPoint("TOPLEFT", 12, -28)
    win.info:SetJustifyH("LEFT")

    local function Header(text, x, justify, width)
        local fs = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", x, -62)
        fs:SetWidth(width); fs:SetJustifyH(justify); fs:SetText(text)
    end
    Header("分类", 12, "LEFT", 100)
    Header("收入", 112, "RIGHT", 85)
    Header("支出", 200, "RIGHT", 85)

    win.cats = {}
    for i = 1, CAT_ROWS do
        local row = CreateFrame("Frame", nil, body)
        row:SetSize(WIDTH - 24, 16)
        row:SetPoint("TOPLEFT", 12, -78 - (i - 1) * 16)
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT"); row.name:SetWidth(100); row.name:SetJustifyH("LEFT")
        row.inc = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.inc:SetPoint("LEFT", 100, 0); row.inc:SetWidth(85); row.inc:SetJustifyH("RIGHT")
        row.exp = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.exp:SetPoint("LEFT", 188, 0); row.exp:SetWidth(85); row.exp:SetJustifyH("RIGHT")
        win.cats[i] = row
    end
    win.empty = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    win.empty:SetPoint("TOPLEFT", 12, -80)
    win.empty:SetText("还没有收支记录")

    local totalY = -78 - CAT_ROWS * 16 - 4
    local totalLabel = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    totalLabel:SetPoint("TOPLEFT", 12, totalY); totalLabel:SetText("合计")
    win.totalInc = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.totalInc:SetPoint("TOPLEFT", 112, totalY); win.totalInc:SetWidth(85); win.totalInc:SetJustifyH("RIGHT")
    win.totalExp = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.totalExp:SetPoint("TOPLEFT", 200, totalY); win.totalExp:SetWidth(85); win.totalExp:SetJustifyH("RIGHT")
    win.net = body:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    win.net:SetPoint("TOPLEFT", 12, totalY - 18)
    win.ah = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.ah:SetPoint("TOPRIGHT", -12, totalY - 20)

    local logY = totalY - 44
    local logTitle = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    logTitle:SetPoint("TOPLEFT", 12, logY); logTitle:SetText("最近明细")
    win.log = {}
    for i = 1, LOG_ROWS do
        local row = CreateFrame("Frame", nil, body)
        row:SetSize(WIDTH - 24, 16)
        row:SetPoint("TOPLEFT", 12, logY - 16 - (i - 1) * 16)
        row.time = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.time:SetPoint("LEFT"); row.time:SetWidth(36); row.time:SetJustifyH("LEFT")
        row.amount = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.amount:SetPoint("LEFT", 36, 0); row.amount:SetWidth(84); row.amount:SetJustifyH("RIGHT")
        row.what = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.what:SetPoint("LEFT", 126, 0); row.what:SetWidth(WIDTH - 24 - 126)
        row.what:SetJustifyH("LEFT"); row.what:SetWordWrap(false)
        win.log[i] = row
    end

    -- 每 5 秒刷新一次（“每小时”和登录时长会随时间变化）
    local elapsed = 0
    win:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= 5 then elapsed = 0; Update() end
    end)
end

function CP.ToggleLedger(show)
    if not win then Create() end
    if show == nil then show = not win:IsShown() end
    CP.db.settings.ledgerShown = show
    if show then
        win:Show()
        Layout()
    else
        win:Hide()
    end
end

table.insert(CP.inits, function()
    if CP.db.settings.ledgerShown then CP.ToggleLedger(true) end
end)
