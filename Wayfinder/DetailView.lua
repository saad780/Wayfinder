-- The detail view: zooming the world map past its limit continues into the
-- minimap's own terrain, drawn wherever you have explored, with every recorded
-- location on top.
--
-- It is a separate frame laid over the map canvas rather than extra zoom levels on
-- Blizzard's canvas, so the world map's own state is never modified.
--
-- Everything is positioned on the "plane" (yards; x east, y south). A single scaled
-- frame holds the terrain and map art, so panning or zooming is one SetPoint call.
local _, ns = ...

local DetailView = ns:NewModule("DetailView")

local floor, ceil, min, max, abs = math.floor, math.ceil, math.min, math.max, math.abs
local TILE, CELLS, CELL = ns.TILE, ns.CELLS, ns.CELL
local HasBit -- set in OnInitialize (Exploration loads first)

local ZOOM_STEP = 1.3
local MIN_SPAN = 140      -- yards across the view at the closest zoom
local MAX_SPAN = 6000     -- never show more than this many yards across
local PLANE_LIMIT = 32 * TILE
local PIN_SIZE = 20
local UNDERLAY_SHADE = 0.85

local view, plane, pinLayer, arrowFrame, hud
local active = false
local cont
local cx, cy, scale = 0, 0, 1       -- current centre (plane yards) and UI units per yard
local tcx, tcy, tscale = 0, 0, 1    -- animation targets
local exitScale, maxScale = 1, 10
local originMapID, underlayMapID
local transformDirty, pinsDirty = true, true
local dragging, dragMoved, dragX, dragY = false, false, 0, 0

---------------------------------------------------------------------------
-- Small pools
---------------------------------------------------------------------------
local freeTextures = {}

local function AcquireTexture(layer, subLevel)
	local tex = table.remove(freeTextures)
	if not tex then
		tex = plane:CreateTexture(nil, layer, nil, subLevel)
	else
		tex:SetDrawLayer(layer, subLevel)
	end
	tex:ClearAllPoints()
	tex:SetVertexColor(1, 1, 1)
	tex:SetDesaturation(0)
	tex:SetAlpha(1)
	tex:Show()
	return tex
end

