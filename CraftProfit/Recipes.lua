-- 读取专业技能窗口里的配方（“无限”使用 C_TradeSkillUI，旧的 GetTradeSkillInfo 已不存在）
local _, CP = ...

local BASIC = (Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic) or 1
CP.currentProf = nil -- 当前打开的专业ID

local function OutputItem(recipeID, schematic)
    if schematic and schematic.outputItemID and schematic.outputItemID > 0 then return schematic.outputItemID end
    if C_TradeSkillUI.GetRecipeOutputItemData then
        local ok, data = pcall(C_TradeSkillUI.GetRecipeOutputItemData, recipeID)
        if ok and type(data) == "table" and data.itemID and data.itemID > 0 then return data.itemID end
    end
    return nil -- 附魔等不产出物品的配方
end

local function ReadRecipe(recipeID, info, prof)
    local ok, sch = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
    if not ok or not sch then return nil end
    local r = {
        name = info.name, icon = info.icon, prof = prof,
        out = OutputItem(recipeID, sch),
        qmin = sch.quantityMin or 1, qmax = sch.quantityMax or sch.quantityMin or 1,
        r = {},
    }
    for _, slot in ipairs(sch.reagentSlotSchematics or {}) do
        local rg = slot.reagents and slot.reagents[1]
        -- 只算必需的基础材料；可选材料不计入成本
        if (slot.reagentType == nil or slot.reagentType == BASIC) and rg and rg.itemID and (slot.quantityRequired or 0) > 0 then
            r.r[#r.r + 1] = { id = rg.itemID, n = slot.quantityRequired }
        end
    end
    return r
end

local retries = 0
function CP.ScanProfession()
    if not C_TradeSkillUI or not C_TradeSkillUI.IsTradeSkillReady or not C_TradeSkillUI.IsTradeSkillReady() then return end
    -- 查看别人分享的专业链接时不记录
    if C_TradeSkillUI.IsTradeSkillLinked and C_TradeSkillUI.IsTradeSkillLinked() then return end
    local base = C_TradeSkillUI.GetBaseProfessionInfo()
    local prof = base and base.professionID
    if not prof then return end
    CP.currentProf = prof

    local ids, changed = {}, false
    for _, id in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
        local info = C_TradeSkillUI.GetRecipeInfo(id)
        -- 刚切换专业时列表里可能还残留上一个专业的配方，过滤掉
        local pi = C_TradeSkillUI.GetProfessionInfoByRecipeID and C_TradeSkillUI.GetProfessionInfoByRecipeID(id)
        local ours = not pi or pi.professionID == prof or pi.parentProfessionID == prof
        if info and info.learned and ours then
            ids[#ids + 1] = id
            local old = CP.db.recipes[id]
            if not old or not old.r or (#old.r == 0 and not old.out) then
                local r = ReadRecipe(id, info, prof)
                if r then CP.db.recipes[id] = r; changed = true end
            end
        end
    end

    if #ids == 0 then
        -- 列表还没准备好，稍后再试
        if retries < 5 then
            retries = retries + 1
            C_Timer.After(0.5, CP.ScanProfession)
        end
        return
    end
    retries = 0
    CP.CharDB().profs[prof] = { name = base.professionName or ("专业" .. prof), ids = ids }
    if changed then CP.RecipesChanged() end
    CP.Refresh()
end

local pending = false
local function Schedule()
    if pending then return end
    pending = true
    C_Timer.After(0.3, function() pending = false; CP.ScanProfession() end)
end

table.insert(CP.inits, function()
    CP.On("TRADE_SKILL_SHOW", function()
        Schedule()
        -- 等暴雪的专业窗口先显示出来，面板才能贴在它旁边
        if CP.OnTradeSkillShow then C_Timer.After(0, CP.OnTradeSkillShow) end
    end)
    CP.On("TRADE_SKILL_LIST_UPDATE", Schedule)
    CP.On("TRADE_SKILL_CLOSE", function() if CP.OnTradeSkillClose then CP.OnTradeSkillClose() end end)
end)
