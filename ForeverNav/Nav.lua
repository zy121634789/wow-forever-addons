-- 定位、炉石、规划、导航进度（到站判断、距离/剩余时间、偏航重算）、导航箭头
local ADDON, NS = ...
local D, G = NS.Data, NS.Graph

local HEARTHSTONE = 6948
local ARRIVE_YARDS = 35   -- 离目标多少码以内算到达

function NS.Print(msg) print("|cff66ddff[咕咕导航]|r " .. tostring(msg)) end

-- ---------------------------------------------------------------- 名字索引
local zoneByName, stopBySub = {}, {}
for key, z in pairs(D.ZONES) do
    zoneByName[z[1]] = key
    zoneByName[z[2]] = key
end
for key, s in pairs(D.STOPS) do
    for _, n in ipairs(s.sub or {}) do stopBySub[n] = stopBySub[n] or key end
end
NS.zoneByName, NS.stopBySub = zoneByName, stopBySub

local mapIdOf
function NS.MapID(zoneKey)
    if not mapIdOf then
        mapIdOf = {}
        if C_Map and C_Map.GetMapInfo then
            for id = 1, 3000 do
                local info = C_Map.GetMapInfo(id)
                if info and info.name then
                    local key = zoneByName[info.name]
                    if key and (not mapIdOf[key] or info.mapType == 3) then mapIdOf[key] = id end
                end
            end
        end
    end
    return mapIdOf[zoneKey]
end

function NS.CurrentNode()
    local zoneKey
    if C_Map and C_Map.GetBestMapForUnit then
        local id = C_Map.GetBestMapForUnit("player")
        local guard = 0
        while id and guard < 10 do
            local info = C_Map.GetMapInfo(id)
            if not info then break end
            if zoneByName[info.name] then zoneKey = zoneByName[info.name]; break end
            id = info.parentMapID
            guard = guard + 1
        end
    end
    if not zoneKey and GetZoneText then zoneKey = zoneByName[GetZoneText() or ""] end
    local sub = (GetSubZoneText and GetSubZoneText()) or ""
    local stopKey = stopBySub[sub]
    if not stopKey and GetMinimapZoneText then stopKey = stopBySub[GetMinimapZoneText() or ""] end
    if stopKey and zoneKey and D.STOPS[stopKey].zone ~= zoneKey then stopKey = nil end
    if not zoneKey and stopKey then zoneKey = D.STOPS[stopKey].zone end
    return zoneKey and ("Z:" .. zoneKey) or nil, stopKey and ("S:" .. stopKey) or nil, zoneKey
end

-- ---------------------------------------------------------------- 炉石
function NS.Hearth()
    local count = 0
    if C_Item and C_Item.GetItemCount then count = C_Item.GetItemCount(HEARTHSTONE) or 0
    elseif GetItemCount then count = GetItemCount(HEARTHSTONE) or 0 end
    if count == 0 then return nil end
    local bind = GetBindLocation and GetBindLocation()
    if not bind then return nil end
    local zone = D.INNS[bind] or zoneByName[bind] or (stopBySub[bind] and D.STOPS[stopBySub[bind]].zone)
    if not zone then return nil, bind end
    local start, duration
    if C_Container and C_Container.GetItemCooldown then
        start, duration = C_Container.GetItemCooldown(HEARTHSTONE)
    elseif GetItemCooldown then
        start, duration = GetItemCooldown(HEARTHSTONE)
    end
    local wait = 0
    if start and duration and start > 0 and duration > 0 then wait = math.max(0, start + duration - GetTime()) / 60 end
    return { zone = zone, wait = wait, name = bind }
end

-- 兼容旧调用
function NS.ContPos(node)
    local p = NS.Geo.Pos(node)
    if p then return p.c, p.x, p.y end
end

-- ---------------------------------------------------------------- 规划
-- 目的地的补充信息（自定义点、收藏）
NS.custom = nil -- { key, name, c, x, y, zone }

