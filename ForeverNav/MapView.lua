-- 可缩放、可拖动的导航地图（独立窗口内）
-- 底图：大陆地图；放大后叠加地区高清地图。上面画路线、副本/团本、码头、鸟点、收藏、你的位置和朝向。
local _, NS = ...
local D, G = NS.Data, NS.Graph
local MV = {}
NS.MapView = MV

MV.COLORS = {
    land = { 0.95, 0.95, 0.95 }, walk = { 0.95, 0.95, 0.95 }, arrive = { 0.95, 0.95, 0.95 }, fly = { 0.3, 1, 0.4 },
    boat = { 0.3, 0.75, 1 }, zeppelin = { 1, 0.6, 0.2 }, skyboat = { 1, 0.6, 0.2 }, tram = { 1, 0.9, 0.3 },
    hearth = { 0.8, 0.45, 1 },
}
local MIN_ZOOM, MAX_ZOOM = 1, 5   -- 大陆图分辨率有限，放太大会糊
local LABEL_ZOOM = 1.4    -- 显示地区名

local function EdgeColor(e)
    if e.kind == "ride" then return MV.COLORS[e.route.type] or MV.COLORS.boat end
    return MV.COLORS[e.kind] or MV.COLORS.land
end

-- ---------------------------------------------------------------- 对象池
local function Pool(view, create)
    return { list = {}, n = 0, create = create, view = view }
end
local function Acquire(pool)
    pool.n = pool.n + 1
    local o = pool.list[pool.n]
    if not o then
        o = pool.create(pool.view)
        pool.list[pool.n] = o
    end
    o:Show()
    return o
end
local function Release(pool)
    for i = 1, pool.n do pool.list[i]:Hide() end
    pool.n = 0
end

-- ---------------------------------------------------------------- 地图底图信息
local artCache = {}
local function ArtInfo(mapID)
    if not mapID then return nil end
    local a = artCache[mapID]
    if a == nil then
        a = false
        if C_Map and C_Map.GetMapArtLayers and C_Map.GetMapArtLayerTextures then
            local ok, layers = pcall(C_Map.GetMapArtLayers, mapID)
            local L = ok and layers and layers[1]
            local ok2, tex = pcall(C_Map.GetMapArtLayerTextures, mapID, 1)
            if L and L.layerWidth and L.layerWidth > 0 and ok2 and type(tex) == "table" then
                a = { lw = L.layerWidth, lh = L.layerHeight, tw = L.tileWidth, th = L.tileHeight, tex = tex,
                    cols = math.ceil(L.layerWidth / L.tileWidth) }
            end
        end
        artCache[mapID] = a
    end
    return a or nil
end