local function ReleaseTextures(list)
	for i = #list, 1, -1 do
		local tex = list[i]
		tex:Hide()
		tex:SetTexture(nil)
		freeTextures[#freeTextures + 1] = tex
		list[i] = nil
	end
end

---------------------------------------------------------------------------
-- Coordinates
---------------------------------------------------------------------------
local function ViewSize()
	local w, h = view:GetSize()
	return max(w, 1), max(h, 1)
end

-- Visible plane rectangle: left, right, top, bottom.
local function VisibleRect(margin)
	local w, h = ViewSize()
	local hw, hh = w / (2 * scale), h / (2 * scale)
	margin = margin or 0
	return cx - hw * (1 + margin), cx + hw * (1 + margin), cy - hh * (1 + margin), cy + hh * (1 + margin)
end

local function CursorInView()
	local x, y = GetCursorPosition()
	local s = view:GetEffectiveScale()
	return x / s - view:GetLeft(), view:GetTop() - y / s
end

local function ViewToPlane(vx, vy, centerX, centerY, atScale)
	local w, h = ViewSize()
	return centerX + (vx - w / 2) / atScale, centerY + (vy - h / 2) / atScale
end

local function PlaneToView(px, py)
	local w, h = ViewSize()
	return (px - cx) * scale + w / 2, (py - cy) * scale + h / 2
end

---------------------------------------------------------------------------
-- Terrain
---------------------------------------------------------------------------
local activeTiles = {} -- tileKey -> list of textures
local tileRange       -- last visible tile range, to skip redundant updates
DetailView.activeTiles = activeTiles -- exposed for tests

local FULL = {}
for r = 1, CELLS do FULL[r] = 2 ^ CELLS - 1 end

-- Splits a tile's explored cells into as few rectangles as possible.
local function Rectangles(rows)
	local rects, open = {}, {}
	for r = 0, CELLS - 1 do
		local mask = rows[r + 1] or 0
		local nextOpen = {}
		local i = 0
		while i < CELLS do
			if HasBit(mask, i) then
				local j = i + 1
				while j < CELLS and HasBit(mask, j) do
					j = j + 1
				end
				local key = i * 64 + j
				local rect = open[key]
				if rect then
					rect[4] = r + 1
				else
					rect = { i, j, r, r + 1 } -- x0, x1, y0, y1 in cells
					rects[#rects + 1] = rect
				end
				nextOpen[key] = rect
				i = j
			else
				i = i + 1
			end
		end
		open = nextOpen
	end
	return rects
end
ns.ExploredRectangles = Rectangles -- exposed for tests

---------------------------------------------------------------------------
-- Fog over unexplored terrain (Darkened mode)
--
-- Marching squares: the fog is laid on a grid offset by half a cell, so each piece's
-- four corners sit on four exploration cells. Which corners are explored picks one of
-- 16 soft-edged pieces (Media/Fog/Fog<case>.tga, see tools/make_fog.py); every point
-- is covered by exactly one piece, so the fog never doubles up, and edges come out as
-- smooth, rounded fades instead of the cell grid's right angles.
---------------------------------------------------------------------------
local FOG_PATH = "Interface\\AddOns\\Wayfinder\\Media\\Fog\\Fog"
local FOG_R, FOG_G, FOG_B = 0.10, 0.11, 0.14
DetailView.FUZZY_MIN_CELL_PIXELS = 6 -- below this, soft edges are too small to see
local fuzzyBuilt -- whether the tiles on screen were built with soft fog edges

--[[ Fog pieces for one tile, in cell units from the tile's top-left corner.
explored(i, j) answers for cells -1..16 (neighbouring tiles included); missing.east,
.west, .north, .south say which neighbours have no terrain, so no fog is drawn past
the coast. Returns a list of { case, x0, x1, y0, y1, u0, u1, v0, v1 }; case 0 is
solid fog (merged into rectangles where possible). ]]
local function FogPieces(explored, missing)
	local pieces = {}
	local function E(i, j)
		return explored(i, j) and 1 or 0
	end
	local function Add(i, j, case)
		-- dual cell (i, j) spans from the centre of cell (i, j) to the centre of (i+1, j+1)
		local x0, x1, y0, y1 = i + 0.5, i + 1.5, j + 0.5, j + 1.5
		local cx0 = (i == -1) and 0 or x0
		local cx1 = (i == CELLS - 1 and missing.east) and CELLS or x1
		local cy0 = (j == -1) and 0 or y0
		local cy1 = (j == CELLS - 1 and missing.south) and CELLS or y1
		pieces[#pieces + 1] = { case, cx0, cx1, cy0, cy1, cx0 - x0, cx1 - x0, cy0 - y0, cy1 - y0 }
	end

	-- The tile's own 16x16 dual cells; solid ones are merged into rectangles.
	local solid = {}
	for j = 0, CELLS - 1 do
		local mask = 0
		for i = 0, CELLS - 1 do
			local case = E(i, j) + 2 * E(i + 1, j) + 4 * E(i, j + 1) + 8 * E(i + 1, j + 1)
			if case == 0 then
				mask = mask + 2 ^ i
			elseif case ~= 15 then
				Add(i, j, case)
			end
		end
		solid[j + 1] = mask
	end
	for _, rect in ipairs(Rectangles(solid)) do
		local x0, x1, y0, y1 = rect[1] + 0.5, rect[2] + 0.5, rect[3] + 0.5, rect[4] + 0.5
		if rect[2] == CELLS and missing.east then x1 = CELLS end
		if rect[4] == CELLS and missing.south then y1 = CELLS end
		pieces[#pieces + 1] = { 0, x0, x1, y0, y1, 0, 1, 0, 1 }
	end

	-- Along a coast the neighbour builds nothing, so this tile covers the half cell
	-- between its edge and its first cell centres.
	local function Edge(i, j)
		local case = E(i, j) + 2 * E(i + 1, j) + 4 * E(i, j + 1) + 8 * E(i + 1, j + 1)
		if case ~= 15 then
			Add(i, j, case)
		end
	end
	if missing.west then
		for j = (missing.north and -1 or 0), CELLS - 1 do
			Edge(-1, j)
		end
	end
	if missing.north then
		for i = 0, CELLS - 1 do
			Edge(i, -1)
		end
	end
	return pieces
end
ns.FogPieces = FogPieces -- exposed for tests

local function TileRows(col, row)
	if ns:GetSetting("unexploredTerrain") == ns.UNEXPLORED_SHOWN then
		return FULL
	end
	return ns.Exploration:GetTileRows(cont, col * 100 + row)
end

local function HasTile(col, row)
	return ns.TileData[cont] and ns.TileData[cont][col * 100 + row] ~= nil
end

-- explored(i, j) for cells of tile (col, row) and the cells just beyond its edges.
local function ExploredLookup(col, row)
	local rowsOf = {}
	local function Rows(dc, dr)
		local key = (dc + 1) * 3 + (dr + 1)
		local rows = rowsOf[key]
		if rows == nil then
			rows = TileRows(col + dc, row + dr) or false
			rowsOf[key] = rows
		end
		return rows
	end
	return function(i, j)
		local dc, dr = 0, 0
		if i < 0 then dc, i = -1, i + CELLS elseif i >= CELLS then dc, i = 1, i - CELLS end
		if j < 0 then dr, j = -1, j + CELLS elseif j >= CELLS then dr, j = 1, j - CELLS end
		local rows = Rows(dc, dr)
		return rows and HasBit(rows[j + 1] or 0, i) or false
	end
end

local function AddFogTexture(list, ox, oy, piece, alpha)
	local case, x0, x1, y0, y1 = piece[1], piece[2], piece[3], piece[4], piece[5]
	local tex = AcquireTexture("ARTWORK", 2)
	if case == 0 then
		tex:SetColorTexture(FOG_R, FOG_G, FOG_B, 1)
	else
		tex:SetTexture(FOG_PATH .. case, "CLAMP", "CLAMP", "LINEAR")
		tex:SetTexCoord(piece[6], piece[7], piece[8], piece[9])
		tex:SetVertexColor(FOG_R, FOG_G, FOG_B)
	end
	tex:SetAlpha(alpha)
	tex:SetSize((x1 - x0) * CELL, (y1 - y0) * CELL)
	tex:SetPoint("TOPLEFT", plane, "TOPLEFT", ox + x0 * CELL, -(oy + y0 * CELL))
	list[#list + 1] = tex
end

local function BuildTile(col, row)
	local key = col * 100 + row
	local list = activeTiles[key] or {}
	activeTiles[key] = list
	ReleaseTextures(list)
	local fileID = ns.TileData[cont] and ns.TileData[cont][key]
	if not fileID then
		return
	end
	local mode = ns:GetSetting("unexploredTerrain")
	local rows = TileRows(col, row)
	local ox, oy = ns.TileOrigin(col, row)

	if mode ~= ns.UNEXPLORED_HIDDEN then
		-- Shown and Darkened: the whole tile at full brightness ...
		local tex = AcquireTexture("ARTWORK", 0)
		tex:SetTexture(fileID, "CLAMP", "CLAMP", "LINEAR")
		tex:SetTexCoord(0, 1, 0, 1)
		tex:SetSize(TILE, TILE)
		tex:SetPoint("TOPLEFT", plane, "TOPLEFT", ox, -oy)
		list[#list + 1] = tex
		if mode ~= ns.UNEXPLORED_DARKENED then
			return
		end
		-- ... with fog over what you have not explored.
		local alpha = 1 - (ns:GetSetting("unexploredBrightness") or 0.4)
		if fuzzyBuilt then
			local missing = {
				west = not HasTile(col - 1, row), east = not HasTile(col + 1, row),
				north = not HasTile(col, row - 1), south = not HasTile(col, row + 1),
			}
			for _, piece in ipairs(FogPieces(ExploredLookup(col, row), missing)) do
				AddFogTexture(list, ox, oy, piece, alpha)
			end
		else
			-- Zoomed far out: plain fog over each unexplored cell.
			local unexplored = {}
			for r = 1, CELLS do
				unexplored[r] = 2 ^ CELLS - 1 - (rows and rows[r] or 0)
			end
			for _, rect in ipairs(Rectangles(unexplored)) do
				AddFogTexture(list, ox, oy, { 0, rect[1], rect[2], rect[3], rect[4] }, alpha)
			end
		end
		return
	end

	-- Hidden: only the explored cells, over the zone's map art.
	if not rows then
		return
	end
	for _, rect in ipairs(Rectangles(rows)) do
		local x0, x1, y0, y1 = rect[1], rect[2], rect[3], rect[4]
		local tex = AcquireTexture("ARTWORK", 1)
		tex:SetTexture(fileID, "CLAMP", "CLAMP", "LINEAR")
		tex:SetTexCoord(x0 / CELLS, x1 / CELLS, y0 / CELLS, y1 / CELLS)
		tex:SetSize((x1 - x0) * CELL, (y1 - y0) * CELL)
		tex:SetPoint("TOPLEFT", plane, "TOPLEFT", ox + x0 * CELL, -(oy + y0 * CELL))
		list[#list + 1] = tex
	end
end

local function ReleaseAllTiles()
	for key, list in pairs(activeTiles) do
		ReleaseTextures(list)
		activeTiles[key] = nil
	end
	tileRange = nil
end

local function UpdateTiles(force)
	local l, r, t, b = VisibleRect(0.15)
	local c0, c1 = floor(l / TILE + 32), floor(r / TILE + 32)
	local r0, r1 = floor(t / TILE + 32), floor(b / TILE + 32)
	local range = c0 .. ":" .. c1 .. ":" .. r0 .. ":" .. r1
	if not force and range == tileRange then
		return
	end
	tileRange = range
	for key, list in pairs(activeTiles) do
		local col, row = ns.SplitTileKey(key)
		if col < c0 or col > c1 or row < r0 or row > r1 then
			ReleaseTextures(list)
			activeTiles[key] = nil
		end
	end
	for col = c0, c1 do
		for row = r0, r1 do
			if force or not activeTiles[col * 100 + row] then
				BuildTile(col, row)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Map art under the terrain (the zone's world map, as Blizzard draws it)
---------------------------------------------------------------------------
local underlay = {}

local function NextPow2(n)
	local p = 16
	while p < n do
		p = p * 2
	end
	return p
end

local function SetUnderlay(mapID)
	if mapID == underlayMapID then
		return
	end
	ReleaseTextures(underlay)
	underlayMapID = mapID
	local rect = mapID and ns.GetMapRect(mapID)
	if not rect or rect.cont ~= cont then
		return
	end
	local layers = C_Map.GetMapArtLayers(mapID)
	local layer = layers and layers[1]
	local textures = C_Map.GetMapArtLayerTextures(mapID, 1)
	if not layer or not textures then
		return
	end
	local tw, th = layer.tileWidth, layer.tileHeight
	local kx, ky = rect.width / layer.layerWidth, rect.height / layer.layerHeight
	local left, top = -rect.left, -rect.top

	local cols = ceil(layer.layerWidth / tw)
	local rows = ceil(layer.layerHeight / th)
	for row = 1, rows do
		for col = 1, cols do
			local fileID = textures[(row - 1) * cols + col]
			if fileID then
				local pw = min(tw, layer.layerWidth - (col - 1) * tw)
				local ph = min(th, layer.layerHeight - (row - 1) * th)
				local tex = AcquireTexture("BACKGROUND", 0)
				tex:SetTexture(fileID, nil, nil, "TRILINEAR")
				tex:SetTexCoord(0, pw / tw, 0, ph / th)
				tex:SetSize(pw * kx, ph * ky)
				tex:SetPoint("TOPLEFT", plane, "TOPLEFT", left + (col - 1) * tw * kx, -(top + (row - 1) * th * ky))
				tex:SetVertexColor(UNDERLAY_SHADE, UNDERLAY_SHADE, UNDERLAY_SHADE)
				underlay[#underlay + 1] = tex
			end
		end
	end

	-- Discovered-area overlays. The tiling below is adapted from Blizzard's
	-- MapExplorationPinMixin:RefreshOverlays (Blizzard_SharedMapDataProviders).
	local overlays = C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures(mapID)
	for _, info in ipairs(overlays or {}) do
		if not info.isShownByMouseOver then
			local wide = ceil(info.textureWidth / tw)
			local tall = ceil(info.textureHeight / th)
			local subLevel = info.isDrawOnTopLayer and 2 or 1
			for j = 1, tall do
				local ph, fh = th, th
				if j == tall then
					ph = info.textureHeight % th
					if ph == 0 then ph = th end
					fh = NextPow2(ph)
				end
				for k = 1, wide do
					local pw, fw = tw, tw
					if k == wide then
						pw = info.textureWidth % tw
						if pw == 0 then pw = tw end
						fw = NextPow2(pw)
					end
					local fileID = info.fileDataIDs[(j - 1) * wide + k]
					if fileID then
						local tex = AcquireTexture("BACKGROUND", subLevel)
						tex:SetTexture(fileID, nil, nil, "TRILINEAR")
						tex:SetTexCoord(0, pw / fw, 0, ph / fh)
						tex:SetSize(pw * kx, ph * ky)
						tex:SetPoint("TOPLEFT", plane, "TOPLEFT",
							left + (info.offsetX + tw * (k - 1)) * kx,
							-(top + (info.offsetY + th * (j - 1)) * ky))
						tex:SetVertexColor(UNDERLAY_SHADE, UNDERLAY_SHADE, UNDERLAY_SHADE)
						underlay[#underlay + 1] = tex
					end
				end
			end
		end
	end
	pinsDirty = true -- live quest markers belong to the underlay's zone
end

-- The zone-level map at a plane position, or nil over open sea.
local function ZoneAt(px, py)
	local wx, wy = ns.PlaneToWorld(px, py)
	local ok, mapID = pcall(C_Map.GetMapPosFromWorldPos, cont, CreateVector2D(wx, wy))
	if not ok or not mapID then
		return nil
	end
	local info = C_Map.GetMapInfo(mapID)
	local guard = 0
	while info and info.mapType > Enum.UIMapType.Zone and info.parentMapID and info.parentMapID ~= 0 and guard < 8 do
		mapID = info.parentMapID
		info = C_Map.GetMapInfo(mapID)
		guard = guard + 1
	end
	if info and info.mapType == Enum.UIMapType.Zone then
		return mapID
	end
end

---------------------------------------------------------------------------
-- Icons
---------------------------------------------------------------------------
local freePins, activePins = {}, {}

local function PinOnEnter(pin)
	if pin.quest then
		GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
		GameTooltip:SetText(pin.quest.questName or QUESTS_LABEL or "Quest", 1, 0.82, 0)
		GameTooltip:AddLine("Available quest", 0.8, 0.8, 0.8)
		GameTooltip:Show()
	else
		ns.Tooltip:Show(pin, pin.rec, pin.catID)
	end
end

local function PinOnLeave()
	GameTooltip:Hide()
end

local function PinOnMouseDown(_, button)
	if button == "LeftButton" then
		DetailView:BeginDrag()
	end
end

local function PinOnMouseUp(pin, button)
	if button == "LeftButton" then
		local moved = DetailView:EndDrag()
		if not moved and IsShiftKeyDown() and pin.rec and pin:IsMouseOver() then
			if pin.rec.waypoint then
				ns.Navigation:ClearWaypoint()
			else
				ns:RemoveLocation(pin.rec)
			end
		end
	elseif button == "MiddleButton" and pin:IsMouseOver() then
		if pin.rec then
			ns.Navigation:ToggleWaypointAt(pin.rec, pin.catID)
		elseif pin.quest then
			local wx, wy = ns.PlaneToWorld(pin.px, pin.py)
			ns.Navigation:SetWaypoint(cont, wx, wy, pin.quest.questName, underlayMapID)
		end
	end
end

local function AcquirePin()
	local pin = table.remove(freePins)
	if not pin then
		pin = CreateFrame("Frame", nil, pinLayer)
		pin:EnableMouse(true)
		pin:SetPassThroughButtons("RightButton")
		pin.icon = pin:CreateTexture(nil, "ARTWORK")
		pin.icon:SetAllPoints()
		pin.highlight = pin:CreateTexture(nil, "HIGHLIGHT")
		pin.highlight:SetAllPoints()
		pin.highlight:SetBlendMode("ADD")
		pin.highlight:SetAlpha(0.45)
		pin:SetScript("OnEnter", PinOnEnter)
		pin:SetScript("OnLeave", PinOnLeave)
		pin:SetScript("OnMouseDown", PinOnMouseDown)
		pin:SetScript("OnMouseUp", PinOnMouseUp)
	end
	pin.rec, pin.catID, pin.quest = nil, nil, nil
	pin:SetFrameLevel(pinLayer:GetFrameLevel() + 1)
	pin:Show()
	activePins[#activePins + 1] = pin
	return pin
end

local function ReleasePins()
	for i = #activePins, 1, -1 do
		local pin = activePins[i]
		pin:Hide()
		pin:ClearAllPoints()
		pin.rec, pin.quest = nil, nil
		freePins[#freePins + 1] = pin
		activePins[i] = nil
	end
end

local function PositionPins()
	for i = 1, #activePins do
		local pin = activePins[i]
		local vx, vy = PlaneToView(pin.px, pin.py)
		pin:SetPoint("CENTER", view, "TOPLEFT", vx, -vy)
	end
end

local function AddQuestPins(l, r, t, b, size)
	if not ns:GetSetting("showLiveQuests") or not ns:IsCategoryEnabled("quest") then
		return
	end
	if not underlayMapID or not C_QuestLine or not C_QuestLine.GetAvailableQuestLines then
		return
	end
	local ok, lines = pcall(C_QuestLine.GetAvailableQuestLines, underlayMapID)
	if not ok or type(lines) ~= "table" then
		return
	end
	for _, info in ipairs(lines) do
		if not info.isHidden and info.x and info.y then
			local _, wx, wy = ns.MapToWorld(underlayMapID, info.x, info.y)
			if wx then
				local px, py = ns.WorldToPlane(wx, wy)
				if px >= l and px <= r and py >= t and py <= b then
					local pin = AcquirePin()
					pin.quest = info
					pin.px, pin.py = px, py
					pin:SetSize(size, size)
					ns.Categories:ApplyIcon(pin.icon, "quest")
					ns.Categories:ApplyIcon(pin.highlight, "quest")
					pin.icon:SetAlpha(1)
				end
			end
		end
	end
end

local function RefreshPins()
	pinsDirty = false
	ReleasePins()
	local l, r, t, b = VisibleRect(0.1)
	-- plane -> world box (wx = -py, wy = -px)
	local minX, maxX, minY, maxY = -b, -t, -r, -l
	local size = PIN_SIZE * (ns:GetSetting("detailIconScale") or 1)
	local function Add(rec)
		local catID = ns.Categories:GetVisibleCategory(rec)
		if catID then
			local pin = AcquirePin()
			pin.rec, pin.catID = rec, catID
			pin.px, pin.py = ns.WorldToPlane(rec.x, rec.y)
			pin:SetSize(size, size)
			ns.Categories:ApplyIcon(pin.icon, catID, rec)
			ns.Categories:ApplyIcon(pin.highlight, catID, rec)
			pin.icon:SetAlpha((not rec.seed and (rec.a or 0) > 20) and 0.7 or 1)
		end
	end
	ns.Database:Query(cont, minX, maxX, minY, maxY, Add)
	ns.Seeds:Query(cont, minX, maxX, minY, maxY, Add)
	AddQuestPins(l, r, t, b, size)

	local waypoint = ns.Navigation:GetWaypoint()
	if waypoint and waypoint.c == cont then
		local px, py = ns.WorldToPlane(waypoint.x, waypoint.y)
		if px >= l and px <= r and py >= t and py <= b then
			local pin = AcquirePin()
			pin.rec, pin.catID = waypoint, "waypoint"
			pin.px, pin.py = px, py
			pin:SetSize(size * 1.3, size * 1.3)
			pin:SetFrameLevel(pinLayer:GetFrameLevel() + 2) -- above the other icons
			ns.Categories:ApplyIcon(pin.icon, "waypoint")
			ns.Categories:ApplyIcon(pin.highlight, "waypoint")
			pin.icon:SetAlpha(1)
		end
	end
	PositionPins()
	DetailView.pinRect = { l, r, t, b }
end

---------------------------------------------------------------------------
-- Player arrow and cursor coordinates
---------------------------------------------------------------------------
local function UpdateArrow()
	local pcont, wx, wy = ns.GetPlayerWorld()
	if pcont ~= cont then
		arrowFrame:Hide()
		return
	end
	local px, py = ns.WorldToPlane(wx, wy)
	local vx, vy = PlaneToView(px, py)
	arrowFrame:ClearAllPoints()
	arrowFrame:SetPoint("CENTER", view, "TOPLEFT", vx, -vy)
	local facing = GetPlayerFacing()
	if facing then
		arrowFrame.texture:SetRotation(facing)
	end
	arrowFrame:Show()
end

local function UpdateCoordinates()
	local px, py
	if view:IsMouseOver() then
		local vx, vy = CursorInView()
		px, py = ViewToPlane(vx, vy, cx, cy, scale)
	else
		local pcont, wx, wy = ns.GetPlayerWorld()
		if pcont == cont then
			px, py = ns.WorldToPlane(wx, wy)
		end
	end
	if not px then
		hud.coords:SetText("")
		return
	end
	local wx, wy = ns.PlaneToWorld(px, py)
	-- Coordinates on the zone under the view, like the world map would show them.
	local mapID = ZoneAt(px, py) or underlayMapID
	local rect = mapID and ns.GetMapRect(mapID)
	if rect and rect.cont == cont then
		local x, y = ns.WorldToMapRect(rect, wx, wy)
		if x >= 0 and x <= 1 and y >= 0 and y <= 1 then
			local info = C_Map.GetMapInfo(mapID)
			hud.coords:SetFormattedText("%s   %.1f, %.1f", info and info.name or "", x * 100, y * 100)
			return
		end
	end
	hud.coords:SetText("")
end

---------------------------------------------------------------------------
-- Transform and animation
---------------------------------------------------------------------------
local function ClampCenter()
	tcx = min(max(tcx, -PLANE_LIMIT), PLANE_LIMIT)
	tcy = min(max(tcy, -PLANE_LIMIT), PLANE_LIMIT)
end

local function ApplyTransform()
	transformDirty = false
	local w, h = ViewSize()
	plane:SetScale(scale)
	plane:ClearAllPoints()
	plane:SetPoint("TOPLEFT", view, "TOPLEFT", (w / 2 - cx * scale) / scale, -(h / 2 - cy * scale) / scale)
	-- Soft fog edges only where a cell is big enough on screen for them to show.
	local fuzzy = scale * CELL >= DetailView.FUZZY_MIN_CELL_PIXELS
	if fuzzy ~= fuzzyBuilt then
		fuzzyBuilt = fuzzy
		UpdateTiles(true)
	else
		UpdateTiles(false)
	end
	local rect = DetailView.pinRect
	local l, r, t, b = VisibleRect(0)
	if pinsDirty or not rect or l < rect[1] or r > rect[2] or t < rect[3] or b > rect[4] then
		RefreshPins()
	else
		PositionPins()
	end
	UpdateArrow()
end

local function OnUpdate(_, elapsed)
	if dragging and not IsMouseButtonDown("LeftButton") then
		-- released outside the view, so OnMouseUp never arrived
		dragging = false
	end
	if dragging then
		local vx, vy = CursorInView()
		local dx, dy = vx - dragX, vy - dragY
		if dx ~= 0 or dy ~= 0 then
			if abs(dx) + abs(dy) > 2 then
				dragMoved = true
			end
			dragX, dragY = vx, vy
			tcx = tcx - dx / scale
			tcy = tcy - dy / scale
			ClampCenter()
			cx, cy = tcx, tcy
			transformDirty = true
		end
	end

	if scale ~= tscale or cx ~= tcx or cy ~= tcy then
		local k = min(1, elapsed * 14)
		scale = scale + (tscale - scale) * k
		cx = cx + (tcx - cx) * k
		cy = cy + (tcy - cy) * k
		if abs(scale - tscale) < tscale * 0.002 and abs(cx - tcx) * scale < 0.5 and abs(cy - tcy) * scale < 0.5 then
			scale, cx, cy = tscale, tcx, tcy
		end
		transformDirty = true
	end

	if transformDirty then
		ApplyTransform()
	else
		UpdateArrow()
	end

	DetailView.slowTimer = (DetailView.slowTimer or 0) + elapsed
	if DetailView.slowTimer > 0.1 then
		DetailView.slowTimer = 0
		UpdateCoordinates()
		if scale == tscale and not dragging then
			local zone = ZoneAt(cx, cy)
			if zone and zone ~= underlayMapID then
				SetUnderlay(zone)
			end
			if pinsDirty then
				RefreshPins()
			end
		end
	end
end

function DetailView:ZoomAt(factor, vx, vy)
	local w, h = ViewSize()
	vx, vy = vx or w / 2, vy or h / 2
	local newScale = min(max(tscale * factor, exitScale), maxScale)
	-- keep the point under the cursor fixed
	local px, py = ViewToPlane(vx, vy, tcx, tcy, tscale)
	tcx = px - (vx - w / 2) / newScale
	tcy = py - (vy - h / 2) / newScale
	tscale = newScale
	ClampCenter()
end

-- Where the view is heading: continent and plane coordinates of its centre.
function DetailView:GetCenter()
	return cont, tcx, tcy
end

-- Slides the view over to the player; false when they are on another continent.
function DetailView:CenterOnPlayer()
	local pcont, wx, wy = ns.GetPlayerWorld()
	if not active or pcont ~= cont then
		return false
	end
	tcx, tcy = ns.WorldToPlane(wx, wy)
	ClampCenter()
	return true
end

function DetailView:BeginDrag()
	dragging, dragMoved = true, false
	dragX, dragY = CursorInView()
	tcx, tcy, tscale = cx, cy, scale -- stop any glide
end

function DetailView:EndDrag()
	local moved = dragMoved
	dragging, dragMoved = false, false
	return moved
end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------
local function CreateFrames()
	local container = WorldMapFrame:GetCanvasContainer()
	view = CreateFrame("Frame", "WayfinderDetailView", container)
	view:SetAllPoints(container)
	local manager = WorldMapFrame.GetPinFrameLevelsManager and WorldMapFrame:GetPinFrameLevelsManager()
	local topPinLevel = manager and manager.maxLevel or 3000
	view:SetFrameLevel(min(topPinLevel + 20, 9000))
	view:SetClipsChildren(true)
	view:EnableMouse(true)
	view:EnableMouseWheel(true)
	view:Hide()

	local background = view:CreateTexture(nil, "BACKGROUND", nil, -8)
	background:SetAllPoints()
	background:SetColorTexture(0.05, 0.07, 0.09, 1)

	plane = CreateFrame("Frame", nil, view)
	plane:SetSize(1, 1)
	plane:SetFrameLevel(view:GetFrameLevel() + 1)

	pinLayer = CreateFrame("Frame", nil, view)
	pinLayer:SetAllPoints()
	pinLayer:SetFrameLevel(view:GetFrameLevel() + 5)

	arrowFrame = CreateFrame("Frame", nil, view)
	arrowFrame:SetSize(28, 28)
	arrowFrame:SetFrameLevel(view:GetFrameLevel() + 8)
	arrowFrame.texture = arrowFrame:CreateTexture(nil, "OVERLAY")
	arrowFrame.texture:SetAllPoints()
	local arrowAtlas = ns.Categories.playerArrowAtlas
	if arrowAtlas then
		arrowFrame.texture:SetAtlas(arrowAtlas)
	else
		arrowFrame.texture:SetTexture(ns.Categories:GetMediaPath("PlayerArrow"))
	end

	hud = CreateFrame("Frame", nil, view)
	hud:SetAllPoints()
	hud:SetFrameLevel(view:GetFrameLevel() + 10)

	hud.coords = hud:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	hud.coords:SetPoint("BOTTOM", 0, 10)
	hud.coords:SetShadowOffset(1, -1)

	hud.hint = hud:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	hud.hint:SetPoint("TOP", 0, -12)
	hud.hint:SetText("Detail view: scroll to zoom, drag to pan, right-click or zoom out to return")
	hud.hint:SetShadowOffset(1, -1)

	local back = CreateFrame("Button", nil, hud, "UIPanelButtonTemplate")
	back:SetText("Back to map")
	back:SetSize(110, 22)
	back:SetPoint("BOTTOMRIGHT", -10, 8)
	back:SetScript("OnClick", function()
		DetailView:Exit()
	end)

	view:SetScript("OnMouseWheel", function(_, delta)
		if delta < 0 and tscale <= exitScale * 1.001 then
			DetailView:Exit()
			return
		end
		DetailView:ZoomAt(ZOOM_STEP ^ delta, CursorInView())
	end)
	view:SetScript("OnMouseDown", function(_, button)
		if button == "LeftButton" then
			DetailView:BeginDrag()
		end
	end)
	view:SetScript("OnMouseUp", function(_, button)
		if button == "LeftButton" then
			DetailView:EndDrag()
		elseif button == "RightButton" then
			DetailView:Exit()
		elseif button == "MiddleButton" then
			local vx, vy = CursorInView()
			local wx, wy = ns.PlaneToWorld(ViewToPlane(vx, vy, cx, cy, scale))
			ns.Navigation:SetWaypoint(cont, wx, wy, nil, underlayMapID)
		end
	end)
	view:SetScript("OnSizeChanged", function()
		if active then
			transformDirty = true
			pinsDirty = true
		end
	end)
	view:SetScript("OnUpdate", OnUpdate)
end

---------------------------------------------------------------------------
-- Entering and leaving
---------------------------------------------------------------------------
function DetailView:IsActive()
	return active
end

-- Opens the view over Blizzard's map showing exactly what the map shows now,
-- then keeps zooming toward the cursor.
function DetailView:EnterFromMap()
	local mapID = WorldMapFrame:GetMapID()
	local rect = ns.GetMapRect(mapID)
	if not rect or not ns.TileData[rect.cont] then
		return false
	end
	local info = C_Map.GetMapInfo(mapID)
	if not info or info.mapType < Enum.UIMapType.Continent then
		return false
	end
	if not view then
		CreateFrames()
	end
	view:Show()

	local viewRect = WorldMapFrame.ScrollContainer:GetViewRect()
	local left = -rect.left + viewRect.left * rect.width
	local right = -rect.left + viewRect.right * rect.width
	local top = -rect.top + viewRect.top * rect.height
	local bottom = -rect.top + viewRect.bottom * rect.height

	cont = rect.cont
	originMapID = mapID
	local w = WorldMapFrame.ScrollContainer:GetWidth()
	scale = w / max(right - left, 1)
	cx, cy = (left + right) / 2, (top + bottom) / 2

	local minScale = w / MAX_SPAN
	if scale < minScale then
		-- A continent at full size: start from a zone-sized window under the cursor.
		local vx, vy = CursorInView()
		cx, cy = ViewToPlane(vx, vy, cx, cy, scale)
		scale = minScale
	end
	exitScale = scale
	maxScale = max(w / MIN_SPAN, scale * 4)
	tcx, tcy, tscale = cx, cy, scale
	self.entryX, self.entryY = cx, cy

	active = true
	underlayMapID = nil
	ReleaseAllTiles()
	SetUnderlay(info.mapType == Enum.UIMapType.Continent and ZoneAt(cx, cy) or mapID)
	pinsDirty, transformDirty = true, true
	ApplyTransform()

	if C_QuestLine and C_QuestLine.RequestQuestLinesForMap and underlayMapID then
		C_QuestLine.RequestQuestLinesForMap(underlayMapID)
	end

	self.visit = (self.visit or 0) + 1
	local visit = self.visit
	hud.hint:Show()
	C_Timer.After(5, function()
		if self.visit == visit then
			hud.hint:Hide()
		end
	end)

	self:ZoomAt(ZOOM_STEP, CursorInView())
	return true
end

function DetailView:Exit(skipPan)
	if not active then
		return
	end
	active = false
	dragging = false
	view:Hide()
	ReleasePins()
	ReleaseAllTiles()
	ReleaseTextures(underlay)
	underlayMapID = nil
	GameTooltip:Hide()

	-- Put Blizzard's map where the detail view was looking, if it is still the same map.
	if not skipPan and WorldMapFrame:IsShown() and WorldMapFrame:GetMapID() == originMapID then
		local moved = abs(cx - (self.entryX or cx)) + abs(cy - (self.entryY or cy))
		local rect = ns.GetMapRect(originMapID)
		if rect and moved > 1 then
			local wx, wy = ns.PlaneToWorld(cx, cy)
			local nx, ny = ns.WorldToMapRect(rect, wx, wy)
			local container = WorldMapFrame.ScrollContainer
			local minX, maxX, minY, maxY = container:CalculateScrollExtentsAtScale(container:GetCanvasScale())
			WorldMapFrame:PanTo(min(max(nx, minX), maxX), min(max(ny, minY), maxY))
		end
	end
end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------
function DetailView:OnInitialize()
	HasBit = ns.HasBit
end

function DetailView:HookWorldMap()
	local container = WorldMapFrame.ScrollContainer
	local lastScaleChange = 0
	hooksecurefunc(WorldMapFrame, "OnCanvasScaleChanged", function()
		lastScaleChange = GetTime()
	end)
	container:HookScript("OnMouseWheel", function(_, delta)
		-- Blizzard zoomed during this same event: not at the limit yet.
		if delta <= 0 or active or GetTime() == lastScaleChange then
			return
		end
		if ns:GetSetting("detailEnabled") and container:IsAtMaxZoom() then
			DetailView:EnterFromMap()
		end
	end)
	WorldMapFrame:HookScript("OnHide", function()
		DetailView:Exit(true)
	end)
	hooksecurefunc(WorldMapFrame, "OnMapChanged", function()
		if active and WorldMapFrame:GetMapID() ~= originMapID then
			DetailView:Exit(true)
		end
	end)
end

function DetailView:OnLogin()
	EventUtil.ContinueOnAddOnLoaded("Blizzard_WorldMap", function()
		self:HookWorldMap()
	end)

	ns:On("EXPLORED", function(changedCont, keys)
		if not active then
			return
		end
		if changedCont == nil then
			UpdateTiles(true)
		elseif changedCont == cont then
			-- A tile's fog edges also read the cells just past its east and south
			-- edges, so its west, north and north-west neighbours change too.
			local rebuild = {}
			for _, key in ipairs(keys) do
				local col, row = ns.SplitTileKey(key)
				rebuild[key] = true
				rebuild[(col - 1) * 100 + row] = true
				rebuild[col * 100 + row - 1] = true
				rebuild[(col - 1) * 100 + row - 1] = true
			end
			for key in pairs(rebuild) do
				if activeTiles[key] then
					BuildTile(ns.SplitTileKey(key))
				end
			end
		end
		pinsDirty = true
	end)
	local function MarkPins()
		pinsDirty = true
	end
	ns:On("POI_UPDATED", MarkPins)
	ns:On("POI_REMOVED", MarkPins)
	ns:On("WAYPOINT_CHANGED", MarkPins)
	ns:On("DATA_CHANGED", function()
		if active then
			UpdateTiles(true)
		end
		pinsDirty = true
	end)
	ns:On("SETTING_CHANGED", function(key)
		if not active then
			return
		end
		if key == "unexploredTerrain" or key == "unexploredBrightness" or key == "shareExploration" then
			UpdateTiles(true)
		elseif key == "detailEnabled" and not ns:GetSetting("detailEnabled") then
			self:Exit()
		end
		pinsDirty = true
	end)
	ns:RegisterEvent("QUESTLINE_UPDATE", MarkPins)
end