local function GoalInfo(goal)
    local kind, key = goal:sub(1, 1), goal:sub(3)
    if kind == "D" then
        local p = G.POI[key]
        return { zone = p.zone, pos = NS.Geo.Pos(goal), name = p.zh }
    elseif kind == "P" then
        local f = NS.db.favs[key] or (NS.custom and NS.custom.key == key and NS.custom)
        if f then return { zone = f.zone, pos = { c = f.c, x = f.x, y = f.y }, name = f.name } end
    end
    return {}
end

function NS.PlanBoth(goal)
    local zoneNode, stopNode, zoneKey = NS.CurrentNode()
    local pos = NS.Geo.PlayerPos()
    if not zoneKey and pos then zoneKey = NS.Geo.ZoneAt(pos.c, pos.x, pos.y) end
    if not zoneKey then return nil, "无法识别你现在所在的地区" end
    local faction = UnitFactionGroup and UnitFactionGroup("player") or "Alliance"
    local hearth = NS.db.settings.useHearth and NS.Hearth() or nil
    local flights = NS.db.settings.useFlights and NS.Taxi.ForPlanning() or nil
    local gi = GoalInfo(goal)
    if (goal:sub(1, 1) == "D" or goal:sub(1, 1) == "P") and not (gi.zone and D.ZONES[gi.zone]) then
        return nil, "目的地所在地区未知"
    end
    local geo = NS.Geo.ForGraph()
    local res = { nFlights = flights and #flights or 0, goal = goal, goalName = gi.name or G.NodeName(goal) }
    for _, mode in ipairs({ "fast", "easy" }) do
        local opts = { faction = faction, mode = mode, hearth = hearth, flights = flights, geo = geo,
            start = { zone = zoneKey, pos = pos }, goalZone = gi.zone, goalPos = gi.pos, goalName = gi.name }
        res[mode] = G.Plan(opts, stopNode or zoneNode, goal)
    end
    if not res.fast then return nil, "找不到路线（可能需要对方阵营的交通工具，或目的地陆路连接未知）" end
    return res
end

-- ---------------------------------------------------------------- 导航
NS.nav = nil -- { goal, mode, plan, step, both, offCount }

local function ClearWaypoint()
    if C_Map and C_Map.ClearUserWaypoint then pcall(C_Map.ClearUserWaypoint) end
end

-- 当前这一步要去的点（有坐标时）：返回 节点, {c,x,y}
function NS.StepTargetPos(step)
    if not step then return nil end
    local node = (step.kind == "ride" or step.kind == "fly") and step.board or step.target
    if node and node:sub(1, 1) == "Z" then return node, nil end
    return node, node and NS.Geo.Pos(node)
end

function NS.UpdateWaypoint()
    ClearWaypoint()
    local nav = NS.nav
    if not nav or not NS.db.settings.arrow then return end
    local _, p = NS.StepTargetPos(nav.plan.steps[nav.step])
    if not p then return end
    if not (C_Map and C_Map.SetUserWaypoint and UiMapPoint) then return end
    local zone = NS.Geo.ZoneAt(p.c, p.x, p.y)
    local mapID = zone and NS.MapID(zone)
    local x, y
    if mapID then x, y = NS.Geo.ContToZone(zone, p.x, p.y) end
    if not x then
        mapID, x, y = NS.Taxi.ContMapID(p.c), p.x * 100, p.y * 100
    end
    if not mapID then return end
    if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(mapID) then return end
    local ok = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(mapID, x / 100, y / 100))
    if ok and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
    end
end

