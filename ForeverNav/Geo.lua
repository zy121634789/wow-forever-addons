-- 地理：地区范围、大陆坐标、关口、码数换算、你的位置和移动速度（依赖游戏接口）
local _, NS = ...
local D, G = NS.Data, NS.Graph
local Geo = {}
NS.Geo = Geo

local rectCache, scaleCache, passCache = {}, {}, nil

-- 地区在大陆地图上的范围 minX, maxX, minY, maxY
function Geo.ZoneRect(zoneKey)
    local r = rectCache[zoneKey]
    if r == nil then
        r = false
        local z = D.ZONES[zoneKey]
        local id, cont = NS.MapID(zoneKey), z and NS.Taxi.ContMapID(z[3])
        if id and cont and C_Map and C_Map.GetMapRectOnMap then
            local ok, a, b, c, d = pcall(C_Map.GetMapRectOnMap, id, cont)
            if ok and a and b and b > a and d and d > c then r = { a, b, c, d } end
        end
        rectCache[zoneKey] = r
    end
    if r then return r[1], r[2], r[3], r[4] end
end
NS.ZoneRect = Geo.ZoneRect

-- 大陆地图 0~1 对应多少码
function Geo.Scale(cont)
    if scaleCache[cont] ~= nil then return scaleCache[cont] or nil end
    scaleCache[cont] = false
    local id = NS.Taxi.ContMapID(cont)
    if id and C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D then
        local function W(x, y)
            local ok, _, p = pcall(C_Map.GetWorldPosFromMapPos, id, CreateVector2D(x, y))
            if ok and p then return p.x, p.y end
        end
        local x0, y0 = W(0, 0)
        local x1, y1 = W(1, 0)
        local x2, y2 = W(0, 1)
        if x0 and x1 and x2 then
            local w = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
            local h = math.sqrt((x2 - x0) ^ 2 + (y2 - y0) ^ 2)
            if w > 100 and h > 100 then scaleCache[cont] = { w = w, h = h } end
        end
    end
    return scaleCache[cont] or nil
end

local function ZoneToCont(zone, zx, zy)
    local a, b, c, d = Geo.ZoneRect(zone)
    if not a then return nil end
    return { c = D.ZONES[zone][3], x = a + (b - a) * zx / 100, y = c + (d - c) * zy / 100 }
end
Geo.ZoneToCont = ZoneToCont

function Geo.ContToZone(zone, x, y)
    local a, b, c, d = Geo.ZoneRect(zone)
    if not a then return nil end
    return (x - a) / (b - a) * 100, (y - c) / (d - c) * 100
end

-- 节点的大陆坐标 { c, x, y }
function Geo.Pos(node)
    if node == "START" then return Geo.PlayerPos() end
    local kind, key = node:sub(1, 1), node:sub(3)
    if kind == "Z" then
        return ZoneToCont(key, 50, 50)
    elseif kind == "S" then
        local s = D.STOPS[key]
        if s and s.x then return ZoneToCont(s.zone, s.x, s.y) end
        return nil -- 没有可靠坐标的码头
    elseif kind == "F" then
        local n = NS.db.taxi[key]
        if n and n.x and (n.cont == "EK" or n.cont == "KAL") then return { c = n.cont, x = n.x, y = n.y } end
    elseif kind == "D" then
        local p = G.POI[key]
        if p and p.x then return ZoneToCont(p.zone, p.x, p.y) end
    elseif kind == "P" then
        local f = NS.db.favs[key] or (NS.custom and NS.custom.key == key and NS.custom)
        if f then return { c = f.c, x = f.x, y = f.y } end
    elseif kind == "X" then
        local p = Geo.Passes()[key]
        return p
    end
end

-- 关口：两个相邻地区范围的交界处（自动从地图范围推算）
function Geo.Passes()
    if passCache then return passCache end
    passCache = {}
    for _, a in ipairs(D.ADJ) do
        local z1, z2 = D.ZONES[a[1]], D.ZONES[a[2]]
        if z1 and z2 and z1[3] == z2[3] then
            local r1 = { Geo.ZoneRect(a[1]) }
            local r2 = { Geo.ZoneRect(a[2]) }
            if r1[1] and r2[1] then
                -- 两个范围各外扩 2% 后取交集的中心；不相交就取两个中心的中点
                local e = 0.02
                local x1, x2 = math.max(r1[1] - e, r2[1] - e), math.min(r1[2] + e, r2[2] + e)
                local y1, y2 = math.max(r1[3] - e, r2[3] - e), math.min(r1[4] + e, r2[4] + e)
                local p
                if x2 > x1 and y2 > y1 then
                    p = { c = z1[3], x = (x1 + x2) / 2, y = (y1 + y2) / 2 }
                else
                    p = { c = z1[3], x = (r1[1] + r1[2] + r2[1] + r2[2]) / 4, y = (r1[3] + r1[4] + r2[3] + r2[4]) / 4 }
                end
                passCache[a[1] .. "|" .. a[2]] = p
            end
        end
    end
    return passCache
end

-- 你在大陆上的位置
function Geo.PlayerPos()
    if not (C_Map and C_Map.GetPlayerMapPosition) then return nil end
    for _, cont in ipairs({ "EK", "KAL" }) do
        local id = NS.Taxi.ContMapID(cont)
        if id then
            local pos = C_Map.GetPlayerMapPosition(id, "player")
            if pos and pos.x and pos.x > 0 and pos.y > 0 then return { c = cont, x = pos.x, y = pos.y } end
        end
    end
end

-- 某个大陆坐标落在哪个地区（取包含它的最小范围）
function Geo.ZoneAt(c, x, y)
    local best, bestArea
    for key, z in pairs(D.ZONES) do
        if z[3] == c then
            local a, b, cc, d = Geo.ZoneRect(key)
            if a and x >= a and x <= b and y >= cc and y <= d then
                local area = (b - a) * (d - cc)
                if not bestArea or area < bestArea then best, bestArea = key, area end
            end
        end
    end
    return best
end

-- 你的移动速度：记录见过的最快地面速度（骑马后自动变快）
local function TrackSpeed()
    if not NS.db or not GetUnitSpeed then return end
    if UnitOnTaxi and UnitOnTaxi("player") then return end
    if IsSwimming and IsSwimming() then return end
    if IsFlying and IsFlying() then return end
    local s = GetUnitSpeed("player")
    if s and s > 0 and s <= 14.5 then
        local c = NS.Taxi.Char()
        if not c.speed or s > c.speed then c.speed = s end
    end
end

function Geo.Speed()
    local c = NS.Taxi.Char()
    return math.max(7, math.min(14, c.speed or 7))
end

function Geo.ForGraph()
    local scale = {}
    for _, c in ipairs({ "EK", "KAL" }) do scale[c] = Geo.Scale(c) end
    return { pos = Geo.Pos, pass = Geo.Passes(), scale = scale, speed = Geo.Speed() }
end

local f = CreateFrame("Frame")
local acc = 0
f:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 1 then return end
    acc = 0
    pcall(TrackSpeed)
end)
