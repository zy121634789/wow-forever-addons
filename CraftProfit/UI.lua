-- 界面：利润面板、拍卖行按钮、鼠标提示、斜杠命令
local _, CP = ...

local ROWS, ROW_H = 16, 22
local COL = { name = 140, cost = 72, sale = 72, profit = 72, sold = 46, daily = 76 }
local ROW_W = COL.name + COL.cost + COL.sale + COL.profit + COL.sold + COL.daily + 22
local SRC_LABEL = { ah = "拍卖", vendor = "商人", craft = "自制" }

local panel

-- ---------------------------------------------------------------- 工具
local function ItemLink(itemID)
    local _, link = (C_Item and C_Item.GetItemInfo or GetItemInfo)(itemID)
    return link
end

local function InsertLink(link)
    if not link then return end
    if ChatFrameUtil and ChatFrameUtil.InsertLink then
        ChatFrameUtil.InsertLink(link)
    elseif ChatEdit_InsertLink then
        ChatEdit_InsertLink(link)
    end
end

local function ProfitColor(v)
    if not v then return "|cff808080" end
    return v >= 0 and "|cff40ff40" or "|cffff5050"
end

-- 当前面板要显示哪个专业
local function ProfList()
    local list = {}
    for id, p in pairs(CP.CharDB().profs) do list[#list + 1] = { id = id, name = p.name } end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

local function CurrentProf()
    local profs = CP.CharDB().profs
    if panel.userProf and profs[panel.userProf] then return panel.userProf end
    if CP.currentProf and profs[CP.currentProf] then return CP.currentProf end
    local list = ProfList()
    return list[1] and list[1].id
end

-- ---------------------------------------------------------------- 行提示
local function ShowRowTooltip(row)
    local e = row.eval
    if not e then return end
    local r = CP.db.recipes[e.recipeID]
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(r.name, 1, 0.82, 0)
    if e.qty ~= 1 then GameTooltip:AddLine(string.format("每次产出 %s 个", e.qty % 1 == 0 and e.qty or string.format("%.1f", e.qty)), 0.8, 0.8, 0.8) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("材料：", 0.6, 0.8, 1)
    for _, p in ipairs(e.parts) do
        local left = CP.ItemName(p.id) .. " ×" .. p.n
        local right
        if p.unit then
            local src = SRC_LABEL[p.src] or ""
            if p.src == "craft" and p.via and CP.db.recipes[p.via] then src = "自制" end
            right = CP.Money(p.unit * p.n) .. " |cff999999(" .. src .. ")|r"
        else
            right = "|cffff8040无价格|r"
        end
        GameTooltip:AddDoubleLine("  " .. left, right, 1, 1, 1, 1, 1, 1)
    end
    GameTooltip:AddDoubleLine("总成本", CP.Money(e.cost) .. (#e.missing > 0 and " |cffff8040+?|r" or ""), 1, 1, 1, 1, 1, 1)
    GameTooltip:AddLine(" ")
    if e.out then
        local p = CP.db.prices[e.out]
        if p then
            GameTooltip:AddDoubleLine("拍卖市场价（单个）", CP.Money(p.m), 0.8, 0.8, 0.8, 1, 1, 1)
            if p.n and p.n < p.m then GameTooltip:AddDoubleLine("最低一口价", CP.Money(p.n), 0.8, 0.8, 0.8, 1, 1, 1) end
            GameTooltip:AddDoubleLine("在售数量 / 数据时间", (p.q or "?") .. " / " .. CP.Age(p.t), 0.8, 0.8, 0.8, 0.7, 0.7, 0.7)
        else
            GameTooltip:AddLine("拍卖行没有这个成品的价格", 1, 0.5, 0.25)
        end
        if e.sale then
            local how = e.saleSrc == "vendor" and "卖商人" or string.format("拍卖到手（扣 %d%% 手续费）", math.floor(CP.db.settings.cut * 100 + 0.5))
            GameTooltip:AddDoubleLine(how, CP.Money(e.sale), 0.8, 0.8, 0.8, 1, 1, 1)
        end
    else
        GameTooltip:AddLine("这个配方不产出物品（如附魔），只计算成本", 0.7, 0.7, 0.7, true)
    end
    if e.profit then
        GameTooltip:AddDoubleLine("每次制作利润", ProfitColor(e.profit) .. CP.Money(e.profit) .. "|r", 1, 1, 1)
        if e.margin then
            GameTooltip:AddDoubleLine("利润率", ProfitColor(e.profit) .. string.format("%.0f%%", e.margin * 100) .. "|r", 1, 1, 1)
        end
    elseif #e.missing > 0 then
        GameTooltip:AddLine("有材料缺价格：去拍卖行全扫描，或到商人处打开一次商店", 1, 0.5, 0.25, true)
    end
    -- 销量
    if e.out then
        GameTooltip:AddLine(" ")
        local perDay, hours, n = CP.Sales.Rate(e.out)
        if perDay then
            GameTooltip:AddDoubleLine("估计日销（全服）", CP.Sales.Label(perDay) .. " 个/天", 0.6, 0.8, 1, 1, 1, 1)
            local p = CP.db.prices[e.out]
            if p and p.q and perDay >= 0.5 then
                GameTooltip:AddDoubleLine("卖完现有在售约需", string.format("%.1f 天", p.q / perDay), 0.8, 0.8, 0.8, 1, 1, 1)
            end
            if e.daily then
                GameTooltip:AddDoubleLine("日赚潜力（利润×日销）", ProfitColor(e.daily) .. CP.Money(e.daily) .. "|r", 0.8, 0.8, 0.8, 1, 1, 1)
            end
            GameTooltip:AddLine(string.format("基于 %d 次扫描对比，共 %.1f 小时", n, hours), 0.6, 0.6, 0.6)
            if hours < 6 then GameTooltip:AddLine("观察时间还短，数字仅供参考", 1, 0.6, 0.3) end
        else
            GameTooltip:AddLine("还没有销量数据：隔 15 分钟～12 小时再全扫描一次", 0.7, 0.7, 0.7, true)
        end
    end
    if e.out then GameTooltip:AddLine("|cff999999Shift+点击：把成品链接发到聊天框|r") end
    GameTooltip:Show()
end

-- ---------------------------------------------------------------- 面板
local function SortList(list, key)
    local function nilLast(a, b, desc)
        if a == nil and b == nil then return nil end
        if a == nil then return false end
        if b == nil then return true end
        if a == b then return nil end
        if desc then return a > b end
        return a < b
    end
    table.sort(list, function(x, y)
        local res
        if key == "name" then
            res = nilLast(x.name, y.name)
        elseif key == "cost" then
            res = nilLast(x.cost, y.cost)
        elseif key == "sale" then
            res = nilLast(x.sale, y.sale, true)
        elseif key == "sold" then
            res = nilLast(x.perDay, y.perDay, true)
        elseif key == "daily" then
            res = nilLast(x.daily, y.daily, true)
        else
            res = nilLast(x.profit, y.profit, true)
        end
        if res == nil then return (x.name or "") < (y.name or "") end
        return res
    end)
end

local function Update()
    if not panel or not panel:IsShown() then return end
    local prof = CurrentProf()
    panel.prof = prof
    local profs = CP.CharDB().profs
    local s = CP.db.settings

    panel.profText:SetText(prof and profs[prof].name or "（先打开一次专业技能窗口）")
    panel.status:SetText(string.format("上次全扫描：%s　手续费：%d%%　有价物品：%d",
        CP.Age(CP.db.lastScan), math.floor(s.cut * 100 + 0.5), (function()
            local n = 0; for _ in pairs(CP.db.prices) do n = n + 1 end; return n end)()))

    local list = {}
    if prof then
        for _, rid in ipairs(profs[prof].ids) do
            local e = CP.Evaluate(rid)
            if e and not (s.hideUnknown and not e.profit) then
                e.name = CP.db.recipes[rid].name
                list[#list + 1] = e
            end
        end
    end
    SortList(list, s.sort)
    panel.list = list

    local maxOffset = math.max(0, #list - ROWS)
    if panel.offset > maxOffset then panel.offset = maxOffset end
    for i = 1, ROWS do
        local row, e = panel.rows[i], list[panel.offset + i]
        row.eval = e
        if e then
            local r = CP.db.recipes[e.recipeID]
            row.icon:SetTexture((e.out and CP.ItemIcon(e.out)) or r.icon or 134400)
            row.name:SetText(e.name)
            row.cost:SetText(CP.Money(e.cost, true) .. (#e.missing > 0 and "|cffff8040?|r" or ""))
            row.sale:SetText(CP.Money(e.sale, true))
            row.profit:SetText(e.profit and (ProfitColor(e.profit) .. CP.Money(e.profit, true) .. "|r") or "|cff808080--|r")
            row.sold:SetText(e.out and CP.Sales.Label(e.perDay) or "")
            row.daily:SetText(e.daily and (ProfitColor(e.daily) .. CP.Money(e.daily, true) .. "|r") or "|cff808080--|r")
            row:Show()
        else
            row:Hide()
        end
    end
    panel.pageText:SetText(#list == 0 and "没有配方" or string.format("%d-%d / 共 %d",
        panel.offset + 1, math.min(#list, panel.offset + ROWS), #list))
    for key, btn in pairs(panel.headers) do
        btn.text:SetTextColor(key == s.sort and 1 or 0.8, key == s.sort and 0.82 or 0.8, key == s.sort and 0 or 0.8)
    end
    panel.hideBox:SetChecked(s.hideUnknown)
    panel.scanBtn:SetEnabled(CP.auctionOpen)
end
table.insert(CP.refreshers, Update)

local function Place()
    panel:ClearAllPoints()
    local pos = CP.db.settings.panelPos
    if pos then
        panel:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    elseif ProfessionsFrame then
        panel:SetPoint("TOPLEFT", ProfessionsFrame, "TOPRIGHT", 50, 0)
    else
        panel:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
    end
end

local function CreatePanel()
    panel = CreateFrame("Frame", "CraftProfitPanel", UIParent, "BasicFrameTemplateWithInset")
    panel:SetSize(ROW_W + 26, 118 + ROWS * ROW_H)
    panel:SetFrameStrata("HIGH")
    panel:SetToplevel(true)
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        CP.db.settings.panelPos = { p, rp, x, y }
    end)
    panel:Hide()
    panel.offset = 0
    tinsert(UISpecialFrames, "CraftProfitPanel") -- 按 Esc 关闭

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", 0, -5)
    title:SetText("制造利润")

    -- 专业切换
    local prev = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    prev:SetSize(24, 20); prev:SetPoint("TOPLEFT", 12, -30); prev:SetText("<")
    local nextB = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    nextB:SetSize(24, 20); nextB:SetPoint("TOPRIGHT", -12, -30); nextB:SetText(">")
    panel.profText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    panel.profText:SetPoint("TOP", 0, -32)
    local function Cycle(dir)
        local list = ProfList()
        if #list == 0 then return end
        local idx = 1
        for i, p in ipairs(list) do if p.id == panel.prof then idx = i end end
        idx = (idx - 1 + dir) % #list + 1
        panel.userProf, panel.offset = list[idx].id, 0
        Update()
    end
    prev:SetScript("OnClick", function() Cycle(-1) end)
    nextB:SetScript("OnClick", function() Cycle(1) end)

    panel.status = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.status:SetPoint("TOPLEFT", 14, -56)

    -- 列标题（点击排序）
    panel.headers = {}
    local x = 14
    for _, col in ipairs({ { "name", "配方", COL.name + 22, "LEFT" }, { "cost", "成本", COL.cost, "RIGHT" },
        { "sale", "售价", COL.sale, "RIGHT" }, { "profit", "利润", COL.profit, "RIGHT" },
        { "sold", "日销", COL.sold, "RIGHT" }, { "daily", "日赚", COL.daily, "RIGHT" } }) do
        local key, label, width, justify = col[1], col[2], col[3], col[4]
        local b = CreateFrame("Button", nil, panel)
        b:SetSize(width, 18)
        b:SetPoint("TOPLEFT", x, -72)
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        b.text:SetAllPoints(); b.text:SetJustifyH(justify); b.text:SetText(label)
        b:SetScript("OnClick", function() CP.db.settings.sort = key; panel.offset = 0; Update() end)
        panel.headers[key] = b
        x = x + width
    end

    -- 行
    panel.rows = {}
    for i = 1, ROWS do
        local row = CreateFrame("Button", nil, panel)
        row:SetSize(ROW_W, ROW_H)
        row:SetPoint("TOPLEFT", 14, -92 - (i - 1) * ROW_H)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(18, 18); row.icon:SetPoint("LEFT")
        local function Cell(width, justify, anchor)
            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetSize(width, ROW_H); fs:SetJustifyH(justify); fs:SetWordWrap(false)
            fs:SetPoint("LEFT", anchor, "RIGHT", 4, 0)
            return fs
        end
        row.name = Cell(COL.name - 4, "LEFT", row.icon)
        row.cost = Cell(COL.cost - 4, "RIGHT", row.name)
        row.sale = Cell(COL.sale - 4, "RIGHT", row.cost)
        row.profit = Cell(COL.profit - 4, "RIGHT", row.sale)
        row.sold = Cell(COL.sold - 4, "RIGHT", row.profit)
        row.daily = Cell(COL.daily - 4, "RIGHT", row.sold)
        row:SetScript("OnEnter", ShowRowTooltip)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:SetScript("OnClick", function(self)
            if IsShiftKeyDown() and self.eval and self.eval.out then InsertLink(ItemLink(self.eval.out)) end
        end)
        panel.rows[i] = row
    end
    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", function(_, delta)
        local maxOffset = math.max(0, #(panel.list or {}) - ROWS)
        panel.offset = math.min(maxOffset, math.max(0, panel.offset - delta * 3))
        Update()
    end)

    -- 底部
    panel.hideBox = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    panel.hideBox:SetSize(22, 22)
    panel.hideBox:SetPoint("BOTTOMLEFT", 10, 8)
    local hideLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hideLabel:SetPoint("LEFT", panel.hideBox, "RIGHT", 2, 0)
    hideLabel:SetText("隐藏算不出利润的")
    panel.hideBox:SetScript("OnClick", function(self)
        CP.db.settings.hideUnknown = self:GetChecked() and true or false
        panel.offset = 0
        Update()
    end)

    panel.pageText = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.pageText:SetPoint("BOTTOMLEFT", 160, 14)

    panel.scanBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.scanBtn:SetSize(96, 22)
    panel.scanBtn:SetPoint("BOTTOMRIGHT", -10, 8)
    panel.scanBtn:SetText("扫描拍卖行")
    panel.scanBtn:SetScript("OnClick", function() CP.Scan.Start() end)
    panel.scanBtn:SetMotionScriptsWhileDisabled(true)
    panel.scanBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("全量扫描拍卖行")
        GameTooltip:AddLine(CP.auctionOpen and "一次读取所有拍卖，服务器限制每 15 分钟一次。" or "需要先打开拍卖行。", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    panel.scanBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local ledgerBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    ledgerBtn:SetSize(56, 22)
    ledgerBtn:SetPoint("RIGHT", panel.scanBtn, "LEFT", -4, 0)
    ledgerBtn:SetText("收支")
    ledgerBtn:SetScript("OnClick", function() CP.ToggleLedger() end)

    local quantBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    quantBtn:SetSize(56, 22)
    quantBtn:SetPoint("RIGHT", ledgerBtn, "LEFT", -4, 0)
    quantBtn:SetText("交易")
    quantBtn:SetScript("OnClick", function() CP.ToggleQuant() end)

    panel:SetScript("OnShow", Update)
end

function CP.TogglePanel(show)
    if not panel then CreatePanel() end
    if show == nil then show = not panel:IsShown() end
    if show then
        Place()
        panel:Show()
        Update()
    else
        panel:Hide()
    end
end

CP.OnTradeSkillShow = function()
    if not panel then CreatePanel() end
    panel.userProf, panel.offset = nil, 0 -- 跟随刚打开的专业
    if panel:IsShown() then return Update() end
    if not CP.db.settings.autoShow then return end
    panel.auto = true
    CP.TogglePanel(true)
end

CP.OnTradeSkillClose = function()
    CP.currentProf = nil
    if panel and panel.auto then
        panel.auto = nil
        panel:Hide()
    end
end

-- ---------------------------------------------------------------- 拍卖行按钮
local ahScan
local function AHButtonLabel()
    local S = CP.Scan
    if S.state ~= "idle" then return S.status or "扫描中…" end
    local left = S.Remaining()
    if left > 0 then return string.format("冷却 %d:%02d", math.floor(left / 60), left % 60) end
    return "全扫描拍卖行"
end

CP.OnScanStatus = function()
    if ahScan then ahScan:SetText(AHButtonLabel()) end
end

CP.OnAuctionShow = function()
    if panel and panel:IsShown() then Update() end
    if ahScan or not AuctionHouseFrame then return end
    ahScan = CreateFrame("Button", "CraftProfitAHScan", AuctionHouseFrame, "UIPanelButtonTemplate")
    ahScan:SetSize(130, 24)
    ahScan:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 4, -30)
    ahScan:SetScript("OnClick", function() CP.Scan.Start() end)
    local elapsed = 0
    ahScan:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed < 0.5 then return end
        elapsed = 0
        self:SetText(AHButtonLabel())
    end)
    ahScan:SetText(AHButtonLabel())

    local ahPanel = CreateFrame("Button", nil, AuctionHouseFrame, "UIPanelButtonTemplate")
    ahPanel:SetSize(130, 24)
    ahPanel:SetPoint("TOP", ahScan, "BOTTOM", 0, -4)
    ahPanel:SetText("制造利润面板")
    ahPanel:SetScript("OnClick", function() CP.TogglePanel() end)

    local ahQuant = CreateFrame("Button", nil, AuctionHouseFrame, "UIPanelButtonTemplate")
    ahQuant:SetSize(130, 24)
    ahQuant:SetPoint("TOP", ahPanel, "BOTTOM", 0, -4)
    ahQuant:SetText("交易建议")
    ahQuant:SetScript("OnClick", function() CP.ToggleQuant() end)
end

-- ---------------------------------------------------------------- 鼠标提示
local function OnTooltipItem(tooltip, data)
    if not CP.db or tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    if type(data) ~= "table" or CP.Secret(data.id) then return end
    local id = data.id
    if type(id) ~= "number" then return end
    local p, v = CP.db.prices[id], CP.db.vendor[id]
    local craft = CP.CraftCostOf(id)
    if not p and not v and not craft then return end
    if p then
        local right = CP.Money(p.m)
        if p.n and p.n < p.m then right = right .. " |cff999999(最低 " .. CP.Money(p.n) .. ")|r" end
        tooltip:AddDoubleLine("|cff33ccff拍卖价|r |cff777777" .. CP.Age(p.t) .. "|r", right, 1, 1, 1, 1, 1, 1)
    end
    if v then tooltip:AddDoubleLine("|cff33ccff商人买价|r", CP.Money(v), 1, 1, 1, 1, 1, 1) end
    local perDay = CP.Sales.Rate(id)
    if perDay then
        tooltip:AddDoubleLine("|cff33ccff估计日销|r", CP.Sales.Label(perDay) .. " 个/天"
            .. (p and p.q and ("  |cff999999在售 " .. p.q .. "|r") or ""), 1, 1, 1, 1, 1, 1)
    end
    if craft then
        local line = CP.Money(craft)
        if p and p.m then
            local net = p.m * (1 - CP.db.settings.cut)
            line = line .. " " .. ProfitColor(net - craft) .. "(利润 " .. CP.Money(net - craft) .. ")|r"
        end
        tooltip:AddDoubleLine("|cff33ccff制作成本|r", line, 1, 1, 1, 1, 1, 1)
    end
end

table.insert(CP.inits, function()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnTooltipItem)
    end
    CP.Print("已加载。输入 |cffffff00/cpf|r 打开面板，|cffffff00/cpf help|r 查看命令。")
end)

-- ---------------------------------------------------------------- 命令
local function Help()
    CP.Print("命令：")
    print("  /cpf　　　　　　打开/关闭利润面板")
    print("  /cpf scan　　　 全扫描拍卖行（需打开拍卖行，15分钟一次）")
    print("  /cpf cut 5　　　设置拍卖行手续费百分比（默认 5）")
    print("  /cpf share 20　 市场价取最便宜的百分之多少的平均（默认 20）")
    print("  /cpf auto　　　 开关：打开专业窗口时自动显示面板")
    print("  /cpf price 物品 查询一个物品的价格（可 Shift+点击物品放进来）")
    print("  /cpf clear　　　清空所有已记录的拍卖价格")
    print("  /cpf zz　　　　 打开/关闭实时收支窗口")
    print("  /cpf zz mini　　收支窗口切换迷你条/详细")
    print("  /cpf zz reset　 重新开始统计“本次”收支")
    print("  /cpf qt　　　　 打开/关闭交易建议（量化）窗口")
    print("  /cpf qt alert　 开关：扫描后在聊天框提醒交易机会")
    print("  /cpf watch 物品 关注/取消关注一个物品（Shift+点击物品放进来）")
    print("  /cpf quick　　　开关：拍卖行开着时快速扫描关注的材料")
    print("  /cpf quick 60　 设置快速扫描间隔秒数（最少 30）")
    print("  /cpf quick sound 开关快速扫描提示音")
end

SLASH_CRAFTPROFIT1 = "/cpf"
SLASH_CRAFTPROFIT2 = "/craftprofit"
SlashCmdList.CRAFTPROFIT = function(msg)
    msg = msg or ""
    local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    local s = CP.db.settings
    if cmd == "" then
        CP.TogglePanel()
    elseif cmd == "scan" then
        CP.Scan.Start()
    elseif cmd == "cut" then
        local n = tonumber(rest)
        if n and n >= 0 and n < 100 then
            s.cut = n / 100
            CP.Print("拍卖行手续费设为 " .. n .. "%")
            CP.Refresh()
        else
            CP.Print("用法：/cpf cut 5")
        end
    elseif cmd == "share" then
        local n = tonumber(rest)
        if n and n > 0 and n <= 100 then
            s.share = n / 100
            CP.Print("市场价改为取最便宜的 " .. n .. "% 的平均，下次扫描生效。")
        else
            CP.Print("用法：/cpf share 20")
        end
    elseif cmd == "auto" then
        s.autoShow = not s.autoShow
        CP.Print("打开专业窗口时自动显示面板：" .. (s.autoShow and "开" or "关"))
    elseif cmd == "price" then
        local id = tonumber(rest:match("item:(%d+)") or rest)
        if not id then return CP.Print("用法：/cpf price [物品链接]") end
        local p, v = CP.db.prices[id], CP.db.vendor[id]
        local craft = CP.CraftCostOf(id)
        CP.Print(CP.ItemName(id) .. "：拍卖 " .. (p and (CP.Money(p.m) .. "（" .. CP.Age(p.t) .. "）") or "无")
            .. "，商人 " .. (v and CP.Money(v) or "无") .. "，制作成本 " .. (craft and CP.Money(craft) or "无"))
    elseif cmd == "zz" or cmd == "ledger" then
        local sub = rest:lower()
        if sub == "mini" then
            s.ledgerMini = not s.ledgerMini
            CP.ToggleLedger(true)
        elseif sub == "reset" then
            CP.Ledger.session = { start = GetTime(), cats = {}, inc = 0, exp = 0 }
            CP.Print("“本次”收支已重新开始统计。")
            if CP.LedgerUpdate then CP.LedgerUpdate() end
        else
            CP.ToggleLedger()
        end
    elseif cmd == "qt" or cmd == "quant" then
        if rest:lower() == "alert" then
            s.quantAlert = not s.quantAlert
            CP.Print("扫描后提醒交易机会：" .. (s.quantAlert and "开" or "关"))
            if CP.QuantUpdate then CP.QuantUpdate() end
        else
            CP.ToggleQuant()
        end
    elseif cmd == "quick" then
        local sub = rest:lower()
        local n = tonumber(sub)
        if n then
            s.quickInterval = math.max(30, math.floor(n))
            CP.Print("快速扫描间隔设为 " .. s.quickInterval .. " 秒（最少 30 秒）")
        elseif sub == "sound" then
            s.quickSound = not s.quickSound
            CP.Print("快速扫描提示音：" .. (s.quickSound and "开" or "关"))
        else
            s.quickScan = not s.quickScan
            CP.Print("快速扫描关注材料：" .. (s.quickScan and ("开（每 " .. s.quickInterval .. " 秒）") or "关"))
        end
        if CP.QuantUpdate then CP.QuantUpdate() end
    elseif cmd == "watch" then
        local id = tonumber(rest:match("item:(%d+)") or rest)
        if not id then return CP.Print("用法：/cpf watch [物品链接]") end
        CP.ToggleWatch(id)
    elseif cmd == "clear" then
        CP.db.prices = {}
        CP.db.lastScan = 0
        CP.Print("已清空拍卖价格。")
        CP.Refresh()
    else
        Help()
    end
end