-- ---------------------------------------------------------------- 创建
function MV.Create(parent, w, h)
    local view = CreateFrame("Frame", nil, parent)
    view:SetSize(w, h)
    if view.SetClipsChildren then view:SetClipsChildren(true) end
    view.w, view.h = w, h
    view.cont, view.zoom, view.cx, view.cy = "EK", 1, 0.5, 0.5

    local bg = view:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints()
    bg:SetColorTexture(0.04, 0.07, 0.11, 1)

    view.canvas = CreateFrame("Frame", nil, view)
    view.canvas:SetAllPoints()
    view.overlay = CreateFrame("Frame", nil, view)
    view.overlay:SetAllPoints()
    view.overlay:SetFrameLevel(view.canvas:GetFrameLevel() + 5)

    local cv = view.canvas
    view.tiles = Pool(cv, function() return cv:CreateTexture(nil, "BACKGROUND", nil, -6) end)
    view.ztiles = Pool(cv, function() return cv:CreateTexture(nil, "BACKGROUND", nil, -5) end)
    view.lines = Pool(cv, function() return cv:CreateLine(nil, "ARTWORK", nil, 2) end)
    view.dots = Pool(cv, function()
        local t = cv:CreateTexture(nil, "ARTWORK", nil, 4)
        t:SetTexture("Interface\\Buttons\\WHITE8X8")
        return t
    end)
    view.labels = Pool(cv, function() return cv:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall") end)
    view.icons = Pool(view.overlay, function(o)
        local b = CreateFrame("Button", nil, o)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetAllPoints()
        b:SetScript("OnEnter", function(self)
            if not self.info then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            for i, l in ipairs(self.info) do
                if i == 1 then GameTooltip:AddLine(l, 1, 0.82, 0) else GameTooltip:AddLine(l, 1, 1, 1, true) end
            end
            if self.node then GameTooltip:AddLine("点击：导航到这里", 0.5, 0.8, 1) end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:SetScript("OnClick", function(self)
            if self.node and view.onPick then view.onPick(self.node) end
        end)
        return b
    end)

    -- 你（箭头）
    view.player = view.overlay:CreateTexture(nil, "OVERLAY", nil, 7)
    view.player:SetTexture("Interface\\Minimap\\MinimapArrow")
    view.player:SetSize(24, 24)
    view.player:Hide()

    -- 交互：滚轮缩放（以鼠标为中心），左键拖动，右键标记目的地
    view:EnableMouse(true)
    view:EnableMouseWheel(true)
    view:SetScript("OnMouseWheel", function(self, delta)
        local mx, my = MV.CursorPos(self)
        local bx, by = MV.ToCont(self, mx, my)
        local z = math.max(MIN_ZOOM, math.min(MAX_ZOOM, self.zoom * (delta > 0 and 1.35 or 1 / 1.35)))
        if z == self.zoom then return end
        self.zoom = z
        -- 保持鼠标下的点不动
        local nx, ny = MV.ToCont(self, mx, my)
        self.cx, self.cy = self.cx + (bx - nx), self.cy + (by - ny)
        MV.Clamp(self)
        MV.Render(self)
    end)
    view:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            self.dragging = true
            self.dragX, self.dragY = MV.CursorPos(self)
            self.dragCX, self.dragCY = self.cx, self.cy
            self.moved = false
        end
    end)
    view:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            self.dragging = false
        elseif button == "RightButton" and self.onRightClick then
            local mx, my = MV.CursorPos(self)
            local x, y = MV.ToCont(self, mx, my)
            self.onRightClick(self.cont, x, y)
        end
    end)
    view:SetScript("OnUpdate", function(self, dt)
        if self.dragging then
            local mx, my = MV.CursorPos(self)
            local s = MV.PixelScale(self)
            local dx, dy = (mx - self.dragX) / (self.art.lw * s), (my - self.dragY) / (self.art.lh * s)
            if math.abs(mx - self.dragX) + math.abs(my - self.dragY) > 2 then self.moved = true end
            self.cx, self.cy = self.dragCX - dx, self.dragCY - dy
            MV.Clamp(self)
            MV.Render(self)
            return
        end
        self.acc = (self.acc or 0) + dt
        if self.acc >= 0.25 then
            self.acc = 0
            MV.UpdatePlayer(self)
        end
    end)
    view.art = { lw = 1002, lh = 668 }
    return view
end

-- ---------------------------------------------------------------- 坐标换算
function MV.CursorPos(view)
    local x, y = GetCursorPosition()
    local s = view:GetEffectiveScale()
    local left, top = view:GetLeft(), view:GetTop()
    return x / s - (left or 0), (top or 0) - y / s
end

function MV.PixelScale(view)
    local base = math.min(view.w / view.art.lw, view.h / view.art.lh)
    return base * view.zoom
end

-- 大陆坐标 → 视图像素
function MV.ToPixel(view, x, y)
    local s = MV.PixelScale(view)
    return view.w / 2 + (x - view.cx) * view.art.lw * s, view.h / 2 + (y - view.cy) * view.art.lh * s
end

-- 视图像素 → 大陆坐标
function MV.ToCont(view, px, py)
    local s = MV.PixelScale(view)
    return view.cx + (px - view.w / 2) / (view.art.lw * s), view.cy + (py - view.h / 2) / (view.art.lh * s)
end

