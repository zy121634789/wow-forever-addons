-- 交易建议窗口：材料列表 + 选中材料的 14 天走势图和分析
local _, CP = ...
local Q = CP.Quant

local ROWS, ROW_H = 12, 20
local COL = { name = 150, cur = 72, mean = 72, dev = 54, sold = 46, act = 80 }
local ROW_W = 18 + COL.name + COL.cur + COL.mean + COL.dev + COL.sold + COL.act + 8
local CHART_W, CHART_H, BARS = 210, 96, 14

local win

local function ItemLink(itemID)
    local _, link = (C_Item and C_Item.GetItemInfo or GetItemInfo)(itemID)
    return link
end

local function ActionText(a)
    local def = Q.ACTIONS[a.action] or Q.ACTIONS.hold
    return def.color .. def.label .. "|r"
end

local function DevText(st)
    if not st or not st.dev then return "|cff808080--|r" end
    local pct = st.dev * 100
    local color = pct <= -10 and "|cff40ff40" or (pct >= 10 and "|cffff6040" or "|cffcccccc")
    return color .. string.format("%+.0f%%", pct) .. "|r"
end

-- ---------------------------------------------------------------- 详情区
local function UpdateDetail()
    local d = win.detail
    local id = win.sel
    if not id then
        d.title:SetText("点击上方一行查看走势和分析")
        d.text:SetText("")
        for i = 1, BARS do d.bars[i]:Hide() end
        d.meanLine:Hide()
        win.watchBtn:Hide()
        return
    end
    local a = Q.Advise(id)
    local st = a.stats
    d.title:SetText(CP.ItemName(id) .. "　" .. ActionText(a) .. (CP.db.watch[id] and "　|cffffd100★关注|r" or ""))
    win.watchBtn:Show()
    win.watchBtn:SetText(CP.db.watch[id] and "取消关注" or "加关注")

    -- 文字
    local lines = {}
    if st and st.mean then
        lines[#lines + 1] = string.format("现价 %s　7日均价 %s", CP.Money(st.cur, true), CP.Money(st.mean, true))
        lines[#lines + 1] = string.format("7日区间 %s ~ %s　波动 ±%.0f%%", CP.Money(st.min, true), CP.Money(st.max, true), st.std / st.mean * 100)
        if st.pct then lines[#lines + 1] = string.format("现价处于 14 天的 %.0f%% 分位（0%%=最低）", st.pct * 100) end
        lines[#lines + 1] = string.format("在售 %d（平时 %d）　日销 %s　你有 %d",
            st.curQ or 0, math.floor((st.meanQ or 0) + 0.5), a.rate and string.format("%.0f", a.rate) or "?", a.owned)
    end
    lines[#lines + 1] = " "
    for _, r in ipairs(a.reasons) do lines[#lines + 1] = "· " .. r end
    d.text:SetText(table.concat(lines, "\n"))

    -- 走势图
    local bars = st and st.bars or {}
    local lo, hi = math.huge, 0
    for i = 1, BARS do
        local v = bars[i]
        if v then
            if v < lo then lo = v end
            if v > hi then hi = v end
        end
    end
    if hi == 0 then
        for i = 1, BARS do d.bars[i]:Hide() end
        d.meanLine:Hide()
        d.range:SetText("")
        return
    end
    local base = lo * 0.9
    local span = math.max(hi - base, 1)
    local def = Q.ACTIONS[a.action] or Q.ACTIONS.hold
    local bw = (CHART_W - (BARS - 1) * 2) / BARS
    for i = 1, BARS do
        local bar, v = d.bars[i], bars[i]
        if v then
            bar:SetSize(bw, math.max(2, (v - base) / span * CHART_H))
            bar:ClearAllPoints()
            bar:SetPoint("BOTTOMLEFT", d.chart, "BOTTOMLEFT", (i - 1) * (bw + 2), 0)
            if i == BARS then
                local r, g, b = tonumber(def.color:sub(5, 6), 16) / 255, tonumber(def.color:sub(7, 8), 16) / 255, tonumber(def.color:sub(9, 10), 16) / 255
                bar:SetColorTexture(r, g, b, 0.9)
            else
                bar:SetColorTexture(0.35, 0.6, 0.85, 0.8)
            end
            bar:Show()
        else
            bar:Hide()
        end
    end
    if st and st.mean and st.mean >= base then
        d.meanLine:ClearAllPoints()
        d.meanLine:SetPoint("BOTTOMLEFT", d.chart, "BOTTOMLEFT", 0, math.min(CHART_H, (st.mean - base) / span * CHART_H))
        d.meanLine:SetSize(CHART_W, 1)
        d.meanLine:Show()
    else
        d.meanLine:Hide()
    end
    d.range:SetText("最高 " .. CP.Money(hi, true) .. "\n最低 " .. CP.Money(lo, true))
end

-- ---------------------------------------------------------------- 列表
local function Update()
    if not win or not win:IsShown() then return end
    local filter = CP.db.settings.quantFilter or "all"
    local list = Q.All(filter)
    win.list = list
    local maxOffset = math.max(0, #list - ROWS)
    if win.offset > maxOffset then win.offset = maxOffset end

    local nMat = 0
    for _ in pairs(Q.Materials()) do nMat = nMat + 1 end
    win.status:SetText(string.format("盯盘 %d 种材料　上次全扫描：%s", nMat, CP.Age(CP.db.lastScan)))
    win.quickBox:SetChecked(CP.db.settings.quickScan)
    win.quickStatus:SetText(CP.Quick.Status())

    for i = 1, ROWS do
        local row, a = win.rows[i], list[win.offset + i]
        row.adv = a
        if a then
            local st = a.stats
            row.icon:SetTexture(CP.ItemIcon(a.itemID) or 134400)
            row.name:SetText((CP.db.watch[a.itemID] and "|cffffd100★|r" or "") .. CP.ItemName(a.itemID))
            row.cur:SetText(st and CP.Money(st.cur, true) or "|cff808080--|r")
            row.mean:SetText(st and st.mean and CP.Money(st.mean, true) or "|cff808080--|r")
            row.dev:SetText(DevText(st))
            row.sold:SetText(CP.Sales.Label(a.rate or CP.Sales.Rate(a.itemID)))
            row.act:SetText(ActionText(a))
            row.selected:SetShown(win.sel == a.itemID)
            row:Show()
        else
            row:Hide()
        end
    end
    win.empty:SetShown(#list == 0)
    win.pageText:SetText(#list == 0 and "" or string.format("%d-%d / 共 %d", win.offset + 1, math.min(#list, win.offset + ROWS), #list))
    for _, b in ipairs(win.filters) do b:SetEnabled(b.key ~= filter) end
    win.alertBox:SetChecked(CP.db.settings.quantAlert)
    UpdateDetail()
end
CP.QuantUpdate = Update
table.insert(CP.refreshers, Update)

local function Create()
    win = CreateFrame("Frame", "CraftProfitQuant", UIParent, "BasicFrameTemplateWithInset")
    local listBottom = 76 + ROWS * ROW_H
    win:SetSize(ROW_W + 24, listBottom + CHART_H + 92)
    win:SetFrameStrata("HIGH")
    win:SetToplevel(true)
    win:SetClampedToScreen(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        CP.db.settings.quantPos = { p, rp, x, y }
    end)
    local pos = CP.db.settings.quantPos
    if pos then win:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else win:SetPoint("CENTER", -200, 0) end
    win:Hide()
    win.offset = 0
    tinsert(UISpecialFrames, "CraftProfitQuant")

    local title = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", 0, -5)
    title:SetText("交易建议（量化）")

    win.filters = {}
    for i, f in ipairs({ { "all", "全部" }, { "buy", "买入" }, { "sell", "卖出" } }) do
        local b = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
        b:SetSize(50, 20)
        b:SetPoint("TOPLEFT", 12 + (i - 1) * 54, -30)
        b:SetText(f[2])
        b.key = f[1]
        b:SetScript("OnClick", function()
            CP.db.settings.quantFilter = f[1]
            win.offset = 0
            Update()
        end)
        win.filters[i] = b
    end
    win.status = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    win.status:SetPoint("TOPRIGHT", -14, -34)

    -- 列标题
    local x = 12
    for _, c in ipairs({ { "材料", COL.name + 18, "LEFT" }, { "现价", COL.cur, "RIGHT" }, { "7日均价", COL.mean, "RIGHT" },
        { "偏离", COL.dev, "RIGHT" }, { "日销", COL.sold, "RIGHT" }, { "建议", COL.act, "RIGHT" } }) do
        local fs = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", x, -58)
        fs:SetSize(c[2], 16)
        fs:SetJustifyH(c[3])
        fs:SetText(c[1])
        x = x + c[2]
    end

    win.rows = {}
    for i = 1, ROWS do
        local row = CreateFrame("Button", nil, win)
        row:SetSize(ROW_W, ROW_H)
        row:SetPoint("TOPLEFT", 12, -76 - (i - 1) * ROW_H)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.selected = row:CreateTexture(nil, "BACKGROUND")
        row.selected:SetAllPoints()
        row.selected:SetColorTexture(0.2, 0.5, 0.8, 0.25)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT")
        local function Cell(width, justify, anchor)
            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetSize(width, ROW_H); fs:SetJustifyH(justify); fs:SetWordWrap(false)
            fs:SetPoint("LEFT", anchor, "RIGHT", 2, 0)
            return fs
        end
        row.name = Cell(COL.name - 2, "LEFT", row.icon)
        row.cur = Cell(COL.cur - 2, "RIGHT", row.name)
        row.mean = Cell(COL.mean - 2, "RIGHT", row.cur)
        row.dev = Cell(COL.dev - 2, "RIGHT", row.mean)
        row.sold = Cell(COL.sold - 2, "RIGHT", row.dev)
        row.act = Cell(COL.act - 2, "RIGHT", row.sold)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnClick", function(self, button)
            if not self.adv then return end
            if button == "RightButton" then
                CP.ToggleWatch(self.adv.itemID)
                return
            end
            if IsShiftKeyDown() then
                local link = ItemLink(self.adv.itemID)
                if link and ChatFrameUtil and ChatFrameUtil.InsertLink then ChatFrameUtil.InsertLink(link)
                elseif link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
                return
            end
            win.sel = self.adv.itemID
            Update()
        end)
        win.rows[i] = row
    end
    win.empty = win:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    win.empty:SetPoint("TOPLEFT", 16, -84)
    win.empty:SetWidth(ROW_W - 10)
    win.empty:SetJustifyH("LEFT")
    win.empty:SetText("没有可显示的材料。先打开专业窗口让插件认识你的配方，再到拍卖行多做几次全扫描。")
    win:EnableMouseWheel(true)
    win:SetScript("OnMouseWheel", function(_, delta)
        local maxOffset = math.max(0, #(win.list or {}) - ROWS)
        win.offset = math.min(maxOffset, math.max(0, win.offset - delta * 3))
        Update()
    end)

    -- 详情区
    local d = {}
    win.detail = d
    local top = -(listBottom + 6)
    d.title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    d.title:SetPoint("TOPLEFT", 14, top)
    d.chart = CreateFrame("Frame", nil, win)
    d.chart:SetSize(CHART_W, CHART_H)
    d.chart:SetPoint("TOPLEFT", 14, top - 22)
    local bg = d.chart:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.35)
    d.bars = {}
    for i = 1, BARS do d.bars[i] = d.chart:CreateTexture(nil, "ARTWORK") end
    d.meanLine = d.chart:CreateTexture(nil, "OVERLAY")
    d.meanLine:SetColorTexture(1, 0.82, 0, 0.9)
    local axis = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    axis:SetPoint("TOPLEFT", d.chart, "BOTTOMLEFT", 0, -2)
    axis:SetWidth(CHART_W)
    axis:SetJustifyH("LEFT")
    axis:SetText("14天前　　　　　|cffffd100— 7日均价|r　　　今天")
    d.range = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    d.range:SetPoint("TOPLEFT", d.chart, "TOPRIGHT", 4, 0)
    d.range:SetJustifyH("LEFT")
    d.text = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    d.text:SetPoint("TOPLEFT", d.chart, "TOPRIGHT", 74, 0)
    d.text:SetWidth(ROW_W - CHART_W - 80)
    d.text:SetJustifyH("LEFT")
    d.text:SetJustifyV("TOP")
    d.text:SetSpacing(2)

    -- 底部
    win.alertBox = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
    win.alertBox:SetSize(22, 22)
    win.alertBox:SetPoint("BOTTOMLEFT", 10, 8)
    local alertLabel = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    alertLabel:SetPoint("LEFT", win.alertBox, "RIGHT", 2, 0)
    alertLabel:SetText("扫描后在聊天框提醒")
    win.alertBox:SetScript("OnClick", function(self)
        CP.db.settings.quantAlert = self:GetChecked() and true or false
    end)
    win.quickBox = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
    win.quickBox:SetSize(22, 22)
    win.quickBox:SetPoint("BOTTOMLEFT", 150, 8)
    local quickLabel = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    quickLabel:SetPoint("LEFT", win.quickBox, "RIGHT", 2, 0)
    quickLabel:SetText("快速扫描★关注")
    win.quickBox:SetScript("OnClick", function(self)
        CP.db.settings.quickScan = self:GetChecked() and true or false
        Update()
    end)
    win.quickBox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("快速扫描")
        GameTooltip:AddLine(string.format("拍卖行开着时，每 %d 秒搜索一遍加了★关注的材料，" ..
            "价格和销量更及时，出现买卖机会会立刻提醒。右键点列表里的材料可以加/取消关注。",
            CP.db.settings.quickInterval or 60), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    win.quickBox:SetScript("OnLeave", function() GameTooltip:Hide() end)
    win.quickStatus = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    win.quickStatus:SetPoint("LEFT", quickLabel, "RIGHT", 6, 0)

    win.pageText = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    win.pageText:SetPoint("TOPLEFT", 180, -34)
    win.watchBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    win.watchBtn:SetSize(80, 22)
    win.watchBtn:SetPoint("BOTTOMRIGHT", -10, 8)
    win.watchBtn:SetScript("OnClick", function()
        if win.sel then CP.ToggleWatch(win.sel) end
    end)

    win:SetScript("OnShow", Update)
    -- 每秒刷新快速扫描状态
    local acc = 0
    win:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 1 then return end
        acc = 0
        win.quickStatus:SetText(CP.Quick.Status())
    end)
end

function CP.ToggleWatch(itemID)
    if CP.db.watch[itemID] then
        CP.db.watch[itemID] = nil
        CP.Print("已取消关注 " .. CP.ItemName(itemID))
    else
        CP.db.watch[itemID] = true
        CP.Print("已关注 " .. CP.ItemName(itemID) .. "：拍卖行开着时每分钟快速扫描它，全扫描也会记录")
    end
    Update()
end

function CP.ToggleQuant(show)
    if not win then Create() end
    if show == nil then show = not win:IsShown() end
    if show then
        win:Show()
        Update()
    else
        win:Hide()
    end
end
