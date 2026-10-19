-- Stitched client map art, with capital maps above Wayfinder's minimap terrain.
-- Coordinate/host-layout routines adapted from OpenMap Map/Stitch.lua.
-- Copyright (c) 2026 OpenMap contributors; MIT, see Vendor/OpenMap/LICENSE.txt.
local _, ns = ...
local S = { WORLD = 947 }
ns.ContinuousEngine.MapStitch = S
local ROOT = "Interface\\AddOns\\" .. ns.name .. "\\Media\\MapMasks\\"
local CONTINENTS = { 1414, 1415 }
local CITIES = ns.ContinuousEngine.MapCityZones
local CUT = { [1454] = true, [1456] = true, [1458] = true }
local TERRITORY = {}
for id = 1411, 1452 do TERRITORY[id] = id ~= 1414 and id ~= 1415 end
for _, id in ipairs({ 2482, 2521, 2548, 2652 }) do TERRITORY[id] = true end

local rects, maps, built, root, player, W, H = {}, {}, false, nil, nil, 1002, 668
local shown, viewU, viewV, halfU, halfV, zoom = false, 0.5, 0.5, 0.5, 0.5, 1
local artLevel
local UNDERCITY, UNDERCITY_SURFACE = 1458, 1420
local undergroundContext, showSurface = false, false
-- Begin the blend only after reaching the old detail view's closer framing.
local TERRAIN_FROM, TERRAIN_FULL = 2500, 1400
local function Smooth(a, b, value)
	local t = math.max(0, math.min(1, (value - a) / (b - a)))
	return t * t * (3 - 2 * t)
end
function S.Rect(id)
	if id == S.WORLD then return 0, 1, 0, 1 end
	if not id or not C_Map.GetMapRectOnMap then return end
	if rects[id] == nil then
		local ok, l, r, t, b = pcall(C_Map.GetMapRectOnMap, id, S.WORLD)
		rects[id] = ok and type(l) == "number" and type(r) == "number"
			and type(t) == "number" and type(b) == "number" and r > l and b > t
			and { l, r, t, b } or false
	end
	local r = rects[id]
	if r then return unpack(r) end
end
function S.Size() return W, H end
function S.ArtSize(id)
	local layers = C_Map.GetMapArtLayers(id)
	local layer = layers and layers[1]
	if layer then return layer.layerWidth, layer.layerHeight, layer end