function MV.Clamp(view)
    view.cx = math.max(0, math.min(1, view.cx))
    view.cy = math.max(0, math.min(1, view.cy))
end

function MV.SetContinent(view, cont)
    if view.cont ~= cont then
        view.cont, view.zoom, view.cx, view.cy = cont, 1, 0.5, 0.5
    end
    local a = ArtInfo(NS.Taxi.ContMapID(cont))
    view.art = a or { lw = 1002, lh = 668 }
    MV.Render(view)
end

-- 放大到能看到这些点
function MV.FitPoints(view, pts)
    local minX, maxX, minY, maxY
    local counts = {}
    for _, p in ipairs(pts) do counts[p.c] = (counts[p.c] or 0) + 1 end
    local cont, best = view.cont, -1
    for c, n in pairs(counts) do if n > best then cont, best = c, n end end
    for _, p in ipairs(pts) do
        if p.c == cont then
            minX, maxX = math.min(minX or p.x, p.x), math.max(maxX or p.x, p.x)
            minY, maxY = math.min(minY or p.y, p.y), math.max(maxY or p.y, p.y)
        end
    end
    view.cont = cont
    view.art = ArtInfo(NS.Taxi.ContMapID(cont)) or { lw = 1002, lh = 668 }
    if minX then
        view.cx, view.cy = (minX + maxX) / 2, (minY + maxY) / 2
        local base = math.min(view.w / view.art.lw, view.h / view.art.lh)
        local zx = view.w * 0.8 / math.max(0.02, (maxX - minX) * view.art.lw * base)
        local zy = view.h * 0.8 / math.max(0.02, (maxY - minY) * view.art.lh * base)
        view.zoom = math.max(MIN_ZOOM, math.min(MAX_ZOOM * 0.75, zx, zy))
    end
    MV.Render(view)
end

-- ---------------------------------------------------------------- 绘制
local function Line(view, x1, y1, x2, y2, thick, c, a)
    local l = Acquire(view.lines)
    l:SetThickness(thick)
    l:SetColorTexture(c[1], c[2], c[3], a)
    l:SetStartPoint("TOPLEFT", view.canvas, x1, -y1)
    l:SetEndPoint("TOPLEFT", view.canvas, x2, -y2)
end

local function Dot(view, x, y, size, r, g, b, a)
    local d = Acquire(view.dots)
    d:SetSize(size, size)
    d:SetVertexColor(r, g, b, a or 1)
    d:ClearAllPoints()
    d:SetPoint("CENTER", view.canvas, "TOPLEFT", x, -y)
end

local function Label(view, x, y, text, r, g, b, anchor)
    local fs = Acquire(view.labels)
    fs:SetText(text)
    fs:SetTextColor(r, g, b)
    fs:ClearAllPoints()
    fs:SetPoint(anchor or "CENTER", view.canvas, "TOPLEFT", x, -y)
end

local function Icon(view, x, y, size, setTex, node, info)
    if x < -20 or y < -20 or x > view.w + 20 or y > view.h + 20 then return end
    local b = Acquire(view.icons)
    b:SetSize(size, size)
    b:ClearAllPoints()
    b:SetPoint("CENTER", view.overlay, "TOPLEFT", x, -y)
    b.tex:SetTexCoord(0, 1, 0, 1)
    b.tex:SetVertexColor(1, 1, 1, 1)
    setTex(b.tex)
    b.node, b.info = node, info
    return b
end

local function SetAtlasOr(tex, atlas, file, r, g, b)
    local ok, res = false, nil
    if tex.SetAtlas then ok, res = pcall(tex.SetAtlas, tex, atlas) end
    local good = ok and res ~= false and (not tex.GetAtlas or tex:GetAtlas() ~= nil)
    if not good then
        tex:SetTexture(file)
        if r then tex:SetVertexColor(r, g, b) end
    end
end

