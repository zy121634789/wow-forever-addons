-- 鸟点（飞行点）：在飞行管理员处打开飞行地图时，记录本角色已解锁的鸟点
-- 游戏只在飞行地图打开时提供“已解锁”信息，所以每个角色需要在任意飞行管理员处打开一次飞行地图来同步。
local _, NS = ...
local D = NS.Data
local T = {}
NS.Taxi = T

function T.CharKey()
    local name, realm = UnitFullName("player")
    return (name or "?") .. "-" .. (realm or GetRealmName() or "?")
end

function T.Char()
    local key = T.CharKey()
    local c = NS.db.chars[key]
    if not c then
        c = { known = {}, synced = 0 }
        NS.db.chars[key] = c
    end
    local _, class = UnitClass("player")
    c.faction = UnitFactionGroup("player")
    c.class = class
    return c, key
end

-- 大陆 key → uiMapID
local contMapID
function T.ContMapID(contKey)
    if not contMapID then
        contMapID = {}
        local names = {}
        for key, n in pairs(D.CONTINENTS) do names[n[1]] = key; names[n[2]] = key end
        if C_Map and C_Map.GetMapInfo then
            for id = 1, 3000 do
                local info = C_Map.GetMapInfo(id)
                if info and info.mapType == 2 and names[info.name] and not contMapID[names[info.name]] then
                    contMapID[names[info.name]] = id
                end
            end
        end
    end
    return contMapID[contKey]
end

function T.ContKeyOfMap(mapID)
    for key in pairs(D.CONTINENTS) do
        if T.ContMapID(key) == mapID then return key end
    end
    return nil
end

