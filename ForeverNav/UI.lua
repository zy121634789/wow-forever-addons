-- 界面：导航窗口（左地图 + 右侧边栏）、顶部导航条、世界地图按钮、命令
local _, NS = ...
local D, G, MV = NS.Data, NS.Graph, NS.MapView

local W, H = 1060, 660
local SIDE_W = 340
local MAP_W, MAP_H = W - SIDE_W - 36, H - 70
local RESULT_ROWS, STEP_ROWS = 6, 5
local ROW_H, STEP_H = 23, 33

-- 侧边栏从上到下的位置（像素，向下为负），底部按钮区单独从底边往上排
local Y = {
    loc = 0, status = -18, search = -38, cats = -64, charRow = -88,
    results = -110,
}
Y.resMore = Y.results - RESULT_ROWS * ROW_H - 2
Y.sep = Y.resMore - 14
Y.goalName = Y.sep - 4
Y.goalInfo = Y.goalName - 22
Y.modes = Y.goalInfo - 50        -- 目的地说明最多 3 行
Y.summary = Y.modes - 26
Y.steps = Y.summary - 20

local ICON = {
    travel = "Interface\\Icons\\Ability_Mount_RidingHorse", fly = "Interface\\Icons\\Ability_Hunter_EagleEye",
    hearth = "Interface\\Icons\\INV_Misc_Rune_01", boat = "Interface\\Icons\\INV_Misc_Spyglass_02",
    zeppelin = "Interface\\Icons\\INV_Gizmo_02", skyboat = "Interface\\Icons\\INV_Gizmo_02", tram = "Interface\\Icons\\INV_Gizmo_01",
}
local function StepIcon(st)
    if st.kind == "ride" then return ICON[st.routeType] or ICON.boat end
    return ICON[st.kind] or ICON.travel
end
local function StepTime(st)
    if st.kind == "ride" then return string.format("等%s+%s", G.Fmt(st.wait):gsub("约", ""), G.Fmt(st.travel):gsub("约", "")) end
    return G.Fmt(st.time)
end
local function Hex(c) return string.format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255) end
local function Yards(d)
    if not d then return "" end
    if d >= 1000 then return string.format("%.1f千码", d / 1000) end
    return string.format("%d码", math.floor(d + 0.5))
end