local function DrawArt(view)
    local cs = MV.PixelScale(view)
    local a = view.art
    if a.tex then
        for i, fileID in ipairs(a.tex) do
            local r, c = math.floor((i - 1) / a.cols), (i - 1) % a.cols
            local px, py = MV.ToPixel(view, c * a.tw / a.lw, r * a.th / a.lh)
            local t = Acquire(view.tiles)
            t:SetTexture(fileID)
            t:SetSize(a.tw * cs, a.th * cs)
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", view.canvas, "TOPLEFT", px, -py)
            t:SetVertexColor(0.85, 0.85, 0.85)
        end
    end
    -- 注：不再叠加各地区的单独地图——它们是带边框的矩形图片，叠在大陆图上会一块块重叠
end

local function DrawZoneLabels(view)
    if view.zoom < LABEL_ZOOM then return end
    for key, z in pairs(D.ZONES) do
        if z[3] == view.cont then
            local a, b, c, d = NS.Geo.ZoneRect(key)
            if a then
                local px, py = MV.ToPixel(view, (a + b) / 2, (c + d) / 2)
                if px > 0 and py > 0 and px < view.w and py < view.h then
                    Label(view, px, py, z[1], 1, 0.9, 0.6)
                end
            end
        end
    end
end

local function NodePixel(view, node)
    local p = NS.Geo.Pos(node)
    if not p or p.c ~= view.cont then return nil end
    return MV.ToPixel(view, p.x, p.y)
end

