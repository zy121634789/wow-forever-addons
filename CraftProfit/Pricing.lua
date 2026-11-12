-- 价格计算（纯逻辑，不依赖界面，可在游戏外测试）
local _, CP = ...

local MAX_DEPTH = 3 -- 材料本身也能制造时，最多往下追几层

-- ---------------------------------------------------------------- 市场价
-- samples = { {unit = 单价, qty = 数量}, ... }
-- 市场价 = 按单价从低到高，取“最便宜的 share 比例数量”的加权平均。
-- 这样一两个挂错价的超低/超高单子不会把价格带偏。
function CP.Aggregate(samples, share)
    if not samples or #samples == 0 then return nil end
    share = share or 0.2
    table.sort(samples, function(a, b) return a.unit < b.unit end)
    local total = 0
    for _, s in ipairs(samples) do total = total + s.qty end
    if total <= 0 then return nil end
    local want = math.max(1, total * share)
    local got, sum = 0, 0
    for _, s in ipairs(samples) do
        local take = math.min(s.qty, want - got)
        sum = sum + take * s.unit
        got = got + take
        if got >= want then break end
    end
    return math.floor(sum / got + 0.5), samples[1].unit, total
end

-- ---------------------------------------------------------------- 缓存
local costCache, producers = {}, nil

function CP.ClearCostCache()
    costCache = {}
end

function CP.RecipesChanged()
    producers = nil
    CP.ClearCostCache()
end

-- 成品物品ID → 能做出它的配方列表
local function Producers()
    if producers then return producers end
    producers = {}
    for rid, r in pairs(CP.db.recipes) do
        if r.out then
            producers[r.out] = producers[r.out] or {}
            table.insert(producers[r.out], rid)
        end
    end
    return producers
end

local function AvgQty(r)
    local lo, hi = r.qmin or 1, r.qmax or r.qmin or 1
    if lo < 1 then lo = 1 end
    if hi < lo then hi = lo end
    return (lo + hi) / 2
end
CP.AvgQty = AvgQty

-- ---------------------------------------------------------------- 材料成本
-- 返回：单价, 来源("ah"/"vendor"/"craft"), 若来源是 craft 则附带配方ID
local RecipeCostInner

local function ItemCostInner(itemID, depth, visiting)
    local best, src, via
    local v = CP.db.vendor[itemID]
    if v and v > 0 then best, src = v, "vendor" end
    local p = CP.db.prices[itemID]
    if p and p.m and (not best or p.m < best) then best, src = p.m, "ah" end

    if depth < MAX_DEPTH and not visiting[itemID] then
        local list = Producers()[itemID]
        if list then
            visiting[itemID] = true
            for _, rid in ipairs(list) do
                local total, missing = RecipeCostInner(rid, depth + 1, visiting)
                if total and #missing == 0 then
                    local unit = total / AvgQty(CP.db.recipes[rid])
                    if not best or unit < best then best, src, via = unit, "craft", rid end
                end
            end
            visiting[itemID] = nil
        end
    end
    return best, src, via
end

function CP.ItemCost(itemID)
    local c = costCache[itemID]
    if c == nil then
        local cost, src, via = ItemCostInner(itemID, 0, {})
        c = { cost = cost, src = src, via = via }
        costCache[itemID] = c
    end
    return c.cost, c.src, c.via
end

-- 返回：总成本(已知部分), 缺价材料列表, 明细
RecipeCostInner = function(recipeID, depth, visiting)
    local r = CP.db.recipes[recipeID]
    if not r or not r.r then return nil, {}, {} end
    local total, missing, parts = 0, {}, {}
    for _, rg in ipairs(r.r) do
        local unit, src, via
        if depth == 0 then
            unit, src, via = CP.ItemCost(rg.id)
        else
            unit, src, via = ItemCostInner(rg.id, depth, visiting)
        end
        parts[#parts + 1] = { id = rg.id, n = rg.n, unit = unit, src = src, via = via }
        if unit then
            total = total + unit * rg.n
        else
            missing[#missing + 1] = rg.id
        end
    end
    return total, missing, parts
end

function CP.RecipeCost(recipeID)
    return RecipeCostInner(recipeID, 0, {})
end

-- ---------------------------------------------------------------- 售价与利润
-- 单个成品能卖多少（铜）：拍卖行扣手续费后 vs 卖商人，取高的
function CP.UnitSale(itemID)
    local cut = CP.db.settings.cut or 0.05
    local p = CP.db.prices[itemID]
    local ah = p and p.m and p.m * (1 - cut)
    local vendor = CP.VendorSell and CP.VendorSell(itemID)
    if ah and (not vendor or ah >= vendor) then return ah, "ah" end
    if vendor then return vendor, "vendor" end
    return nil
end

-- 评估一个配方：成本、售价、利润
function CP.Evaluate(recipeID)
    local r = CP.db.recipes[recipeID]
    if not r then return nil end
    local cost, missing, parts = CP.RecipeCost(recipeID)
    local qty = AvgQty(r)
    local res = { recipeID = recipeID, cost = cost, missing = missing, parts = parts, qty = qty, out = r.out }
    if r.out then
        local unit, src = CP.UnitSale(r.out)
        if unit then
            res.sale, res.saleSrc = unit * qty, src
        end
    end
    if res.sale and cost and #missing == 0 then
        res.profit = res.sale - cost
        res.margin = cost > 0 and res.profit / cost or nil
    end
    -- 销量：估计每天全服卖出多少个成品；日赚 = 每次利润 × 每天能卖掉的制作次数
    if r.out and CP.Sales then
        res.perDay = CP.Sales.Rate(r.out)
        if res.profit and res.perDay then res.daily = res.profit * res.perDay / qty end
    end
    return res
end

-- 物品作为“成品”时最便宜的制作成本（给鼠标提示用）
function CP.CraftCostOf(itemID)
    local list = Producers()[itemID]
    if not list then return nil end
    local best, bestRid
    for _, rid in ipairs(list) do
        local total, missing = CP.RecipeCost(rid)
        if total and #missing == 0 then
            local unit = total / AvgQty(CP.db.recipes[rid])
            if not best or unit < best then best, bestRid = unit, rid end
        end
    end
    return best, bestRid
end