-- 鸟点名字 “奥伯丁，黑海岸” → 城镇名、地区key、停靠点key
local function ParseName(name)
    local parts = {}
    -- 注意：“，”是 3 个字节，不能放进 [^...] 字符类里（会按单个字节拆开中文），先替换成英文逗号
    local plain = (name or ""):gsub("，", ",")
    for p in string.gmatch(plain, "[^,]+") do parts[#parts + 1] = (p:gsub("^%s+", ""):gsub("%s+$", "")) end
    local town = parts[1] or name or "?"
    local zone = NS.zoneByName[town] or NS.zoneByName[parts[#parts] or ""]
    local stop
    for sub, key in pairs(NS.stopBySub) do
        if town == sub or (#town >= 6 and sub:find(town, 1, true)) or town:find(sub, 1, true) then
            if not zone or D.STOPS[key].zone == zone or D.ZONES[D.STOPS[key].zone][4] then stop = key; break end
        end
    end
    return town, zone, stop
end
T.ParseName = ParseName

-- 在大陆地图上的位置 → 地区key（名字解析不出来时用）
local function ZoneAt(mapID, x, y)
    if not (C_Map and C_Map.GetMapInfoAtPosition) then return nil end
    local ok, info = pcall(C_Map.GetMapInfoAtPosition, mapID, x, y)
    if ok and info and info.name then return NS.zoneByName[info.name] end
end

local function WorldPos(mapID, x, y)
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
    local ok, _, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
    if ok and pos then return pos.x, pos.y end
end

-- 记录一个鸟点的位置信息（所有角色共享）
local function Remember(id, name, mapID, x, y)
    local town, zone, stop = ParseName(name)
    zone = zone or ZoneAt(mapID, x, y)
    local cont = (zone and D.ZONES[zone] and D.ZONES[zone][3]) or T.ContKeyOfMap(mapID) or tostring(mapID)
    local n = NS.db.taxi[id] or {}
    n.name, n.town, n.zone, n.stop, n.cont, n.map, n.x, n.y = name, town, zone, stop, cont, mapID, x, y
    n.wx, n.wy = WorldPos(mapID, x, y)
    NS.db.taxi[id] = n
    return n
end

-- 打开飞行地图：同步本角色的鸟点
function T.Sync()
    local mapID = GetTaxiMapID and GetTaxiMapID()
    if not mapID and C_Map and C_Map.GetBestMapForUnit then
        local id = C_Map.GetBestMapForUnit("player")
        while id do
            local info = C_Map.GetMapInfo(id)
            if not info then break end
            if info.mapType == 2 then mapID = id; break end
            id = info.parentMapID
        end
    end
    local char = T.Char()
    local count, contSeen = 0, {}
    if C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and mapID then
        local ok, nodes = pcall(C_TaxiMap.GetAllTaxiNodes, mapID)
        if ok and type(nodes) == "table" then
            for _, n in ipairs(nodes) do
                if n.nodeID and n.name and n.position then
                    local id = tostring(n.nodeID)
                    local rec = Remember(id, n.name, mapID, n.position.x, n.position.y)
                    contSeen[rec.cont] = true
                    -- 飞行地图上列出的都是已发现的鸟点（“不可到达”只是暂时连不通）
                    char.known[id] = true
                    count = count + 1
                end
            end
        end
    elseif NumTaxiNodes then
        -- 旧版接口兜底
        for i = 1, NumTaxiNodes() do
            local name = TaxiNodeName(i)
            local x, y = TaxiNodePosition(i)
            if name and x then
                local id = "n:" .. name
                local rec = Remember(id, name, mapID or 0, x, y)
                contSeen[rec.cont] = true
                char.known[id] = true
                count = count + 1
            end
        end
    end
    if count > 0 then
        char.synced = time()
        char.syncedConts = char.syncedConts or {}
        for c in pairs(contSeen) do char.syncedConts[c] = time() end
        NS.Print(string.format("已同步本角色的鸟点：这片大陆 %d 个。", count))
        if NS.OnTaxiChanged then NS.OnTaxiChanged() end
    end
end

-- 登录时用地图接口补全鸟点位置（不代表已解锁）
function T.Prefill()
    if not (C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap) then return end
    for key in pairs(D.CONTINENTS) do
        local mapID = T.ContMapID(key)
        if mapID then
            local ok, nodes = pcall(C_TaxiMap.GetTaxiNodesForMap, mapID)
            if ok and type(nodes) == "table" then
                for _, n in ipairs(nodes) do
                    if n.nodeID and n.name and n.position and not NS.db.taxi[tostring(n.nodeID)] then
                        Remember(tostring(n.nodeID), n.name, mapID, n.position.x, n.position.y)
                    end
                end
            end
        end
    end
end

-- 给路线规划用：当前角色已解锁、并且知道在哪个地区的鸟点
function T.ForPlanning()
    local char = T.Char()
    local list = {}
    for id in pairs(char.known) do
        local n = NS.db.taxi[id]
        if n and n.zone and D.ZONES[n.zone] then
            list[#list + 1] = { id = id, name = n.name, town = n.town, zone = n.zone, stop = n.stop, cont = n.cont,
                wx = n.wx, wy = n.wy, x = n.x, y = n.y }
        end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

-- 所有角色的鸟点概况（界面用）
function T.Summary()
    local out = {}
    for key, c in pairs(NS.db.chars) do
        local byCont = {}
        for id in pairs(c.known) do
            local n = NS.db.taxi[id]
            local cont = n and n.cont or "?"
            byCont[cont] = byCont[cont] or {}
            table.insert(byCont[cont], n and n.town or id)
        end
        for _, l in pairs(byCont) do table.sort(l) end
        out[#out + 1] = { key = key, faction = c.faction, class = c.class, synced = c.synced or 0, byCont = byCont }
    end
    table.sort(out, function(a, b) return a.key < b.key end)
    return out
end

-- 每片大陆一共见过多少个鸟点（按阵营不区分）
function T.TotalByCont()
    local t = {}
    for _, n in pairs(NS.db.taxi) do t[n.cont] = (t[n.cont] or 0) + 1 end
    return t
end

local f = CreateFrame("Frame")
f:RegisterEvent("TAXIMAP_OPENED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event)
    if not NS.db then return end
    local ok, err = pcall(event == "TAXIMAP_OPENED" and T.Sync or T.Prefill)
    if not ok then NS.Print("鸟点同步出错：" .. tostring(err)) end
    if event == "PLAYER_LOGIN" then T.Char() end
end)
