-- 路线计算（纯逻辑，可在游戏外测试）
-- 节点：
--   Z:地区  地区（作为目的地时，进入该地区即到达）
--   S:停靠点  F:鸟点id  D:副本key  P:自定义点  X:a|b 两个地区之间的关口  START 起点
-- 有坐标（geo）时按真实距离和你的移动速度算时间；没有坐标的地区退回到“每穿过一个地区约 N 分钟”的估算。
local _, NS = ...
local D = NS.Data
local G = {}
NS.Graph = G

local SPEED = 22          -- 船/飞艇大致速度（码/秒）
local DOCK = 60           -- 默认停靠秒数
local FLY_SPEED = 32      -- 鸟点飞行速度（码/秒）
local FLY_DETOUR = 1.25
local FLY_OVERHEAD = 0.5
local WALK_DETOUR = 1.2   -- 地面路线不是直线，多算 20%
local NORM_YARDS = 12000

G.MODES = {
    fast = { board = 1, hop = 1.0, fly = 0.3, label = "最快" },
    easy = { board = 8, hop = 1.4, fly = 1.0, label = "最省心" },
}

G.FNAMES, G.PNAMES = {}, {}
G.POI = {}
for _, p in ipairs(D.POIS) do G.POI[p.key] = p end

function G.ZoneName(key) local z = D.ZONES[key]; return z and z[1] or key end
function G.StopName(key) local s = D.STOPS[key]; return s and s.zh or key end
function G.NodeName(node)
    if node == "START" then return "当前位置" end
    local kind, key = node:sub(1, 1), node:sub(3)
    if kind == "S" then return G.StopName(key) end
    if kind == "F" then return (G.FNAMES[key] or key) .. "飞行点" end
    if kind == "D" then return G.POI[key] and (G.POI[key].zh .. "入口") or key end
    if kind == "P" then return G.PNAMES[key] or "地图上的点" end
    if kind == "X" then
        local a, b = key:match("^(.-)|(.*)$")
        return G.ZoneName(a) .. "/" .. G.ZoneName(b) .. " 交界"
    end
    return G.ZoneName(key)
end

-- 节点所在的地区
function G.NodeZone(node, extra)
    local kind, key = node:sub(1, 1), node:sub(3)
    if kind == "Z" then return key end
    if kind == "S" then return D.STOPS[key] and D.STOPS[key].zone end
    if kind == "D" then return G.POI[key] and G.POI[key].zone end
    return extra and extra[node]
end

local function AddEdge(adj, from, to, e)
    adj[from] = adj[from] or {}
    e.from, e.to = from, to
    table.insert(adj[from], e)
end

local function RouteTiming(r)
    local dock = (r.dock or DOCK) / 60
    if r.fixed then return { r.fixed }, 0.5, dock end
    local legs, sum = {}, 0
    for i, l in ipairs(r.len) do legs[i] = l / SPEED / 60; sum = sum + legs[i] end
    local cycle
    if r.loop then cycle = sum + #legs * dock else cycle = 2 * (sum + dock) end
    return legs, cycle / 2, dock
end
G.RouteTiming = RouteTiming

-- 两点（大陆坐标）之间的码数
function G.Yards(geo, a, b)
    if not (a and b) or a.c ~= b.c then return nil end
    local s = geo and geo.scale and geo.scale[a.c]
    local w, h = s and s.w or NORM_YARDS, s and s.h or NORM_YARDS
    return math.sqrt(((a.x - b.x) * w) ^ 2 + ((a.y - b.y) * h) ^ 2)
end

function G.FlightTime(a, b, geo)
    local d
    if a.wx and b.wx then
        d = math.sqrt((a.wx - b.wx) ^ 2 + (a.wy - b.wy) ^ 2)
    elseif a.x and b.x then
        d = G.Yards(geo, { c = a.cont, x = a.x, y = a.y }, { c = b.cont, x = b.x, y = b.y })
            or math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) * NORM_YARDS
    else
        return nil
    end
    return d * FLY_DETOUR / FLY_SPEED / 60 + FLY_OVERHEAD