end
function S.ChainAt(u, v)
	local chain, id, x, y = { S.WORLD }, S.WORLD, u, v
	if not u or not v or not C_Map.GetMapInfoAtPosition then return chain end
	for _ = 1, 6 do
		local info = C_Map.GetMapInfoAtPosition(id, x, y)
		if not info or info.mapID == id or (info.mapType ~= Enum.UIMapType.Continent
			and info.mapType ~= Enum.UIMapType.Zone) then break end
		local l, r, t, b = C_Map.GetMapRectOnMap(info.mapID, id)
		if not l or r <= l or b <= t then break end
		id, x, y = info.mapID, (x - l) / (r - l), (y - t) / (b - t)
		chain[#chain + 1] = id
	end
	-- Some clients report the outdoor zone even inside a capital's footprint.
	for city, parent in pairs(CITIES) do
		local l, r, t, b = S.Rect(city)
		if l and u >= l and u <= r and v >= t and v <= b then
			local last = chain[#chain]
			if last == parent then chain[#chain + 1] = city end
		end
	end
	if undergroundContext and showSurface and chain[#chain] == UNDERCITY then
		table.remove(chain)
		if S.Rect(UNDERCITY_SURFACE) and chain[#chain] ~= UNDERCITY_SURFACE then
			chain[#chain + 1] = UNDERCITY_SURFACE
		end
	end
	return chain
end
function S.InCity(u, v)
	local chain = S.ChainAt(u, v)
	return ns.IsCityMap(chain[#chain])
end
function S.ContinentAt(u, v)
	for _, id in ipairs(CONTINENTS) do
		local l, r, t, b = S.Rect(id)
		if l and u >= l and u <= r and v >= t and v <= b then return id end
	end
end
function S.FromYards(cont, wx, wy)
	for _, id in ipairs(CONTINENTS) do
		local rect = ns.GetMapRect(id)
		local l, r, t, b = S.Rect(id)
		if rect and rect.cont == cont and l then
			local x, y = ns.WorldToMapRect(rect, wx, wy)
			return l + x * (r - l), t + y * (b - t)
		end
	end
end

local function AddMap(id)
	if maps[id] then return end
	local l, r, t, b = S.Rect(id)
	local aw, ah = S.ArtSize(id)
	local info = C_Map.GetMapInfo(id)
	if not l or not aw or not info then return end
	if id ~= S.WORLD and info.mapType ~= Enum.UIMapType.Continent and info.mapType ~= Enum.UIMapType.Zone then return end
	maps[id] = { id = id, l = l, r = r, t = t, b = b,
		city = ns.IsCityMap(id), continent = info.mapType == Enum.UIMapType.Continent }
end
local function Texture(rec, file, x, y, width, height, u, v, sub, reuse)
	local tex = reuse or rec.frame:CreateTexture(nil, "ARTWORK", nil, sub or 0)
	tex:SetDrawLayer("ARTWORK", sub or 0)
	tex:SetTexture(file, "CLAMP", "CLAMP", "TRILINEAR")
	tex:SetTexCoord(0, u, 0, v)
	tex:SetPoint("TOPLEFT", rec.frame, "TOPLEFT", x * rec.sx, -y * rec.sy)
	tex:SetSize(width * rec.sx, height * rec.sy)
	if rec.mask and not reuse then tex:AddMaskTexture(rec.mask) end
	tex:Show()
	return tex
end
local function Overlays(rec)
	rec.overlayPool = rec.overlayPool or {}
	for _, tex in ipairs(rec.overlays or {}) do
		tex:Hide(); tex:SetTexture(nil)
		rec.overlayPool[#rec.overlayPool + 1] = tex
	end
	rec.overlays = {}
	local info = C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures(rec.id)
	for _, overlay in ipairs(info or {}) do
		ns.LayoutExplorationOverlay(overlay, rec.layer.tileWidth, rec.layer.tileHeight,
			function(file, x, y, w, h, u, v, level)
				rec.overlays[#rec.overlays + 1] = Texture(rec, file, x, y, w, h, u, v, level, table.remove(rec.overlayPool))
			end)
	end
end
local function BuildMap(rec)
	local aw, ah, layer = S.ArtSize(rec.id)
	local files = C_Map.GetMapArtLayerTextures(rec.id, 1)
	if not files or not layer then return end
	local frame = CreateFrame("Frame", nil, root)
	rec.frame, rec.textures, rec.layer = frame, {}, layer
	frame:SetFrameLevel(artLevel + (rec.city and 65 or rec.continent and 2 or rec.id == S.WORLD and 1 or 5))
	frame:SetPoint("TOPLEFT", root, "TOPLEFT", rec.l * W, -rec.t * H)
	frame:SetSize((rec.r - rec.l) * W, (rec.b - rec.t) * H)
	rec.sx, rec.sy = frame:GetWidth() / aw, frame:GetHeight() / ah
	local maskFile = rec.id ~= UNDERCITY and (rec.city and (CUT[rec.id] and "MapCityMask\\" .. rec.id or "MapFeatherRound")
		or TERRITORY[rec.id] and "MapTerritory\\" .. rec.id
		or rec.id ~= S.WORLD and "MapFeatherRound")
	if maskFile then
		rec.mask = frame:CreateMaskTexture()
		rec.mask:SetTexture(ROOT .. maskFile, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		rec.mask:SetAllPoints(frame)
	end
	local tw, th = layer.tileWidth, layer.tileHeight
	local cols = math.ceil(aw / tw)
	for index, file in ipairs(files) do
		local x, y = (index - 1) % cols * tw, math.floor((index - 1) / cols) * th
		local w, h = math.min(tw, aw - x), math.min(th, ah - y)
		if w > 0 and h > 0 then
			rec.textures[#rec.textures + 1] = Texture(rec, file, x, y, w, h, w / tw, h / th)
		end
	end
	Overlays(rec)
end

function S.VisibleMaps()
	local result = {}
	for id, rec in pairs(maps) do
		if rec.visible and not rec.continent and id ~= S.WORLD then result[#result + 1] = id end
	end
	return result
end
function S.GetUndergroundView()
	if undergroundContext then return UNDERCITY, showSurface end
end
local function UpdateUndergroundContext()
	local rec = maps[UNDERCITY]
	local inside = rec and shown and viewU >= rec.l and viewU <= rec.r
		and viewV >= rec.t and viewV <= rec.b
		and zoom >= 0.7 * math.min(1 / (rec.r-rec.l), 1 / (rec.b-rec.t))
	if not inside then showSurface = false end
	undergroundContext = inside and true or false
	ns.ContinuousMap:UpdateLayerButton(S.GetUndergroundView())
end
function S.ResetUndergroundView()
	undergroundContext, showSurface = false, false
	ns.ContinuousMap:UpdateLayerButton()
end
function S.ToggleUndergroundView()
	if not undergroundContext then return end
	showSurface = not showSurface
	local controller = ns.ContinuousEngine:GetModule("worldmap")
	controller.FollowLayerMap(showSurface and UNDERCITY_SURFACE or UNDERCITY)
	S.SetView(viewU, viewV, halfU, halfV, zoom, zoom)
	ns:Fire("MAP_LAYER_CHANGED")
end
function S.Recull()
	if not built then return end
	for id, rec in pairs(maps) do
		local visible = shown and rec.r >= viewU - halfU and rec.l <= viewU + halfU
			and rec.b >= viewV - halfV and rec.t <= viewV + halfV
		local fit = math.min(1 / (rec.r - rec.l), 1 / (rec.b - rec.t))
		local alpha = id == S.WORLD and 1 or rec.city and Smooth(0.2 * fit, 0.4 * fit, zoom)
			or rec.continent and Smooth(1.1, 2.2, zoom) or Smooth(0.35 * fit, 0.8 * fit, zoom)
		if id == UNDERCITY and undergroundContext then
			visible = visible and not showSurface
			alpha = 1
		end
		rec.visible = visible and alpha > 0.001
		if rec.visible and not rec.frame then BuildMap(rec) end
		if rec.frame then rec.frame:SetShown(rec.visible); rec.frame:SetAlpha(alpha) end
	end
end
function S.Build(parent, level, range)
	if built then return end
	W, H = S.ArtSize(S.WORLD)
	if not W or not H then W, H = 1002, 668 end
	artLevel, S.artTop, S.terrainLevel = level, level + range, level + 50
	root = CreateFrame("Frame", nil, parent)
	root:SetSize(W, H)
	root:SetFrameLevel(level)
	S.root = root
	AddMap(S.WORLD)
	for _, info in ipairs(C_Map.GetMapChildrenInfo(S.WORLD, nil, true) or {}) do AddMap(info.mapID) end
	for _, id in ipairs(CONTINENTS) do AddMap(id) end
	for id in pairs(CITIES) do AddMap(id) end
	built = true
	S.Recull()
end
function S.IsBuilt() return built end
function S.Layout(id)
	local l, r, t = S.Rect(id)
	local aw = S.ArtSize(id)
	if not root or not l or not aw then return false end
	root:SetScale(aw / ((r - l) * W))
	root:ClearAllPoints()
	root:SetPoint("TOPLEFT", root:GetParent(), "TOPLEFT", -l * W, t * H)
	return true
end
function S.SetShown(on)
	shown = on and true or false
	if root then root:SetShown(shown) end
	if not shown then S.ResetUndergroundView() end
	if not shown and ns.DetailView:IsFollowingMap() then ns.DetailView:Exit(true) end
end
function S.SetZoom() end -- SetView supplies the matching view and zoom together.
function S.SetView(u, v, hu, hv, _, stepZoom)
	viewU, viewV, halfU, halfV, zoom = u, v, hu, hv, stepZoom
	UpdateUndergroundContext()
	S.Recull()
	-- Underground artwork replaces the surface tiles, but keeps the same
	-- marker layer. Exiting DetailView here also removed all persistent pins.
	local pinsOnly = undergroundContext and not showSurface
	local id = S.ContinentAt(u, v)
	local rect = id and ns.GetMapRect(id)
	local l, r, t, b
	if id then l, r, t, b = S.Rect(id) end
	if shown and rect and l and ns.TileData[rect.cont] and ns:GetSetting("detailEnabled") then
		local x, y = (u - l) / (r - l), (v - t) / (b - t)
		local span = hu * 2 / (r - l) * rect.width
		local height = hv * 2 / (b - t) * rect.height
		local alpha = pinsOnly and 1 or 1 - Smooth(TERRAIN_FULL, TERRAIN_FROM, span)
		if alpha > 0 then
			local fl = WorldMapFrame:GetPinFrameLevelsManager()
			local questLevel = math.min(8000, math.max(S.artTop + 5, (fl.maxLevel or 3000) + 10))
			ns.DetailView:FollowMap(rect.cont, rect.top - y * rect.height, rect.left - x * rect.width,
				WorldMapFrame.ScrollContainer:GetWidth() / span, alpha, S.terrainLevel, questLevel,
				WorldMapFrame.ScrollContainer:GetHeight() / height, pinsOnly)
			return
		end
	end
	if ns.DetailView:IsFollowingMap() then ns.DetailView:Exit(true) end
end
function S.RefreshExplored()
	for _, rec in pairs(maps) do if rec.frame then Overlays(rec) end end
end
function S.ApplyGrade() S.RefreshExplored() end
function S.SetPlayer(u, v, facing)
	if not u or not shown then if player then player:Hide() end; return end
	if not player then
		player = CreateFrame("Frame", nil, root)
		player.texture = player:CreateTexture(nil, "OVERLAY")
		player.texture:SetAllPoints()
		player.texture:SetTexture(ns.Categories:GetMediaPath("PlayerArrow"))
	end
	local sc = WorldMapFrame.ScrollContainer
	local effective = root:GetEffectiveScale() / sc:GetEffectiveScale()
	player:SetSize(24 / effective, 24 / effective)
	player:ClearAllPoints()
	player:SetPoint("CENTER", root, "TOPLEFT", u * W, -v * H)
	player.texture:SetRotation(facing or 0)
	player:Show()
end
function S.RaiseArrow(level) if player then player:SetFrameLevel(level) end end