local function Announce()
    local nav = NS.nav
    local step = nav.plan.steps[nav.step]
    if not step then return end
    NS.Print(string.format("第 %d/%d 步：%s", nav.step, #nav.plan.steps, step.text))
    if step.note then NS.Print("　" .. step.note) end
end

local function Changed()
    if NS.OnNavChanged then NS.OnNavChanged() end
end

function NS.StartNav(goal, mode, quiet)
    local res, err = NS.PlanBoth(goal)
    if not res then NS.Print(err); return false end
    mode = mode or NS.db.settings.mode
    local plan = res[mode] or res.fast
    if #plan.steps == 0 then NS.Print("你已经在 " .. res.goalName .. " 了。"); return false end
    NS.nav = { goal = goal, mode = mode, plan = plan, step = 1, both = res, name = res.goalName, offCount = 0 }
    NS.db.lastGoal = goal
    if not quiet then
        NS.Print(string.format("开始导航到 %s（%s，%s，换乘 %d 次%s）", res.goalName, G.MODES[mode].label, G.Fmt(plan.time),
            plan.boards, plan.flights > 0 and ("，坐鸟 " .. plan.flights .. " 次") or ""))
    end
    Announce()
    NS.UpdateWaypoint()
    Changed()
    return true
end

function NS.StopNav(silent)
    if NS.nav and not silent then NS.Print("导航已停止。") end
    NS.nav = nil
    ClearWaypoint()
    Changed()
end

local function Arrived()
    local nav = NS.nav
    local p = G.POI[nav.goal:sub(3)]
    NS.Print("|cff40ff40已到达 " .. nav.name .. "！|r")
    if nav.goal:sub(1, 1) == "D" and p and not p.x and p.hint then
        NS.Print("入口提示：" .. p.hint)
    end
    if PlaySound and SOUNDKIT and SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01 then pcall(PlaySound, SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01) end
    NS.StopNav(true)
end

local function Near(node, ppos)
    if not ppos then return false end
    local p = NS.Geo.Pos(node)
    if not p then return false end
    local d = G.Yards(NS.Geo.ForGraph(), ppos, p)
    return d and d <= ARRIVE_YARDS
end

-- 检查有没有完成后面的某一步
function NS.CheckProgress()
    local nav = NS.nav
    if not nav then return end
    local zoneNode, stopNode, zoneKey = NS.CurrentNode()
    local ppos = NS.Geo.PlayerPos()
    if not zoneKey and ppos then zoneKey = NS.Geo.ZoneAt(ppos.c, ppos.x, ppos.y) end
    local goal = nav.goal
    local gkind = goal:sub(1, 1)
    -- 终点
    if goal == zoneNode or goal == stopNode or Near(goal, ppos) then return Arrived() end
    if gkind == "D" or gkind == "P" then
        local gpos = NS.Geo.Pos(goal)
        local gz = nav.plan.zoneOf and nav.plan.zoneOf[goal]
        if not gpos and gz == zoneKey then return Arrived() end -- 入口坐标未知：进入所在地区即算到
    end
    local steps = nav.plan.steps
    local sub = GetSubZoneText and GetSubZoneText() or ""
    local mini = GetMinimapZoneText and GetMinimapZoneText() or ""
    local reached
    for i = nav.step, #steps do
        local st = steps[i]
        local t = st.target
        local kind = t:sub(1, 1)
        local hit = t == zoneNode or (stopNode and t == stopNode) or Near(t, ppos)
        if not hit and kind == "F" then
            local n = NS.db.taxi[t:sub(3)]
            if n then
                if n.town and (sub == n.town or mini == n.town) then hit = true end
                if st.kind == "fly" and n.zone == zoneKey then
                    local from = NS.db.taxi[st.board:sub(3)]
                    if not from or from.zone ~= zoneKey then hit = true end
                end
                if zoneByName[n.town or ""] == zoneKey then hit = true end
            end
        elseif not hit and kind == "S" then
            local s = D.STOPS[t:sub(3)]
            if #(s.sub or {}) == 0 and not s.x and s.zone == zoneKey then hit = true end
            if st.kind == "ride" and s.zone == zoneKey and D.STOPS[st.board:sub(3)].zone ~= zoneKey then hit = true end
        end
        if hit then reached = i end
    end
    if reached then
        nav.step = reached + 1
        if nav.step > #steps then return Arrived() end
        Announce()
        NS.UpdateWaypoint()
        Changed()
    end
end

-- 当前一步还有多远、全程还要多久
function NS.NavInfo()
    local nav = NS.nav
    if not nav then return nil end
    local st = nav.plan.steps[nav.step]
    if not st then return nil end
    local ppos = NS.Geo.PlayerPos()
    local _, tpos = NS.StepTargetPos(st)
    local dist = ppos and tpos and G.Yards(NS.Geo.ForGraph(), ppos, tpos)
    local cur = st.time
    if dist and (st.kind == "travel") then cur = dist * 1.2 / NS.Geo.Speed() / 60 end
    local rest = 0
    for i = nav.step + 1, #nav.plan.steps do rest = rest + nav.plan.steps[i].time end
    -- 朝向：目标相对你面朝方向的角度（弧度）
    local angle
    if dist and dist > 5 and GetPlayerFacing then
        local ok, facing = pcall(GetPlayerFacing)
        if ok and type(facing) == "number" and not (issecretvalue and issecretvalue(facing)) then
            local s = NS.Geo.Scale(ppos.c) or { w = 1, h = 1 }
            local dx, dy = (tpos.x - ppos.x) * s.w, (tpos.y - ppos.y) * s.h
            -- 地图上北是 -y；游戏朝向 0 = 北，逆时针增加
            angle = math.atan2(-dx, -dy) - facing
        end
    end
    return { step = st, dist = dist, eta = cur + rest, angle = angle }
end

-- 偏航：你所在的地区不在剩余路线上，连续 10 秒就重新规划
local function RouteZones(nav)
    local set = {}
    for i = nav.step, #nav.plan.steps do
        local st = nav.plan.steps[i]
        for _, e in ipairs(st.edges or {}) do
            if e.zone then set[e.zone] = true end
            for _, n in ipairs({ e.from, e.to }) do
                local z = G.NodeZone(n, nav.plan.zoneOf)
                if z then set[z] = true end
            end
        end
    end
    return set
end

function NS.CheckOffRoute()
    local nav = NS.nav
    if not nav or not NS.db.settings.autoReroute then return end
    if UnitOnTaxi and UnitOnTaxi("player") then nav.offCount = 0; return end
    local _, _, zoneKey = NS.CurrentNode()
    if not zoneKey then nav.offCount = 0; return end -- 在海上/船上等未知区域不判断
    local set = RouteZones(nav)
    if set[zoneKey] then nav.offCount = 0; return end
    nav.offCount = (nav.offCount or 0) + 1
    if nav.offCount >= 2 then
        NS.Print("你偏离了路线，已重新规划。")
        NS.StartNav(nav.goal, nav.mode, true)
    end
end

-- ---------------------------------------------------------------- 事件与存档
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ZONE_CHANGED")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("ZONE_CHANGED_INDOORS")
frame:SetScript("OnEvent", function(_, event, arg)
    if event == "ADDON_LOADED" then
        if arg ~= ADDON then return end
        ForeverNavDB = ForeverNavDB or {}
        ForeverNavDB.settings = ForeverNavDB.settings or {}
        local s = ForeverNavDB.settings
        if s.mode == nil then s.mode = "easy" end
        if s.useHearth == nil then s.useHearth = true end
        if s.arrow == nil then s.arrow = true end
        if s.useFlights == nil then s.useFlights = true end
        if s.autoReroute == nil then s.autoReroute = true end
        ForeverNavDB.chars = ForeverNavDB.chars or {}
        ForeverNavDB.taxi = ForeverNavDB.taxi or {}
        ForeverNavDB.favs = ForeverNavDB.favs or {}   -- [key] = { name, c, x, y, zone }
        NS.db = ForeverNavDB
        return
    end
    if not NS.db then return end
    local ok, err = pcall(NS.CheckProgress)
    if not ok then NS.Print("出错：" .. tostring(err)) end
    if NS.OnLocationChanged then NS.OnLocationChanged() end
end)

-- 每秒：距离判断到站；每 5 秒：偏航检查
local ticker = CreateFrame("Frame")
local acc, offAcc = 0, 0
ticker:SetScript("OnUpdate", function(_, dt)
    if not NS.nav then return end
    acc, offAcc = acc + dt, offAcc + dt
    if acc >= 1 then
        acc = 0
        local ok, err = pcall(NS.CheckProgress)
        if not ok then NS.Print("出错：" .. tostring(err)) end
        if NS.OnNavTick then NS.OnNavTick() end
    end
    if offAcc >= 5 then
        offAcc = 0
        pcall(NS.CheckOffRoute)
    end
end)

-- ---------------------------------------------------------------- 搜索
-- 返回 { node, name, sub, kind } 列表；kind: zone/stop/dungeon/raid/fav
function NS.Search(text, filter)
    text = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local out = {}
    local function score(name)
        if not name then return nil end
        local n = name:lower()
        if text == "" then return 3 end
        if n == text then return 0 end
        if n:sub(1, #text) == text then return 1 end
        if n:find(text, 1, true) then return 2 end
    end
    local function best(...)
        local b
        for i = 1, select("#", ...) do
            local s = score((select(i, ...)))
            if s and (not b or s < b) then b = s end
        end
        return b
    end
    local function want(kind) return not filter or filter == kind end
    if want("zone") and text ~= "" then
        for key, z in pairs(D.ZONES) do
            local sc = best(z[1], z[2])
            if sc then out[#out + 1] = { node = "Z:" .. key, name = z[1], sc = sc, kind = "zone", city = z[4] } end
        end
    end
    if want("stop") then
        for key, s in pairs(D.STOPS) do
            local sc = best(s.zh, s.en)
            if sc then out[#out + 1] = { node = "S:" .. key, name = s.zh, sc = sc + 0.3, kind = "stop", sub = G.ZoneName(s.zone) .. " 码头" } end
        end
    end
    for _, p in ipairs(D.POIS) do
        if want(p.kind) then
            local sc = best(p.zh, p.en, unpack(p.alias or {}))
            if sc then
                out[#out + 1] = { node = "D:" .. p.key, name = p.zh, sc = sc + 0.1, kind = p.kind,
                    sub = G.ZoneName(p.zone) .. " · " .. p.lv .. (p.new and " · 新" or "") .. (p.open and (" · " .. p.open) or "") }
            end
        end
    end
    if want("fav") then
        for key, f in pairs(NS.db.favs) do
            local sc = best(f.name)
            if sc then out[#out + 1] = { node = "P:" .. key, name = f.name, sc = sc, kind = "fav", sub = G.ZoneName(f.zone or "?") } end
        end
    end
    if want("flight") then
        for _, n in ipairs(NS.Taxi.ForPlanning()) do
            local sc = best(n.town, n.name)
            if sc then out[#out + 1] = { node = "Z:" .. n.zone, name = n.town, sc = sc + 0.5, kind = "flight", sub = G.ZoneName(n.zone) .. " 飞行点", fid = n.id } end
        end
    end
    table.sort(out, function(a, b)
        if a.sc ~= b.sc then return a.sc < b.sc end
        return a.name < b.name
    end)
    return out
end

-- 收藏当前位置
function NS.AddFavorite(name)
    local pos = NS.Geo.PlayerPos()
    local _, _, zoneKey = NS.CurrentNode()
    if not pos then NS.Print("拿不到你现在的坐标（副本里不能收藏）。"); return end
    zoneKey = zoneKey or NS.Geo.ZoneAt(pos.c, pos.x, pos.y)
    local key = tostring(time()) .. tostring(math.random(100, 999))
    name = (name and name ~= "") and name or ((GetSubZoneText and GetSubZoneText() ~= "" and GetSubZoneText()) or G.ZoneName(zoneKey or "?"))
    NS.db.favs[key] = { name = name, c = pos.c, x = pos.x, y = pos.y, zone = zoneKey }
    NS.Print("已收藏：" .. name)
    return key
end

-- 地图上任意一点作为目的地
function NS.SetCustomGoal(c, x, y, name)
    local zone = NS.Geo.ZoneAt(c, x, y)
    if not zone then NS.Print("这个位置不在已知地区里。"); return nil end
    NS.custom = { key = "custom", name = name or ("地图标记（" .. G.ZoneName(zone) .. "）"), c = c, x = x, y = y, zone = zone }
    return "P:custom"
end