end

--[[ opts = {
    faction, mode, hearth = { zone, wait }, flights = { {id, zone, cont, x, y, wx, wy, town, stop}, ... },
    geo = {
        pos = function(node) return { c = 大陆, x = , y = } 或 nil end,   -- 大陆坐标 0~1
        pass = { ["a|b"] = { c, x, y } },                              -- 关口
        scale = { EK = { w, h }, KAL = { w, h } },                     -- 大陆地图对应多少码
        speed = 码/秒,
    },
    start = { zone = , pos = {c,x,y} },     -- 起点（精确位置）；没有则用 startNode
    goal = 节点, goalZone = 地区, goalPos = {c,x,y}, goalName = 名字
} ]]
function G.Build(opts)
    local mode = G.MODES[opts.mode or "fast"]
    local geo = opts.geo or {}
    local speed = (geo.speed and geo.speed > 0) and geo.speed or 7
    local adj = {}
    local zoneOf = {}         -- 额外节点所在地区（F/P/X/START）
    local points = {}         -- [地区] = { {node, pos}, ... }

    local function AddPoint(zone, node, pos)
        if not zone or not D.ZONES[zone] then return end
        points[zone] = points[zone] or {}
        table.insert(points[zone], { node = node, pos = pos })
    end
    local function Pos(node) return geo.pos and geo.pos(node) or nil end

    -- 地区锚点
    for key in pairs(D.ZONES) do AddPoint(key, "Z:" .. key, Pos("Z:" .. key)) end
    -- 关口 / 没坐标时的地区相邻
    for _, a in ipairs(D.ADJ) do
        local k = a[1] .. "|" .. a[2]
        local p = geo.pass and (geo.pass[k] or geo.pass[a[2] .. "|" .. a[1]])
        if p then
            local node = "X:" .. k
            zoneOf[node] = a[1]
            AddPoint(a[1], node, p)
            AddPoint(a[2], node, p)
        else
            local t = a[3]
            AddEdge(adj, "Z:" .. a[1], "Z:" .. a[2], { kind = "land", time = t, cost = t * mode.hop, zone = a[2] })
            AddEdge(adj, "Z:" .. a[2], "Z:" .. a[1], { kind = "land", time = t, cost = t * mode.hop, zone = a[1] })
        end
    end
    -- 停靠点
    for key, s in pairs(D.STOPS) do AddPoint(s.zone, "S:" .. key, Pos("S:" .. key)) end
    -- 鸟点
    local flights = opts.flights or {}
    for _, n in ipairs(flights) do
        G.FNAMES[n.id] = n.town or n.name
        local node = "F:" .. n.id
        zoneOf[node] = n.zone
        AddPoint(n.zone, node, Pos(node))
    end
    -- 起点
    local startNode = opts.startNode
    if opts.start and opts.start.zone then
        startNode = "START"
        zoneOf.START = opts.start.zone
        AddPoint(opts.start.zone, "START", opts.start.pos)
    end
    -- 终点（副本/自定义点）
    local goal = opts.goal
    if goal and (goal:sub(1, 1) == "D" or goal:sub(1, 1) == "P") then
        local gz = opts.goalZone or G.NodeZone(goal)
        zoneOf[goal] = gz
        if opts.goalName then G.PNAMES[goal:sub(3)] = opts.goalName end
        AddPoint(gz, goal, opts.goalPos or Pos(goal))
    end

    -- 地区内部：任意两点之间可以走
    for zone, list in pairs(points) do
        for i = 1, #list do
            for j = 1, #list do
                if i ~= j then
                    local p, q = list[i], list[j]
                    local t
                    local d = p.pos and q.pos and G.Yards(geo, p.pos, q.pos)
                    if d then
                        t = d * WALK_DETOUR / speed / 60
                    else
                        -- 没有坐标：用停靠点的步行时间或默认 2 分钟
                        local sp = p.node:sub(1, 1) == "S" and D.STOPS[p.node:sub(3)].walk
                        local sq = q.node:sub(1, 1) == "S" and D.STOPS[q.node:sub(3)].walk
                        t = math.max(sp or 0, sq or 0, 1.5)
                        if p.node:sub(1, 1) == "X" or q.node:sub(1, 1) == "X" then t = math.max(t, 2.5) end
                    end
                    AddEdge(adj, p.node, q.node, { kind = "walk", time = t, cost = t * mode.hop, zone = zone })
                end
            end
        end
    end
    -- 目的地是地区：进入该地区的任何一点都算到达
    if goal and goal:sub(1, 1) == "Z" then
        local gz = goal:sub(3)
        for _, p in ipairs(points[gz] or {}) do
            if p.node ~= goal then AddEdge(adj, p.node, goal, { kind = "arrive", time = 0, cost = 0, zone = gz }) end
        end
    end

    -- 交通工具
    for _, r in ipairs(D.ROUTES) do
        if r.faction == "Neutral" or r.faction == opts.faction then
            local legs, wait, dock = RouteTiming(r)
            local function Ride(a, b, travel, via)
                local t = wait + travel
                AddEdge(adj, "S:" .. a, "S:" .. b, { kind = "ride", route = r, wait = wait, travel = travel,
                    via = via, time = t, cost = t + mode.board })
            end
            if r.loop then
                local n = #r.stops
                for i = 1, n do
                    local a, b, c = r.stops[i], r.stops[i % n + 1], r.stops[(i + 1) % n + 1]
                    Ride(a, b, legs[i])
                    Ride(a, c, legs[i] + dock + legs[i % n + 1], b)
                end
            else
                Ride(r.stops[1], r.stops[2], legs[1])
                Ride(r.stops[2], r.stops[1], legs[1])
            end
        end
    end
    -- 鸟点之间
    for i, a in ipairs(flights) do
        for j, b in ipairs(flights) do
            if i ~= j and a.cont == b.cont then
                local t = G.FlightTime(a, b, geo)
                if t then AddEdge(adj, "F:" .. a.id, "F:" .. b.id, { kind = "fly", time = t, cost = t + mode.fly }) end
            end
        end
    end
    return { adj = adj, hearth = opts.hearth, mode = mode, zoneOf = zoneOf, start = startNode }