local function DrawRoute(view)
    local plan, current = view.plan, view.current
    if not plan then return end
    for i, st in ipairs(plan.steps) do
        local done = current and i < current
        local cur = current and i == current
        for _, e in ipairs(st.edges or {}) do
            local x1, y1 = NodePixel(view, e.from)
            local x2, y2 = NodePixel(view, e.to)
            local c = EdgeColor(e)
            local a = done and 0.3 or 1
            if x1 and x2 then
                if cur then Line(view, x1, y1, x2, y2, 7, { 0, 0, 0 }, 0.6) end
                Line(view, x1, y1, x2, y2, cur and 5 or 3.5, c, a)
            elseif e.kind == "ride" and (x1 or x2) then
                -- 跨大陆：在码头处标出“坐船去对岸”
                local x, y = x1 or x2, y1 or y2
                local other = x1 and e.to or e.from
                Dot(view, x, y, 10, c[1], c[2], c[3], a)
                Label(view, x + 8, y, (x1 and "→ " or "← ") .. G.NodeName(other), c[1], c[2], c[3], "LEFT")
            end
        end
        if st.kind == "ride" or st.kind == "fly" then
            local x, y = NodePixel(view, st.board)
            if x then Dot(view, x, y, 8, 1, 1, 1, done and 0.4 or 1) end
        end
    end
    -- 起点、终点
    local first, last = plan.path[1], plan.path[#plan.path]
    if first then
        local x, y = NodePixel(view, first.from)
        if x then Dot(view, x, y, 10, 0.2, 1, 0.3, 1) end
    end
    if last then
        local x, y = NodePixel(view, last.to)
        if x then
            Dot(view, x, y, 14, 0, 0, 0, 0.8)
            Dot(view, x, y, 10, 1, 0.25, 0.25, 1)
            Label(view, x, y - 14, view.goalName or G.NodeName(last.to), 1, 0.45, 0.45, "BOTTOM")
        end
    end
end

local function DrawPOIs(view)
    local f = view.filters or {}
    -- 副本、团本
    for _, p in ipairs(D.POIS) do
        if f[p.kind] ~= false then
            local node = "D:" .. p.key
            local x, y = NodePixel(view, node)
            if not x and D.ZONES[p.zone] and D.ZONES[p.zone][3] == view.cont then
                -- 没有入口坐标：画在地区中心，标为大概位置
                x, y = NodePixel(view, "Z:" .. p.zone)
            end
            if x then
                local info = { p.zh .. "  " .. p.lv, G.ZoneName(p.zone) .. (p.new and " · 无限新副本" or "") .. (p.open and (" · " .. p.open) or "") }
                if p.hint then info[#info + 1] = p.hint end
                if not p.x then info[#info + 1] = "|cffffcc33入口坐标未收录，图标在地区中心|r"
                elseif p.approx then info[#info + 1] = "|cff999999入口坐标为近似值|r" end
                local size = view.zoom >= 2 and 20 or 16
                local b = Icon(view, x, y, size, function(t)
                    SetAtlasOr(t, p.kind == "raid" and "Raid" or "Dungeon", "Interface\\Buttons\\WHITE8X8",
                        p.kind == "raid" and 1 or 0.6, p.kind == "raid" and 0.4 or 0.8, p.kind == "raid" and 0.2 or 1)
                end, node, info)
                if b and not p.x then b.tex:SetVertexColor(1, 1, 1, 0.55) end
            end
        end
    end
    -- 码头
    if f.stop ~= false then
        for key, s in pairs(D.STOPS) do
            local x, y = NodePixel(view, "S:" .. key)
            if x then
                Icon(view, x, y, 14, function(t) t:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_02") end,
                    "S:" .. key, { s.zh, G.ZoneName(s.zone) .. " 码头/站点" })
            end
        end
    end
    -- 鸟点（显示所选角色的）
    if f.flight ~= false then
        local known = view.known or {}
        for id, n in pairs(NS.db.taxi) do
            if n.cont == view.cont and n.x then
                local x, y = MV.ToPixel(view, n.x, n.y)
                if known[id] then
                    Icon(view, x, y, 10, function(t) t:SetTexture("Interface\\Buttons\\WHITE8X8"); t:SetVertexColor(0.3, 1, 0.4) end,
                        n.zone and ("Z:" .. n.zone) or nil, { n.town or n.name, "已解锁的飞行点" })
                elseif view.showUnknownFlights then
                    Dot(view, x, y, 5, 0.6, 0.6, 0.6, 0.7)
                end
            end
        end
    end
    -- 收藏
    if f.fav ~= false then
        for key, fv in pairs(NS.db.favs) do
            if fv.c == view.cont then
                local x, y = MV.ToPixel(view, fv.x, fv.y)
                Icon(view, x, y, 16, function(t) t:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1") end,
                    "P:" .. key, { fv.name, "我的收藏" })
            end
        end
    end
end

function MV.UpdatePlayer(view)
    local p = NS.Geo.PlayerPos()
    if not p or p.c ~= view.cont then view.player:Hide(); return end
    local x, y = MV.ToPixel(view, p.x, p.y)
    view.player:ClearAllPoints()
    view.player:SetPoint("CENTER", view.overlay, "TOPLEFT", x, -y)
    local facing = GetPlayerFacing and GetPlayerFacing()
    if type(facing) == "number" and not (issecretvalue and issecretvalue(facing)) then view.player:SetRotation(facing) end
    view.player:Show()
end

function MV.Render(view)
    Release(view.tiles); Release(view.ztiles); Release(view.lines); Release(view.dots)
    Release(view.labels); Release(view.icons)
    DrawArt(view)
    DrawZoneLabels(view)
    DrawRoute(view)
    DrawPOIs(view)
    MV.UpdatePlayer(view)
    if view.onRender then view.onRender(view) end
end

-- 设置要画的路线
function MV.SetRoute(view, plan, current, goalName, fit)
    view.plan, view.current, view.goalName = plan, current, goalName
    if fit and plan then
        local pts = {}
        for _, e in ipairs(plan.path) do
            for _, n in ipairs({ e.from, e.to }) do
                local p = NS.Geo.Pos(n)
                if p then pts[#pts + 1] = p end
            end
        end
        if #pts > 0 then return MV.FitPoints(view, pts) end
    end
    MV.Render(view)
end

function MV.CenterOnPlayer(view)
    local p = NS.Geo.PlayerPos()
    if not p then return false end
    view.cont = p.c
    view.art = ArtInfo(NS.Taxi.ContMapID(p.c)) or { lw = 1002, lh = 668 }
    view.cx, view.cy = p.x, p.y
    view.zoom = math.max(view.zoom, 3)
    MV.Render(view)
    return true
end
