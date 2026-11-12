-- 量化交易：记录基础材料的价格历史，计算指标，给出买卖建议
-- 策略核心是“均值回归”：价格明显低于近 7 天均价且有人在买 → 买入；明显高于均价 → 卖出/暂缓购买。
-- 再用供应量、短期趋势、流动性（日销）过滤掉“接飞刀”和“买了卖不掉”的情况。
local _, CP = ...

local Q = {}
CP.Quant = Q

local KEEP = 21 * 86400      -- 历史保留 21 天
local FINE_MERGE = 50        -- 50 秒内的多次记录合并成一个点
local FINE_KEEP = 86400      -- 最近 24 小时保留分钟级明细，更早的压缩成每小时一个点
local HOUR = 3600
local DAY = 86400
local MIN_POINTS = 6         -- 至少几个点才给建议
local MIN_SPAN = DAY         -- 至少覆盖多长时间才给建议
local STD_FLOOR = 0.03       -- 波动率下限（均价的 3%），避免价格几乎不动时一点点偏离就报警

Q.ACTIONS = {
    strong_buy = { label = "强烈买入", color = "|cff00ff66" },
    buy        = { label = "买入",     color = "|cff66ff99" },
    stock      = { label = "适合备货", color = "|cff99ddff" },
    wait       = { label = "等待",     color = "|cffffcc33" },
    hold       = { label = "观望",     color = "|cffbbbbbb" },
    sell       = { label = "偏高可卖", color = "|cffff9944" },
    strong_sell = { label = "高位卖出", color = "|cffff4444" },
    nodata     = { label = "数据不足", color = "|cff777777" },
}

-- ---------------------------------------------------------------- 历史数据
local cache = {}

