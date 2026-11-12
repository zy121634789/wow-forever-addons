-- 销量估算
-- 暴雪没有提供“成交记录”接口，所以用两次全扫描之间“消失的挂单”来估算卖出了多少：
--   1. 剩余时间还很长、不可能是过期的挂单（排除过期）
--   2. 单价不高于这次扫描的最低价（买家总是从最便宜的买；被取消重挂压价的单子价格更高，排除）
-- 同时满足才算“卖出”。结果是偏保守的估计。
local _, CP = ...

local Sales = {}
CP.Sales = Sales

local MAX_GAP = 12 * 3600   -- 两次扫描间隔超过 12 小时就无法排除过期，不计入
local MIN_GAP = 5 * 60      -- 间隔太短没有意义
local UNKNOWN_OK = 2 * 3600 -- 拿不到剩余时间时，间隔 2 小时内才计入
local KEEP_OBS = 200        -- 每个物品保留多少次观察（快速扫描的观察按小时合并）
local WINDOW = 7 * 86400    -- 用最近 7 天的观察计算日销
local BAND_MIN = { [0] = 0, [1] = 1800, [2] = 7200, [3] = 43200 }

-- 剩余时间（客户端返回的档位或秒数）→ 至少还剩多少秒；-1 表示未知
function Sales.MinSecondsLeft(v)
    if type(v) ~= "number" then return -1 end
    if v > 4 then return v end -- 已经是秒数
    if C_AuctionHouse and C_AuctionHouse.GetTimeLeftBandInfo then
        local ok, minSec = pcall(C_AuctionHouse.GetTimeLeftBandInfo, v)
        if ok and type(minSec) == "number" then return minSec end
    end
    return BAND_MIN[v] or -1
end

-- listings = { {b = 一口价总额, q = 数量, m = 至少剩余秒数}, ... }
function Sales.Encode(listings)
    local parts = {}
    for i, l in ipairs(listings) do
        parts[i] = string.format("%d:%d:%d", l.b, l.q, l.m)
    end
    return table.concat(parts, ",")
end

function Sales.Decode(s)
    local list = {}
    for b, q, m in string.gmatch(s or "", "(%d+):(%d+):(%-?%d+)") do
        list[#list + 1] = { b = tonumber(b), q = tonumber(q), m = tonumber(m) }
    end
    return list
end

-- 比较同一物品的上次挂单(prev)和这次挂单(cur)，返回估计卖出的数量
function Sales.Compare(prev, cur, gap)
    -- 这次的最低单价
    local curMin
    for _, l in ipairs(cur) do
        local u = l.b / l.q
        if not curMin or u < curMin then curMin = u end
    end
    -- 按 “总价:数量” 分组计数
    local curCount = {}
    for _, l in ipairs(cur) do
        local k = l.b .. ":" .. l.q
        curCount[k] = (curCount[k] or 0) + 1
    end
    local groups = {}
    for _, l in ipairs(prev) do
        local k = l.b .. ":" .. l.q
        groups[k] = groups[k] or {}
        table.insert(groups[k], l)
    end
    local sold = 0
    for k, list in pairs(groups) do
        local gone = #list - (curCount[k] or 0)
        if gone > 0 then
            -- 保守：假设消失的是剩余时间最短的那几个（最可能是过期）
            table.sort(list, function(a, b) return a.m < b.m end)
            for i = 1, gone do
                local l = list[i]
                local notExpired
                if l.m < 0 then notExpired = gap <= UNKNOWN_OK else notExpired = l.m >= gap end
                local cheapEnough = (not curMin) or (l.b / l.q <= curMin * 1.001)
                if notExpired and cheapEnough then sold = sold + l.q end
            end
        end
    end
    return sold
end

-- 需要跟踪销量的物品：所有已知配方的成品和材料
function Sales.Tracked()
    local set = {}
    for _, r in pairs(CP.db.recipes) do
        if r.out then set[r.out] = true end
        for _, rg in ipairs(r.r or {}) do set[rg.id] = true end
    end
    for id in pairs(CP.db.watch or {}) do set[id] = true end -- 手动关注的物品
    return set
end

-- 记一次观察：h 小时内卖出 s 个。quick=true 时并入同一小时内上一条快速扫描的观察
function Sales.AddObs(itemID, now, h, s, quick)
    local obs = CP.db.sales[itemID] or {}
    local last = obs[#obs]
    if quick and last and last.k and math.floor(last.t / 3600) == math.floor(now / 3600) then
        last.h, last.s, last.t = last.h + h, last.s + s, now
    else
        table.insert(obs, { t = now, h = h, s = s, k = quick or nil })
        while #obs > KEEP_OBS do table.remove(obs, 1) end
    end
    CP.db.sales[itemID] = obs
end

-- 全扫描完成时调用：listingsByItem[itemID] = listings（只含跟踪的物品）
function Sales.OnScan(listingsByItem, tracked, now)
    local db = CP.db
    local snap = db.snap
    local gap = snap and snap.t and (now - snap.t) or nil
    if snap and snap.items and gap and gap >= MIN_GAP and gap <= MAX_GAP then
        for itemID, s in pairs(snap.items) do
            -- 最近有快速扫描数据的物品，销量由快速扫描精确统计，这里跳过以免重复计算
            local q = db.quick and db.quick[itemID]
            local quickCovered = q and q.t and now - q.t < 2 * 3600
            if tracked[itemID] and not quickCovered then
                local prev = Sales.Decode(s)
                if #prev > 0 then
                    local sold = Sales.Compare(prev, listingsByItem[itemID] or {}, gap)
                    Sales.AddObs(itemID, now, gap / 3600, sold, false)
                end
            end
        end
    end
    -- 保存这次的快照
    local items = {}
    for itemID, list in pairs(listingsByItem) do
        if #list > 0 then items[itemID] = Sales.Encode(list) end
    end
    db.snap = { t = now, items = items }
    -- 清理过期的观察
    for itemID, obs in pairs(db.sales) do
        while obs[1] and now - obs[1].t > 2 * WINDOW do table.remove(obs, 1) end
        if #obs == 0 then db.sales[itemID] = nil end
    end
end

-- 估计日销：返回 每天卖出数量, 观察总小时数, 观察次数；没有数据返回 nil
function Sales.Rate(itemID)
    local obs = CP.db.sales[itemID]
    if not obs then return nil end
    local now = CP.Now()
    local hours, sold, n = 0, 0, 0
    for _, o in ipairs(obs) do
        if now - o.t <= WINDOW then
            hours, sold, n = hours + o.h, sold + o.s, n + 1
        end
    end
    if n == 0 or hours <= 0 then return nil end
    return sold / hours * 24, hours, n
end

-- 日销的文字描述
function Sales.Label(perDay)
    if perDay == nil then return "|cff808080?|r" end
    if perDay < 0.5 then return "|cffff5050滞销|r" end
    local color = perDay >= 20 and "|cff40ff40" or (perDay >= 5 and "|cffffff40" or "|cffffa040")
    if perDay >= 100 then return color .. math.floor(perDay + 0.5) .. "|r" end
    return color .. string.format("%.1f", perDay):gsub("%.0$", "") .. "|r"
end
