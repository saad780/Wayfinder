-- Native canvas contract for integration tests of the real controller/renderer.
-- Rectangles are synthetic; controller math is not replaced with a fake API.
mock.maps[947].mapType = Enum.UIMapType.World
mock.maps[1453].isCity = true
mock.maps[1411] = { name = "Durotar", mapType = 3, parent = 1414, cont = 1,
	top = 6000, left = 10000, width = 6000, height = 4000 }
mock.maps[1454] = { name = "Orgrimmar", mapType = 3, parent = 1414, cont = 1,
	top = 5800, left = 9500, width = 1200, height = 800, isCity = true }
mock.maps[1458] = { name = "Undercity", mapType = 3, parent = 1415, cont = 0,
	top = 10000, left = 10000, width = 1200, height = 800, isCity = true }
mock.maps[1420] = { name = "Tirisfal Glades", mapType = 3, parent = 1415, cont = 0,
	top = 11000, left = 12000, width = 6000, height = 4000 }
mock.maps[1421] = { name = "Silverpine Forest", mapType = 3, parent = 1415, cont = 0,
	top = 8500, left = 14000, width = 5000, height = 4000 }
mock.maps[9999] = { name = "Dungeon", mapType = 4, parent = 1429 }
local worldRects = { [947] = { 0, 1, 0, 1 },
	[1414] = { 0.05, 0.45, 0.1, 0.9 }, [1415] = { 0.55, 0.95, 0.1, 0.9 } }
for id, m in pairs(mock.maps) do
	if m.cont and not worldRects[id] then
		local p = mock.maps[m.cont == 0 and 1415 or 1414]
		local wr = worldRects[m.cont == 0 and 1415 or 1414]
		worldRects[id] = { wr[1] + (p.left - m.left) / p.width * (wr[2] - wr[1]),
			wr[1] + (p.left - m.left + m.width) / p.width * (wr[2] - wr[1]),
			wr[3] + (p.top - m.top) / p.height * (wr[4] - wr[3]),
			wr[3] + (p.top - m.top + m.height) / p.height * (wr[4] - wr[3]) }
	end
end
function C_Map.GetMapRectOnMap(id, parent)
	local r, p = worldRects[id], worldRects[parent]
	if not r or not p then return end
	return (r[1] - p[1]) / (p[2] - p[1]), (r[2] - p[1]) / (p[2] - p[1]),
		(r[3] - p[3]) / (p[4] - p[3]), (r[4] - p[3]) / (p[4] - p[3])
end
function C_Map.GetMapInfoAtPosition(parent, x, y)
	local found, area
	for id, m in pairs(mock.maps) do
		if m.parent == parent then
			local l, r, t, b = C_Map.GetMapRectOnMap(id, parent)
			if l and x >= l and x <= r and y >= t and y <= b and (not area or (r-l)*(b-t) < area) then
				found, area = id, (r-l)*(b-t)
			end
		end
	end
	return found and C_Map.GetMapInfo(found)
end
-- Distinct client tiles let tests distinguish the city from surface artwork.
function C_Map.GetMapArtLayerTextures(id)
	local files = {}
	for i = 1, 12 do files[i] = id * 100 + i end
	return files
end

local map, sc = WorldMapFrame, WorldMapFrame.ScrollContainer
local Region = getmetatable(map)
function Region:CreateMaskTexture()
	local mask = self:CreateTexture()
	mask.kind = "MaskTexture"
	return mask
end
function Region:EnableMouse(value) self.mouse = value end
function Region:EnableMouseWheel(value) self.wheel = value end
sc.mouseButtonInfo = { LeftButton = { down = false } }
sc.currentScale, sc.targetScale, sc.currentScrollX, sc.currentScrollY = 1, 1, 0.5, 0.5
sc.mapID = map.mapID
MAP_CANVAS_MOUSE_WHEEL_ZOOM_BEHAVIOR_NONE = 0
MAP_CANVAS_MOUSE_WHEEL_ZOOM_BEHAVIOR_FULL = 1
local fl = { maxLevel = 3100 }
function fl:InsertFrameLevelAbove() return true end
function fl:GetValidFrameLevel(kind) return kind == "PIN_FRAME_LEVEL_WAYFINDER_STITCH" and 400 or 1000 end
function map:GetPinFrameLevelsManager() return fl end
function sc:GetCanvasScale() return self.currentScale end
function sc:GetCurrentScrollX() return self.currentScrollX end
function sc:GetCurrentScrollY() return self.currentScrollY end
function sc:NormalizeHorizontalSize(w) return w / self.Child:GetWidth() end
function sc:NormalizeVerticalSize(h) return h / self.Child:GetHeight() end
function sc:CalculateScrollExtents()
	self.scrollXExtentsMin, self.scrollXExtentsMax, self.scrollYExtentsMin, self.scrollYExtentsMax =
		self:CalculateScrollExtentsAtScale(self.currentScale)
end
function sc:SetMouseWheelZoomMode(mode) self.mouseWheelZoomMode = mode end
function sc:SetScalingMode(mode) self.scalingMode = mode end
function sc:CreateZoomLevels() self.zoomLevels = { { scale = 1, layerIndex = 1 } } end
function sc:ResetZoom()
	self.currentScale, self.targetScale, self.currentScrollX, self.currentScrollY = 1, 1, 0.5, 0.5
end
function sc:OnCanvasSizeChanged()
	self.mapID = map.mapID
	self:CreateZoomLevels()
	self:ResetZoom()
end
function sc:MarkViewRectDirty()
	map:OnCanvasPanChanged()
end
function sc:GetViewRect()
	local hu = self:GetWidth() / (2 * self.Child:GetWidth() * self.currentScale)
	local hv = self:GetHeight() / (2 * self.Child:GetHeight() * self.currentScale)
	return { left = self.currentScrollX - hu, right = self.currentScrollX + hu,
		top = self.currentScrollY - hv, bottom = self.currentScrollY + hv }
end
function sc:GetCursorPosition()
	return (mock.mapCursorX or 0.5) * self.Child:GetWidth() * self.currentScale,
		(1 - (mock.mapCursorY or 0.5)) * self.Child:GetHeight() * self.currentScale
end
function map:EnumeratePinsByTemplate(template)
	local i = 0
	return function()
		repeat i = i + 1 until not self.pins[i] or self.pins[i].template == template
		return self.pins[i]
	end
end
function map:AddCanvasClickHandler(fn) self.canvasClick = fn end
function map:OnCanvasScaleChanged()
	for _, p in ipairs(self.providers) do if p.OnCanvasScaleChanged then p:OnCanvasScaleChanged() end end
end
function map:OnCanvasPanChanged()
	for _, p in ipairs(self.providers) do if p.OnCanvasPanChanged then p:OnCanvasPanChanged() end end
end
function map:OnMapChanged()
	for _, p in ipairs(self.providers) do if p.OnMapChanged then p:OnMapChanged() end end
end
function map:SetMapID(id)
	self.mapID = id
	sc:OnCanvasSizeChanged()
	self:OnMapChanged()
end
-- Exercise both standalone installation and coexistence in separate runtimes.
if mock.withOpenMap then
	local mod = { enabled = true, db = { enabled = true } }
	OpenMap = { GetModule = function() return mod end }
	OpenMapAPI = { major = 1, IsStitched = function() return mod.enabled end }
	mock.openMapModule = mod
end