local function Decode(s)
    local pts = {}
    for t, m, q in string.gmatch(s or "", "(%d+):(%d+):(%d+)") do
        pts[#pts + 1] = { t = tonumber(t), m = tonumber(m), q = tonumber(q) }
    end
    return pts
end

local function Encode(pts)
    local parts = {}
    for i, p in ipairs(pts) do parts[i] = string.format("%d:%d:%d", p.t, p.m, p.q) end
    return table.concat(parts, ",")
end
Q.Decode, Q.Encode = Decode, Encode

function Q.History(itemID)
    local pts = cache[itemID]
    if not pts then
        pts = Decode(CP.db.hist[itemID])
        cache[itemID] = pts
    end
    return pts
end

-- 把 24 小时以前的点按小时合并（取平均），控制存档大小
local function Compact(pts, now)
    local out, bucket = {}, nil
    local function flush()
        if bucket then
            out[#out + 1] = { t = math.floor(bucket.t / bucket.n), m = math.floor(bucket.m / bucket.n + 0.5), q = math.floor(bucket.q / bucket.n + 0.5) }
            bucket = nil
        end
    end
    for _, p in ipairs(pts) do
        if now - p.t > KEEP then
            -- 丢弃
        elseif now - p.t > FINE_KEEP then
            local h = math.floor(p.t / HOUR)
            if bucket and bucket.h ~= h then flush() end
            bucket = bucket or { h = h, t = 0, m = 0, q = 0, n = 0 }
            bucket.t, bucket.m, bucket.q, bucket.n = bucket.t + p.t, bucket.m + p.m, bucket.q + p.q, bucket.n + 1
        else
            flush()
            out[#out + 1] = p
        end
    end
    flush()
    return out
end
Q.Compact = Compact

-- 给一个物品记一个价格点（全扫描和快速扫描都用它）
function Q.RecordOne(itemID, m, q, now)
    if not m then return end
    local db = CP.db
    local pts = Decode(db.hist[itemID])
    local last = pts[#pts]
    local point = { t = now, m = math.floor(m + 0.5), q = q or 0 }
    if last and now - last.t < FINE_MERGE and now >= last.t then pts[#pts] = point else pts[#pts + 1] = point end
    db.hist[itemID] = Encode(Compact(pts, now))
    cache[itemID] = nil
end

-- 全扫描完成时调用：给跟踪的物品各记一个价格点
function Q.Record(tracked, now)
    local db = CP.db
    for itemID in pairs(tracked) do
        local p = db.prices[itemID]
        if p and p.t == now and p.m then Q.RecordOne(itemID, p.m, p.q, now) end
    end
    -- 清理不再跟踪、且数据已过期的物品
    for itemID, s in pairs(db.hist) do
        local last = tonumber(string.match(s, "(%d+):%d+:%d+$") or 0)
        if now - last > KEEP then db.hist[itemID] = nil end
    end
    cache = {}
end

-- ---------------------------------------------------------------- 关注的材料
-- 基础材料 = 已知配方用到的材料里，不能被已知配方做出来、也不是商人随便买的那些；外加手动关注的物品
function Q.Materials()
    local db = CP.db
    local produced, set = {}, {}
    for _, r in pairs(db.recipes) do
        if r.out then produced[r.out] = true end
    end
    for _, r in pairs(db.recipes) do
        for _, rg in ipairs(r.r or {}) do
            local id = rg.id
            local v, p = db.vendor[id], db.prices[id]
            local vendorItem = v and (not p or not p.m or v <= p.m)
            if not produced[id] and not vendorItem then set[id] = true end
        end
    end
    for id in pairs(db.watch) do set[id] = true end
    return set
end

-- ---------------------------------------------------------------- 指标
local function Mean(list, key)
    local s = 0
    for _, v in ipairs(list) do s = s + v[key] end
    return #list > 0 and s / #list or nil
end

function Q.Stats(itemID, now)
    now = now or CP.Now()
    local pts = Q.History(itemID)
    if #pts == 0 then return nil end
    local st = { n = 0, cur = pts[#pts].m, curQ = pts[#pts].q, lastT = pts[#pts].t }
    -- 优先用最新的价格（可能来自浏览时顺手记录的）
    local p = CP.db.prices[itemID]
    if p and p.m and p.t and p.t > st.lastT then st.cur, st.curQ, st.lastT = p.m, p.q or st.curQ, p.t end

    -- 先按小时取平均再统计：快速扫描每分钟一个点、全扫描几小时一个点，
    -- 不这样处理的话，开着拍卖行的那几个小时会在均价里占过大的比重
    local hourly, byHour = {}, {}
    for _, pt in ipairs(pts) do
        local h = math.floor(pt.t / HOUR)
        local b = byHour[h]
        if not b then
            b = { t = 0, m = 0, q = 0, n = 0 }
            byHour[h] = b
            hourly[#hourly + 1] = b
        end
        b.t, b.m, b.q, b.n = b.t + pt.t, b.m + pt.m, b.q + pt.q, b.n + 1
    end
    for _, b in ipairs(hourly) do b.t, b.m, b.q = b.t / b.n, b.m / b.n, b.q / b.n end
    pts = hourly

    local w7, w24, w14 = {}, {}, {}
    for _, pt in ipairs(pts) do
        local age = now - pt.t
        if age <= 7 * DAY then w7[#w7 + 1] = pt end
        if age <= DAY then w24[#w24 + 1] = pt end
        if age <= 14 * DAY then w14[#w14 + 1] = pt end
    end
    st.n = #w7
    st.span = #w7 > 0 and (w7[#w7].t - w7[1].t) or 0
    st.mean = Mean(w7, "m")
    st.meanQ = Mean(w7, "q")
    st.ma24 = Mean(w24, "m")
    if st.mean then
        local var = 0
        st.min, st.max = math.huge, 0
        for _, pt in ipairs(w7) do
            var = var + (pt.m - st.mean) ^ 2
            if pt.m < st.min then st.min = pt.m end
            if pt.m > st.max then st.max = pt.m end
        end
        st.std = math.max(math.sqrt(var / #w7), st.mean * STD_FLOOR)
        st.z = (st.cur - st.mean) / st.std
        st.dev = (st.cur - st.mean) / st.mean
        st.trend = st.ma24 and (st.ma24 - st.mean) / st.mean or 0
        st.supply = (st.meanQ and st.meanQ > 0) and (st.curQ or 0) / st.meanQ or nil
    end
    -- 百分位：现价在 14 天里处于什么位置（0=最低 1=最高）
    if #w14 > 1 then
        local below = 0
        for _, pt in ipairs(w14) do if pt.m < st.cur then below = below + 1 end end
        st.pct = below / (#w14 - 1)
        if st.pct > 1 then st.pct = 1 end
    end
    -- 14 天每日均价（画图用），bars[14] 是今天
    st.bars = {}
    for d = 13, 0, -1 do
        local from, to = now - (d + 1) * DAY, now - d * DAY
        local s, c = 0, 0
        for _, pt in ipairs(pts) do
            if pt.t > from and pt.t <= to then s, c = s + pt.m, c + 1 end
        end
        st.bars[14 - d] = c > 0 and s / c or false
    end
    return st
end

-- 当前挂单里，单价不高于 price 的数量（优先用快速扫描的结果，其次是上次全扫描的快照）
function Q.AvailableBelow(itemID, price)
    local quick = CP.Quick and CP.Quick.Listings(itemID)
    if quick then
        local n = 0
        for _, a in ipairs(quick) do
            if a.u <= price then n = n + a.q end
        end
        return n
    end
    local snap = CP.db.snap
    local s = snap and snap.items and snap.items[itemID]
    if not s then return nil end
    local n = 0
    for _, l in ipairs(CP.Sales.Decode(s)) do
        if l.b / l.q <= price then n = n + l.q end
    end
    return n
end

local function Owned(itemID)
    if C_Item and C_Item.GetItemCount then
        local ok, n = pcall(C_Item.GetItemCount, itemID, true)
        if ok and type(n) == "number" then return n end
    end
    return 0
end

-- ---------------------------------------------------------------- 建议
function Q.Advise(itemID, now)
    local st = Q.Stats(itemID, now)
    local adv = { itemID = itemID, stats = st, reasons = {}, score = 0, owned = Owned(itemID) }
    local R = adv.reasons
    if not st or not st.mean or st.n < MIN_POINTS or st.span < MIN_SPAN then
        adv.action = "nodata"
        R[#R + 1] = string.format("需要至少 %d 个小时有价格记录、覆盖 1 天以上（现在 %d 个小时）", MIN_POINTS, st and st.n or 0)
        return adv
    end
    local cut = CP.db.settings.cut or 0.05
    local rate = CP.Sales.Rate(itemID)
    adv.rate = rate
    local liquid = rate and rate >= 1
    local z, dev = st.z, st.dev

    -- 目标价：买入价 = 均价 − 1 个标准差；卖出价 = 均价
    adv.buyPrice = st.mean - st.std
    adv.sellPrice = st.mean
    adv.edge = st.mean * (1 - cut) - st.cur -- 现价买入、回到均价卖出，每个能赚多少（扣手续费）

    local falling = st.trend < -0.12 and st.supply and st.supply > 1.4

    if z <= -1 then
        if falling then
            adv.action = "wait"
            R[#R + 1] = string.format("价格比 7 日均价低 %.0f%%，但 24 小时内还在快速下跌，在售量是平时的 %.1f 倍", -dev * 100, st.supply)
            R[#R + 1] = "供应正在涌入，可能还会更低：等跌势停下再买"
        elseif adv.edge > 0 and liquid then
            adv.action = z <= -2 and "strong_buy" or "buy"
            R[#R + 1] = string.format("价格比 7 日均价低 %.0f%%（偏离 %.1f 个标准差）", -dev * 100, -z)
            R[#R + 1] = string.format("有人在买：估计每天卖出 %.0f 个", rate)
        else
            adv.action = "stock"
            R[#R + 1] = string.format("价格比 7 日均价低 %.0f%%，适合给自己做东西备货", -dev * 100)
            if not liquid then R[#R + 1] = "日销太低或未知，不建议买来倒卖" end
            if adv.edge <= 0 then R[#R + 1] = "扣掉手续费后转卖没有差价" end
        end
    elseif z >= 1 then
        adv.action = z >= 2 and "strong_sell" or "sell"
        R[#R + 1] = string.format("价格比 7 日均价高 %.0f%%（偏离 %.1f 个标准差）", dev * 100, z)
        if adv.owned > 0 then
            R[#R + 1] = string.format("你有 %d 个，现在卖比平时多赚约 %s", adv.owned,
                CP.Money((st.cur - st.mean) * adv.owned * (1 - cut), true))
        end
        R[#R + 1] = "做东西需要的话暂缓购买，等价格回落"
    else
        adv.action = "hold"
        R[#R + 1] = string.format("价格在正常区间（比均价 %s%.0f%%）", dev >= 0 and "高" or "低", math.abs(dev) * 100)
    end

    if st.trend and math.abs(st.trend) >= 0.08 then
        R[#R + 1] = string.format("24 小时均价比 7 日均价%s %.0f%%", st.trend > 0 and "高" or "低", math.abs(st.trend) * 100)
    end
    if st.supply and (st.supply >= 1.5 or st.supply <= 0.6) then
        R[#R + 1] = string.format("在售量是平时的 %.1f 倍%s", st.supply, st.supply <= 0.6 and "（货少，容易涨价）" or "（货多）")
    end

    -- 建议数量：均价以下能买到的量，最多 2 天的销量
    if adv.action == "buy" or adv.action == "strong_buy" then
        local avail = Q.AvailableBelow(itemID, adv.buyPrice * 1.001) or 0
        local cap = rate and math.floor(rate * 2) or avail
        adv.qty = math.min(avail, cap)
        if adv.qty > 0 then
            R[#R + 1] = string.format("建议 %s 以下买入约 %d 个（不超过 2 天销量），回到均价每个约赚 %s",
                CP.Money(adv.buyPrice, true), adv.qty, CP.Money(adv.edge, true))
        end
    end

    -- 排序分：买入信号越强越靠前，然后是卖出信号
    local liq = liquid and math.min(2, 1 + math.log(rate) / 5) or 0.5
    if adv.action == "strong_buy" or adv.action == "buy" then
        adv.score = 100 - z * 10 * liq
    elseif adv.action == "strong_sell" or adv.action == "sell" then
        adv.score = 50 + z * 10 + (adv.owned > 0 and 20 or 0)
    elseif adv.action == "stock" then
        adv.score = 40 - z * 5
    elseif adv.action == "wait" then
        adv.score = 30
    else
        adv.score = 10 - math.abs(z)
    end
    return adv
end

-- 所有关注材料的建议，按信号强弱排序
function Q.All(filter)
    local list = {}
    for id in pairs(Q.Materials()) do
        local a = Q.Advise(id)
        local keep = true
        if filter == "buy" then keep = a.action == "buy" or a.action == "strong_buy" or a.action == "stock"
        elseif filter == "sell" then keep = a.action == "sell" or a.action == "strong_sell" end
        if keep then list[#list + 1] = a end
    end
    table.sort(list, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.itemID < b.itemID
    end)
    return list
end

-- 扫描完成后在聊天框提示最强的几个机会
function Q.Alert()
    if not CP.db.settings.quantAlert then return end
    local shown = 0
    for _, a in ipairs(Q.All()) do
        if a.action == "strong_buy" or a.action == "buy" or a.action == "strong_sell"
            or (a.action == "sell" and a.owned > 0) then
            if shown == 0 then CP.Print("量化提醒（/cpf qt 查看详情）：") end
            local def = Q.ACTIONS[a.action]
            print(string.format("  %s%s|r %s　现价 %s　均价 %s", def.color, def.label, CP.ItemName(a.itemID),
                CP.Money(a.stats.cur, true), CP.Money(a.stats.mean, true)))
            shown = shown + 1
            if shown >= 3 then break end
        end
    end
end