local CATS = {
    { key = "all", label = "全部" }, { key = "dungeon", label = "副本" }, { key = "raid", label = "团本" },
    { key = "stop", label = "码头" }, { key = "flight", label = "鸟点" }, { key = "fav", label = "收藏" },
}
local KIND_ICON = { dungeon = "|A:Dungeon:14:14|a", raid = "|A:Raid:14:14|a", stop = "|TInterface\\Icons\\INV_Misc_Spyglass_02:14|t",
    flight = "|cff4dff66●|r", fav = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:14|t", zone = "|cffffd100◆|r" }

local win, hud

-- ---------------------------------------------------------------- 工具
local function CurrentPlan()
    return win.res and (win.res[win.mode] or win.res.fast)
end
local function Navigating() return NS.nav and NS.nav.goal == win.goal and NS.nav end

local function RefreshMap(fit)
    local map = win.map
    local nav = Navigating()
    -- 鸟点显示所选角色
    local viewKey = NS.db.settings.viewChar
    local c = viewKey and NS.db.chars[viewKey] or NS.Taxi.Char()
    map.known = c.known
    map.showUnknownFlights = win.cat == "flight"
    map.filters = win.filters
    MV.SetRoute(map, nav and nav.plan or CurrentPlan(), nav and nav.step, win.res and win.res.goalName, fit)
end

-- ---------------------------------------------------------------- 侧边栏：结果列表
local function RefreshResults()
    local s = win.side
    local cat = win.cat
    local list = NS.Search(s.search:GetText(), cat ~= "all" and cat or nil)
    if cat == "all" and s.search:GetText() == "" then
        -- 没输入时“全部”显示副本+团本
        local l2 = {}
        for _, it in ipairs(NS.Search("", "dungeon")) do l2[#l2 + 1] = it end
        for _, it in ipairs(NS.Search("", "raid")) do l2[#l2 + 1] = it end
        list = l2
    end
    s.results = list
    local maxOff = math.max(0, #list - RESULT_ROWS)
    if s.resOffset > maxOff then s.resOffset = maxOff end
    for i = 1, RESULT_ROWS do
        local row, it = s.resRows[i], list[s.resOffset + i]
        if it then
            row.it = it
            row.name:SetText((KIND_ICON[it.kind] or "") .. " " .. it.name)
            row.sub:SetText(it.sub or "")
            row.sel:SetShown(win.goal == it.node)
            row:Show()
        else
            row:Hide()
        end
    end
    s.resMore:SetText(#list > RESULT_ROWS and string.format("%d-%d / %d", s.resOffset + 1, math.min(#list, s.resOffset + RESULT_ROWS), #list) or (#list == 0 and "没有结果" or ""))
    for _, b in ipairs(s.catBtns) do b:SetEnabled(b.key ~= cat) end
    -- 鸟点分类：角色切换
    s.charRow:SetShown(cat == "flight")
    if cat == "flight" then
        local key = NS.db.settings.viewChar or select(2, NS.Taxi.Char())
        local c = NS.db.chars[key]
        local n = 0
        if c then for _ in pairs(c.known) do n = n + 1 end end
        s.charText:SetText(string.format("%s%s|r  已解锁 %d 个", c and c.faction == "Horde" and "|cffff6060" or "|cff66aaff", key:gsub("%-.*", ""), n))
    end
end

-- ---------------------------------------------------------------- 侧边栏：路线
local function RefreshSteps()
    local s = win.side
    local plan = Navigating() and NS.nav.plan or CurrentPlan()
    local steps = plan and plan.steps or {}
    local nav = Navigating()
    local maxOff = math.max(0, #steps - STEP_ROWS)
    if s.stepOffset > maxOff then s.stepOffset = maxOff end
    for i = 1, STEP_ROWS do
        local row, idx = s.stepRows[i], s.stepOffset + i
        local st = steps[idx]
        if st then
            local cur = nav and nav.step == idx
            local done = nav and nav.step > idx
            row.icon:SetTexture(StepIcon(st))
            row.icon:SetDesaturated(done and true or false)
            -- 固定两行：第一行做什么，第二行时间和提示；放不下显示省略号，鼠标移上去看全文
            row.text:SetText((done and "|cff777777" or (cur and "|cff40ff40" or "|cffffffff")) .. idx .. ". " .. st.text .. "|r")
            row.time:SetText("|cffffd100" .. StepTime(st) .. "|r" .. (st.note and ("  |cffffcc33" .. st.note .. "|r") or ""))
            row.st = st
            row.bg:SetColorTexture(cur and 0.1 or 1, cur and 0.4 or 1, cur and 0.15 or 1, cur and 0.5 or (idx % 2 == 0 and 0.05 or 0.02))
            row:Show()
        else
            row:Hide()
        end
    end
    s.stepMore:SetText(#steps > STEP_ROWS and string.format("滚轮翻页 %d/%d", math.min(#steps, s.stepOffset + STEP_ROWS), #steps) or "")
end

local function RefreshRoute()
    local s = win.side
    local res = win.res
    -- 目的地卡片
    if win.goal then
        local kind, key = win.goal:sub(1, 1), win.goal:sub(3)
        local p = kind == "D" and G.POI[key]
        s.goalName:SetText((p and (KIND_ICON[p.kind] .. " ") or "") .. (res and res.goalName or G.NodeName(win.goal)))
        local info = {}
        if p then
            info[#info + 1] = G.ZoneName(p.zone) .. " · " .. p.lv .. (p.new and " · |cff66ddff无限新副本|r" or "")
            if p.open then info[#info + 1] = "|cffffcc33" .. p.open .. "|r" end
            if p.hint then info[#info + 1] = "|cffbbbbbb" .. p.hint .. "|r" end
            if not p.x then info[#info + 1] = "|cffff9933入口坐标未收录：导航到所在地区，按提示找入口|r" end
        end
        s.goalInfo:SetText(table.concat(info, "\n"))
    else
        s.goalName:SetText("|cff999999选一个目的地|r")
        s.goalInfo:SetText("在上面搜索，或点地图上的图标；\n右键点地图任意位置，可以导航到那里。")
    end
    for _, b in ipairs(s.modeBtns) do
        local p = res and res[b.mode]
        b:SetText(G.MODES[b.mode].label .. (p and (" " .. G.Fmt(p.time)) or ""))
        b:SetEnabled(res ~= nil and win.mode ~= b.mode)
    end
    local plan = CurrentPlan()
    if plan then
        local parts = { G.Fmt(plan.time) }
        parts[#parts + 1] = plan.boards > 0 and ("换乘 " .. plan.boards .. " 次") or "不用坐船"
        if plan.flights > 0 then parts[#parts + 1] = "坐鸟 " .. plan.flights .. " 次" end
        s.summary:SetText(table.concat(parts, " · "))
        s.startBtn:Enable()
        s.startBtn:SetText(Navigating() and "重新规划" or "开始导航")
    else
        s.summary:SetText(win.err and ("|cffff6060" .. win.err .. "|r") or "")
        s.startBtn:Disable()
        s.startBtn:SetText("开始导航")
    end
    s.stopBtn:SetEnabled(NS.nav ~= nil)
    RefreshSteps()
end

local function UpdateStatus()
    if not win or not win:IsShown() then return end
    local s = win.side
    local zoneNode, stopNode = NS.CurrentNode()
    local sub = GetSubZoneText and GetSubZoneText() or ""
    s.loc:SetText("|cff66ddff你在|r " .. (zoneNode and G.NodeName(zoneNode) or "|cffff5050未知|r") .. (sub ~= "" and (" · " .. sub) or ""))
    local h, bind = NS.Hearth()
    local c = NS.Taxi.Char()
    local n = 0
    for _ in pairs(c.known) do n = n + 1 end
    s.status:SetText(string.format("|cff999999炉石 %s · 鸟点 %s · 速度 %.0f码/秒|r",
        h and (h.name .. (h.wait > 0 and ("(" .. math.ceil(h.wait) .. "分)") or "")) or (bind or "无"),
        n > 0 and (n .. "个") or "|cffffcc33未同步|r", NS.Geo.Speed()))
end

-- ---------------------------------------------------------------- 选择目的地
function NS.SetGoal(goal, keepView)
    if not win then NS.CreateWindow() end
    win.goal = goal
    win.mode = NS.db.settings.mode
    win.res, win.err = NS.PlanBoth(goal)
    win.side.stepOffset = 0
    if not win:IsShown() then win:Show() end
    RefreshResults()
    RefreshRoute()
    RefreshMap(not keepView)
end

local function Replan()
    if win and win.goal then win.res, win.err = NS.PlanBoth(win.goal) end
    if win then RefreshRoute(); RefreshMap(false) end
end

-- ---------------------------------------------------------------- 创建窗口
local function Check(parent, text, key, x, y, onClick)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetPoint("TOPLEFT", x, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", cb, "RIGHT", 0, 0)
    fs:SetText(text)
    cb:SetChecked(NS.db.settings[key])
    cb:SetScript("OnClick", function(self)
        NS.db.settings[key] = self:GetChecked() and true or false
        if onClick then onClick() end
    end)
    return cb
end

local function OneLine(fs, width)
    fs:SetWidth(width)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    if fs.SetMaxLines then fs:SetMaxLines(1) end
end

local function BuildSide(side)
    local s = side
    s.loc = side:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    s.loc:SetPoint("TOPLEFT", 0, Y.loc)
    OneLine(s.loc, SIDE_W)
    s.status = side:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    s.status:SetPoint("TOPLEFT", 0, Y.status)
    OneLine(s.status, SIDE_W)

    s.search = CreateFrame("EditBox", nil, side, "InputBoxTemplate")
    s.search:SetSize(SIDE_W - 8, 22)
    s.search:SetPoint("TOPLEFT", 6, Y.search)
    s.search:SetAutoFocus(false)
    local ph = side:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ph:SetPoint("LEFT", s.search, "LEFT", 2, 0)
    ph:SetText("搜索副本、团本、地区，如 死矿")
    local function UpdatePH() ph:SetShown(s.search:GetText() == "" and not s.search:HasFocus()) end
    s.search:SetScript("OnTextChanged", function() s.resOffset = 0; UpdatePH(); RefreshResults() end)
    s.search:SetScript("OnEditFocusGained", UpdatePH)
    s.search:SetScript("OnEditFocusLost", UpdatePH)
    s.search:SetScript("OnEnterPressed", function(self)
        local it = s.results and s.results[1]
        if it then NS.SetGoal(it.node) end
        self:ClearFocus()
    end)
    s.search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)

    s.catBtns = {}
    local bw = (SIDE_W - 2 * (#CATS - 1)) / #CATS
    for i, c in ipairs(CATS) do
        local b = CreateFrame("Button", nil, side, "UIPanelButtonTemplate")
        b:SetSize(bw, 20)
        b:SetPoint("TOPLEFT", (i - 1) * (bw + 2), Y.cats)
        b:SetText(c.label)
        b.key = c.key
        b:SetScript("OnClick", function()
            win.cat = c.key
            s.resOffset = 0
            win.filters = {}
            if c.key ~= "all" then
                for _, k in ipairs({ "dungeon", "raid", "stop", "flight", "fav" }) do win.filters[k] = (k == c.key) end
            end
            RefreshResults()
            RefreshMap(false)
        end)
        s.catBtns[i] = b
    end

    -- 鸟点分类的角色切换
    s.charRow = CreateFrame("Frame", nil, side)
    s.charRow:SetSize(SIDE_W, 20)
    s.charRow:SetPoint("TOPLEFT", 0, Y.charRow)
    local prev = CreateFrame("Button", nil, s.charRow, "UIPanelButtonTemplate")
    prev:SetSize(22, 18); prev:SetPoint("LEFT"); prev:SetText("<")
    local nextB = CreateFrame("Button", nil, s.charRow, "UIPanelButtonTemplate")
    nextB:SetSize(22, 18); nextB:SetPoint("RIGHT"); nextB:SetText(">")
    s.charText = s.charRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    s.charText:SetPoint("CENTER")
    local function Cycle(dir)
        local keys = {}
        for k in pairs(NS.db.chars) do keys[#keys + 1] = k end
        table.sort(keys)
        if #keys == 0 then return end
        local cur = NS.db.settings.viewChar or select(2, NS.Taxi.Char())
        local idx = 1
        for i, k in ipairs(keys) do if k == cur then idx = i end end
        NS.db.settings.viewChar = keys[(idx - 1 + dir) % #keys + 1]
        RefreshResults()
        RefreshMap(false)
    end
    prev:SetScript("OnClick", function() Cycle(-1) end)
    nextB:SetScript("OnClick", function() Cycle(1) end)
    s.charRow:Hide()

    -- 结果列表
    s.resRows, s.resOffset = {}, 0
    for i = 1, RESULT_ROWS do
        local row = CreateFrame("Button", nil, side)
        row:SetSize(SIDE_W, ROW_H - 1)
        row:SetPoint("TOPLEFT", 0, Y.results - (i - 1) * ROW_H)
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.05 or 0.02)
        row.sel = row:CreateTexture(nil, "BORDER")
        row.sel:SetAllPoints()
        row.sel:SetColorTexture(0.2, 0.5, 0.8, 0.35)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", 4, 0)
        OneLine(row.name, 150)
        row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.sub:SetPoint("RIGHT", -4, 0)
        OneLine(row.sub, SIDE_W - 162)
        row.sub:SetJustifyH("RIGHT")
        row:SetScript("OnClick", function(self) if self.it then NS.SetGoal(self.it.node) end end)
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", function(_, delta)
            s.resOffset = math.max(0, s.resOffset - delta)
            RefreshResults()
        end)
        s.resRows[i] = row
    end
    s.resMore = side:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    s.resMore:SetPoint("TOPRIGHT", 0, Y.resMore)

    -- 目的地
    local sep = side:CreateTexture(nil, "ARTWORK")
    sep:SetPoint("TOPLEFT", 0, Y.sep)
    sep:SetSize(SIDE_W, 1)
    sep:SetColorTexture(0.4, 0.6, 0.8, 0.5)
    s.goalName = side:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    s.goalName:SetPoint("TOPLEFT", 0, Y.goalName)
    OneLine(s.goalName, SIDE_W)
    s.goalInfo = side:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    s.goalInfo:SetPoint("TOPLEFT", 0, Y.goalInfo)
    s.goalInfo:SetWidth(SIDE_W)
    s.goalInfo:SetHeight(46)
    s.goalInfo:SetJustifyH("LEFT")
    s.goalInfo:SetJustifyV("TOP")
    if s.goalInfo.SetMaxLines then s.goalInfo:SetMaxLines(3) end

    s.modeBtns = {}
    for i, mode in ipairs({ "easy", "fast" }) do
        local b = CreateFrame("Button", nil, side, "UIPanelButtonTemplate")
        b:SetSize(SIDE_W / 2 - 2, 22)
        b:SetPoint("TOPLEFT", (i - 1) * (SIDE_W / 2 + 2), Y.modes)
        b.mode = mode
        b:SetScript("OnClick", function()
            win.mode = mode
            NS.db.settings.mode = mode
            RefreshRoute()
            RefreshMap(false)
        end)
        s.modeBtns[i] = b
    end
    s.summary = side:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    s.summary:SetPoint("TOPLEFT", 0, Y.summary)
    OneLine(s.summary, SIDE_W - 90)
    s.stepMore = side:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    s.stepMore:SetPoint("TOPRIGHT", 0, Y.summary)

    -- 步骤：每步固定两行
    s.stepRows, s.stepOffset = {}, 0
    for i = 1, STEP_ROWS do
        local row = CreateFrame("Frame", nil, side)
        row:SetSize(SIDE_W, STEP_H - 2)
        row:SetPoint("TOPLEFT", 0, Y.steps - (i - 1) * STEP_H)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(24, 24)
        row.icon:SetPoint("LEFT", 3, 0)
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("TOPLEFT", 32, -3)
        OneLine(row.text, SIDE_W - 36)
        row.time = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.time:SetPoint("BOTTOMLEFT", 32, 3)
        OneLine(row.time, SIDE_W - 36)
        row:EnableMouse(true)
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", function(_, delta)
            s.stepOffset = math.max(0, s.stepOffset - delta)
            RefreshSteps()
        end)
        row:SetScript("OnEnter", function(self)
            if not self.st then return end
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:AddLine(self.st.text, 1, 1, 1, true)
            GameTooltip:AddLine(StepTime(self.st), 1, 0.82, 0)
            if self.st.note then GameTooltip:AddLine(self.st.note, 1, 0.8, 0.2, true) end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        s.stepRows[i] = row
    end

    -- 底部（从底边往上排，不和上面重叠）：第一行按钮，第二行开关
    s.favBtn = CreateFrame("Button", nil, side, "UIPanelButtonTemplate")
    s.favBtn:SetSize(84, 24)
    s.favBtn:SetPoint("BOTTOMLEFT", 0, 6)
    s.favBtn:SetText("收藏这里")
    s.favBtn:SetScript("OnClick", function()
        local name = s.search:GetText()
        local key = NS.AddFavorite(name ~= "" and name or nil)
        if key then
            s.search:SetText("")
            win.cat = "fav"
            RefreshResults()
            RefreshMap(false)
        end
    end)
    s.favBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("收藏当前位置")
        GameTooltip:AddLine("先在搜索框输入名字再点，可以给收藏起名；收藏列表里右键可删除。", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    s.favBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    s.startBtn = CreateFrame("Button", nil, side, "UIPanelButtonTemplate")
    s.startBtn:SetSize(100, 24)
    s.startBtn:SetPoint("BOTTOMRIGHT", 0, 6)
    s.startBtn:SetScript("OnClick", function()
        if win.goal then
            NS.StartNav(win.goal, win.mode)
            if NS.nav then win.res = NS.nav.both end
            RefreshRoute()
            RefreshMap(false)
        end
    end)
    s.stopBtn = CreateFrame("Button", nil, side, "UIPanelButtonTemplate")
    s.stopBtn:SetSize(64, 24)
    s.stopBtn:SetPoint("RIGHT", s.startBtn, "LEFT", -4, 0)
    s.stopBtn:SetText("停止")
    s.stopBtn:SetScript("OnClick", function() NS.StopNav() end)

    local function BottomCheck(text, key, x, onClick)
        local cb = CreateFrame("CheckButton", nil, side, "UICheckButtonTemplate")
        cb:SetSize(22, 22)
        cb:SetPoint("BOTTOMLEFT", x, 34)
        local fs = side:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", cb, "RIGHT", 0, 1)
        fs:SetText(text)
        cb:SetChecked(NS.db.settings[key])
        cb:SetScript("OnClick", function(self)
            NS.db.settings[key] = self:GetChecked() and true or false
            if onClick then onClick() end
        end)
        return cb
    end
    BottomCheck("鸟点", "useFlights", 0, Replan)
    BottomCheck("炉石", "useHearth", 72, Replan)
    BottomCheck("箭头", "arrow", 144, function() NS.UpdateWaypoint() end)
    BottomCheck("偏航重算", "autoReroute", 216)
end

function NS.CreateWindow()
    win = CreateFrame("Frame", "ForeverNavFrame", UIParent, "BasicFrameTemplateWithInset")
    win:SetSize(W, H)
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
        NS.db.settings.winPos = { p, rp, x, y }
    end)
    local pos = NS.db.settings.winPos
    if pos then win:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else win:SetPoint("CENTER", 0, 20) end
    -- 窗口大小：用户设置过就用设置；否则按屏幕自动缩小到能完整放下
    local scale = NS.db.settings.winScale
    if not scale then
        local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
        scale = math.min(1, (sw - 40) / W, (sh - 80) / H)
    end
    win:SetScale(scale)
    win:Hide()
    win.mode = NS.db.settings.mode
    win.cat = "all"
    win.filters = {}
    tinsert(UISpecialFrames, "ForeverNavFrame")

    local title = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", 0, -5)
    title:SetText("咕咕导航")

    -- 地图
    local border = CreateFrame("Frame", nil, win, "BackdropTemplate")
    border:SetPoint("TOPLEFT", 12, -30)
    border:SetSize(MAP_W + 4, MAP_H + 4)
    if border.SetBackdrop then
        border:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10 })
        border:SetBackdropBorderColor(0.4, 0.6, 0.8, 0.9)
    end
    win.map = MV.Create(border, MAP_W, MAP_H)
    win.map:SetPoint("TOPLEFT", 2, -2)
    win.map.onPick = function(node) NS.SetGoal(node, true) end
    win.map.onRightClick = function(c, x, y)
        local node = NS.SetCustomGoal(c, x, y)
        if node then NS.SetGoal(node, true) end
    end

    -- 地图上的按钮
    local function MapBtn(text, x, w, fn)
        local b = CreateFrame("Button", nil, win.map.overlay, "UIPanelButtonTemplate")
        b:SetSize(w, 20)
        b:SetPoint("TOPLEFT", x, -6)
        b:SetText(text)
        b:SetScript("OnClick", fn)
        return b
    end
    win.contBtns = {
        MapBtn("卡利姆多", 6, 76, function() MV.SetContinent(win.map, "KAL") end),
        MapBtn("东部王国", 86, 76, function() MV.SetContinent(win.map, "EK") end),
    }
    MapBtn("定位我", 166, 60, function() if not MV.CenterOnPlayer(win.map) then NS.Print("拿不到你的位置。") end end)
    MapBtn("看全程", 230, 60, function() RefreshMap(true) end)
    MapBtn("+", MAP_W - 52, 22, function() win.map.zoom = math.min(5, win.map.zoom * 1.4); MV.Render(win.map) end)
    MapBtn("-", MAP_W - 28, 22, function() win.map.zoom = math.max(1, win.map.zoom / 1.4); MV.Render(win.map) end)

    -- 图例
    local legend = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    legend:SetPoint("BOTTOMLEFT", 14, 12)
    local C = MV.COLORS
    legend:SetText(Hex(C.land) .. "━ 跑路|r  " .. Hex(C.fly) .. "━ 坐鸟|r  " .. Hex(C.boat) .. "━ 坐船|r  "
        .. Hex(C.zeppelin) .. "━ 飞艇|r  " .. Hex(C.tram) .. "━ 地铁|r  " .. Hex(C.hearth) .. "━ 炉石|r   "
        .. "|A:Dungeon:14:14|a副本  |A:Raid:14:14|a团本  |cff4dff66■|r鸟点  "
        .. "|cff999999滚轮缩放 · 拖动平移 · 点图标导航 · 右键任意位置导航|r")

    -- 侧边栏
    win.side = CreateFrame("Frame", nil, win)
    win.side:SetPoint("TOPLEFT", MAP_W + 24, -30)
    win.side:SetSize(SIDE_W, H - 40)
    BuildSide(win.side)

    win:SetScript("OnShow", function()
        UpdateStatus()
        RefreshResults()
        RefreshRoute()
        if not win.shownOnce then
            win.shownOnce = true
            local p = NS.Geo.PlayerPos()
            MV.SetContinent(win.map, p and p.c or "EK")
            if p then MV.CenterOnPlayer(win.map) end
        end
        RefreshMap(false)
    end)
end

function NS.ToggleWindow(show)
    if not win then NS.CreateWindow() end
    if show == nil then show = not win:IsShown() end
    if show then win:Show() else win:Hide() end
end

-- ---------------------------------------------------------------- 顶部导航条（像车载导航）
local function UpdateHUD()
    local info = NS.NavInfo()
    if not info then if hud then hud:Hide() end return end
    if not hud then
        hud = CreateFrame("Button", "ForeverNavTracker", UIParent, "BackdropTemplate")
        hud:SetSize(380, 60)
        hud:SetClampedToScreen(true)
        hud:SetMovable(true)
        hud:EnableMouse(true)
        hud:RegisterForDrag("LeftButton")
        hud:SetScript("OnDragStart", hud.StartMoving)
        hud:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local p, _, rp, x, y = self:GetPoint()
            NS.db.settings.trackerPos = { p, rp, x, y }
        end)
        hud:SetScript("OnClick", function() NS.ToggleWindow(true); if NS.nav then NS.SetGoal(NS.nav.goal) end end)
        if hud.SetBackdrop then
            hud:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
            hud:SetBackdropColor(0.02, 0.05, 0.08, 0.88)
            hud:SetBackdropBorderColor(0.4, 0.85, 1, 1)
        end
        local pos = NS.db.settings.trackerPos
        if pos then hud:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else hud:SetPoint("TOP", 0, -160) end
        hud.arrow = hud:CreateTexture(nil, "ARTWORK")
        hud.arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
        hud.arrow:SetSize(40, 40)
        hud.arrow:SetPoint("LEFT", 6, 0)
        hud.icon = hud:CreateTexture(nil, "ARTWORK")
        hud.icon:SetSize(34, 34)
        hud.icon:SetPoint("LEFT", 9, 0)
        hud.dist = hud:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        hud.dist:SetPoint("TOPLEFT", 54, -7)
        hud.eta = hud:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hud.eta:SetPoint("TOPRIGHT", -10, -9)
        hud.step = hud:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        hud.step:SetPoint("TOPLEFT", 54, -27)
        hud.step:SetWidth(316)
        hud.step:SetJustifyH("LEFT")
        hud.bar = hud:CreateTexture(nil, "ARTWORK")
        hud.bar:SetHeight(3)
        hud.bar:SetPoint("BOTTOMLEFT", 4, 4)
        hud.bar:SetColorTexture(0.3, 0.85, 1, 0.9)
    end
    local nav, st = NS.nav, info.step
    -- 有方向时显示箭头，否则显示这一步的图标
    if info.angle then
        hud.arrow:SetRotation(info.angle)
        hud.arrow:Show()
        hud.icon:Hide()
    else
        hud.arrow:Hide()
        hud.icon:SetTexture(StepIcon(st))
        hud.icon:Show()
    end
    local head
    if st.kind == "ride" then head = "等" .. (st.routeType == "boat" and "船" or "飞艇")
    elseif st.kind == "fly" then head = "坐鸟"
    elseif st.kind == "hearth" then head = "用炉石"
    else head = info.dist and ("前方 " .. Yards(info.dist)) or "前往" end
    hud.dist:SetText(head)
    hud.eta:SetText(string.format("→ %s  全程还剩%s", nav.name, G.Fmt(info.eta)))
    hud.step:SetText(st.text .. (st.note and ("\n|cffffcc33" .. st.note .. "|r") or ""))
    hud:SetHeight(st.note and 74 or 60)
    hud.bar:SetWidth(math.max(1, 372 * (nav.step - 1) / math.max(1, #nav.plan.steps)))
    hud:Show()
end

NS.OnNavChanged = function()
    UpdateHUD()
    if win and win:IsShown() then RefreshRoute(); RefreshMap(false) end
end
NS.OnNavTick = function()
    UpdateHUD()
    if win and win:IsShown() then UpdateStatus() end
end
NS.OnLocationChanged = UpdateStatus
NS.OnTaxiChanged = function()
    if not win then return end
    if win.goal then win.res, win.err = NS.PlanBoth(win.goal) end
    if win:IsShown() then RefreshResults(); RefreshRoute(); RefreshMap(false); UpdateStatus() end
end

-- 收藏右键删除
local function HookFavDelete()
    for _, row in ipairs(win.side.resRows) do
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local old = row:GetScript("OnClick")
        row:SetScript("OnClick", function(self, button)
            if button == "RightButton" and self.it and self.it.kind == "fav" then
                NS.db.favs[self.it.node:sub(3)] = nil
                NS.Print("已删除收藏：" .. self.it.name)
                RefreshResults()
                RefreshMap(false)
                return
            end
            old(self, button)
        end)
    end
end
local origCreate = NS.CreateWindow
NS.CreateWindow = function() origCreate(); HookFavDelete() end

-- ---------------------------------------------------------------- 世界地图按钮
local mapBtn
local function EnsureMapButton()
    if mapBtn or not WorldMapFrame then return end
    mapBtn = CreateFrame("Button", "ForeverNavMapButton", WorldMapFrame, "UIPanelButtonTemplate")
    mapBtn:SetSize(110, 22)
    local anchor = WorldMapFrame.ScrollContainer or WorldMapFrame
    mapBtn:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -8, -8)
    mapBtn:SetFrameStrata("HIGH")
    mapBtn:SetText("导航到这里")
    mapBtn:SetScript("OnClick", function()
        local id = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
        local info = id and C_Map.GetMapInfo(id)
        local key = info and NS.zoneByName[info.name]
        if key then NS.SetGoal("Z:" .. key) else NS.Print("这张地图不在导航数据里，请切换到具体的地区地图。") end
    end)
end

-- ---------------------------------------------------------------- 命令
SLASH_FOREVERNAV1 = "/dh"
SLASH_FOREVERNAV2 = "/forevernav"
SlashCmdList.FOREVERNAV = function(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "" then return NS.ToggleWindow() end
    if msg == "stop" or msg == "停止" then return NS.StopNav() end
    local scale = msg:match("^scale%s+([%d%.]+)$") or msg:match("^缩放%s+([%d%.]+)$")
    if scale then
        local v = math.max(0.6, math.min(1.4, tonumber(scale)))
        NS.db.settings.winScale = v
        if win then win:SetScale(v) end
        return NS.Print("窗口缩放设为 " .. v)
    end
    if msg:match("^收藏") or msg:match("^fav") then
        local name = msg:gsub("^收藏%s*", ""):gsub("^fav%s*", "")
        NS.AddFavorite(name)
        return
    end
    if msg == "help" or msg == "帮助" then
        NS.Print("用法：")
        print("  /dh　　　　　　 打开/关闭导航窗口")
        print("  /dh 死亡矿井　　直接导航（副本、团本、地区、码头都行，支持简称：死矿、黑龙、BRD）")
        print("  /dh 收藏 名字　 收藏当前位置")
        print("  /dh stop　　　　停止导航")
        print("  /dh scale 0.9　 调整窗口大小（0.6~1.4）")
        return
    end
    local list = NS.Search(msg)
    if #list == 0 then return NS.Print("找不到“" .. msg .. "”，试试副本名、地区名或城镇名") end
    NS.SetGoal(list[1].node)
    NS.StartNav(list[1].node, NS.db.settings.mode)
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    EnsureMapButton()
    if WorldMapFrame and WorldMapFrame.HookScript then WorldMapFrame:HookScript("OnShow", EnsureMapButton) end
    NS.Print("已加载。|cffffff00/dh|r 打开导航，|cffffff00/dh 死矿|r 直接导航到副本。")
end)