end

function G.Route(graph, start, goal)
    if start == goal then return {}, 0, 0 end
    local adj = graph.adj
    local dist, timeTo, prev, done = { [start] = 0 }, { [start] = 0 }, {}, {}
    local extra = {}
    if graph.hearth and graph.hearth.zone and D.ZONES[graph.hearth.zone] then
        local t = (graph.hearth.wait or 0) + 0.5
        extra[1] = { kind = "hearth", from = start, to = "Z:" .. graph.hearth.zone, time = t, cost = t }
    end
    while true do
        local u, best = nil, math.huge
        for node, d in pairs(dist) do
            if not done[node] and d < best then u, best = node, d end
        end
        if not u then return nil end
        if u == goal then break end
        done[u] = true
        local edges = adj[u] or {}
        if u == start and #extra > 0 then
            local merged = {}
            for _, e in ipairs(edges) do merged[#merged + 1] = e end
            for _, e in ipairs(extra) do merged[#merged + 1] = e end
            edges = merged
        end
        for _, e in ipairs(edges) do
            local nd = best + e.cost
            if not done[e.to] and (dist[e.to] == nil or nd < dist[e.to] - 1e-9) then
                dist[e.to], timeTo[e.to], prev[e.to] = nd, timeTo[u] + e.time, e
            end
        end
    end
    local path, node = {}, goal
    while node ~= start do
        local e = prev[node]
        table.insert(path, 1, e)
        node = e.from
    end
    -- 去掉零耗时的“到达”边对显示的影响：保留在路径里，Steps 会合并
    return path, timeTo[goal], dist[goal]
end

local function Fmt(min)
    if min < 1 then return "不到1分钟" end
    if min >= 60 then return string.format("约%d小时%d分", math.floor(min / 60), math.floor(min % 60 + 0.5)) end
    return string.format("约%d分钟", math.floor(min + 0.5))
end
G.Fmt = Fmt

function G.Steps(path)
    local steps = {}
    local seg
    local function flush()
        if not seg then return end
        -- 途经的地区（去掉终点所在地区和重复）
        -- 途经的地区：去掉出发地区和终点所在地区
        local via, seen = {}, {}
        for i = 2, #seg.zones - 1 do
            local z = seg.zones[i]
            if not seen[z] and z ~= seg.zones[1] and z ~= seg.zones[#seg.zones] then
                seen[z] = true
                via[#via + 1] = G.ZoneName(z)
            end
        end
        local text = "前往 " .. G.NodeName(seg.target)
        if #via > 0 then text = text .. "（途经 " .. table.concat(via, "、") .. "）" end
        steps[#steps + 1] = { kind = "travel", text = text, time = seg.time, target = seg.target, edges = seg.edges }
        seg = nil
    end
    for _, e in ipairs(path) do
        if e.kind == "land" or e.kind == "walk" or e.kind == "arrive" then
            if not seg then seg = { zones = {}, time = 0, edges = {}, firstZone = e.zone } end
            seg.time = seg.time + e.time
            -- 关口和“到达”不作为步骤的终点名字
            if e.kind == "arrive" or e.to:sub(1, 1) ~= "X" then seg.target = e.to end
            seg.target = seg.target or e.to
            table.insert(seg.edges, e)
            if e.zone and seg.zones[#seg.zones] ~= e.zone then seg.zones[#seg.zones + 1] = e.zone end
        elseif e.kind == "hearth" then
            flush()
            steps[#steps + 1] = { kind = "hearth", text = "使用炉石回到 " .. G.NodeName(e.to), time = e.time, target = e.to, edges = { e } }
        elseif e.kind == "fly" then
            flush()
            steps[#steps + 1] = { kind = "fly", text = string.format("在 %s 坐鸟飞往 %s", G.NodeName(e.from), G.NodeName(e.to)),
                time = e.time, target = e.to, board = e.from, edges = { e } }
        elseif e.kind == "ride" then
            flush()
            local r = e.route
            local a, b = e.from:sub(3), e.to:sub(3)
            local text = string.format("在 %s %s到 %s", G.StopName(a), D.TYPE_NAME[r.type] or "乘坐", G.StopName(b))
            local note
            if e.via then note = "中途在 " .. G.StopName(e.via) .. " 停靠，不要下船" end
            if r.loop then
                note = (note and (note .. "；") or "") .. "这是单向环线船（米奈希尔港→南海镇→奥伯丁→米奈希尔港）"
            end
            steps[#steps + 1] = { kind = "ride", text = text, note = note, time = e.time, wait = e.wait, travel = e.travel,
                target = e.to, board = e.from, routeType = r.type, edges = { e } }
        end
    end
    flush()
    -- 去掉开头“前往 当前位置”之类零耗时的空步骤
    local out = {}
    for _, st in ipairs(steps) do
        if not (st.kind == "travel" and st.time < 0.05 and #out == 0 and #steps > 1) then out[#out + 1] = st end
    end
    return out
end

function G.Plan(opts, start, goal)
    opts.goal = goal
    opts.startNode = start
    local graph = G.Build(opts)
    local s = graph.start or start
    local path, time = G.Route(graph, s, goal)
    if not path then return nil end
    local boards, flights = 0, 0
    for _, e in ipairs(path) do
        if e.kind == "ride" then boards = boards + 1 end
        if e.kind == "fly" then flights = flights + 1 end
    end
    return { steps = G.Steps(path), time = time, boards = boards, flights = flights, path = path, mode = opts.mode,
        zoneOf = graph.zoneOf }
end
