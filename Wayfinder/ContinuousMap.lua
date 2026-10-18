-- Private adapter for the MIT OpenMap scroll controller. The renderer and terrain
-- are Wayfinder's; nothing here depends on the OpenMap addon being installed.
local _, ns = ...
local Continuous = ns:NewModule("ContinuousMap")
local engine = { modules = {}, MapCityZones = {
	[1453] = 1429, [1454] = 1411, [1455] = 1426,
	[1456] = 1412, [1457] = 1438, [1458] = 1420,
} }
ns.ContinuousEngine = engine

function engine:NewModule(key, spec)
	spec.db = {}
	for k, v in pairs(spec.defaults) do spec.db[k] = v end
	spec.enabled = false
	self.modules[key] = spec
	return spec
end
function engine:GetModule(key) return self.modules[key] end
function engine:Print(...) ns.Print(...) end
function engine.RegisterEvent(owner, event, fn)
	ns:RegisterEvent(event, function(_, ...) fn(owner, event, ...) end)
end
engine.Safe = {
	IsSecret = function(v) return v ~= nil and not ns.Readable(v) end,
	XY = function(v) if v and ns.Readable(v) then return v:GetXY() end end,
	Call = function(fn, ...)
		if type(fn) ~= "function" then return end
		local ok, value = pcall(fn, ...)
		if ok and ns.Readable(value) then return value end
	end,
}

local callbacks = {}
local api = { major = 1, version = 2 }
Continuous.API = api
local function Controller() return engine:GetModule("worldmap") end
local function Fire(event, ...)
	for owner, fn in pairs(callbacks[event] or {}) do fn(owner, event, ...) end
end
function api.RegisterCallback(owner, event, fn)
	callbacks[event] = callbacks[event] or {}
	callbacks[event][owner] = fn
end
function api.IsStitched()
	local mod = Controller()
	return mod and mod.IsStitched() or false
end
function api.WorldFromMap(id, x, y)
	if engine.MapStitch.Rect(id) then return Controller().ToWorld(id, x, y) end
end
function api.MapFromWorld(id, u, v)
	if engine.MapStitch.Rect(id) then return Controller().FromWorld(id, u, v) end
end
function api.MapAt(u, v)
	local chain = engine.MapStitch.ChainAt(u, v)
	return chain[#chain]
end
function api.GetView() return Controller().ViewNow() end
function api.ShowWorld(u, v, zoom)
	if not api.IsStitched() then return false end
	local _, _, now = api.GetView()
	Controller().Glide(u, v, zoom or now)
	return true
end
function api.ArtTopLevel() return engine.MapStitch.artTop end
function api.CanvasFromWorldPos(cont, wx, wy)
	if not api.IsStitched() then return end
	local u, v = engine.MapStitch.FromYards(cont, wx, wy)
	if u then return api.MapFromWorld(WorldMapFrame:GetMapID(), u, v) end
end

function Continuous:IsActive() return api.IsStitched() end
function Continuous:UpdateLayerButton(city, surface)
	local button = self.layerButton
	if not city then if button then button:Hide() end; return end
	if not button then
		local container = WorldMapFrame:GetCanvasContainer()
		button = CreateFrame("Button", "WayfinderMapLayerButton", container, "BackdropTemplate")
		button:SetSize(118, 28)
		button:SetPoint("TOPRIGHT", container, "TOPRIGHT", -12, -44)
		button:SetFrameLevel(math.min(9500, container:GetFrameLevel() + 8700))
		button:RegisterForClicks("LeftButtonUp")
		button:SetPassThroughButtons("RightButton", "MiddleButton")
		button:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
		button:SetBackdropColor(0.035, 0.05, 0.06, 0.96)
		button:SetBackdropBorderColor(0.42, 0.34, 0.19, 1)
		-- Original, resolution-independent layer glyph. The active floor is gold.
		local function Path(points)
			local lines = {}
			for i = 1, #points - 1 do
				local line = button:CreateLine(nil, "ARTWORK")
				line:SetThickness(1.5)
				line:SetStartPoint("LEFT", button, 16 + points[i][1], points[i][2])
				line:SetEndPoint("LEFT", button, 16 + points[i+1][1], points[i+1][2])
				lines[#lines + 1] = line
			end
			return lines
		end
		button.upperLayer = Path({ { -8, 3 }, { 0, 7 }, { 8, 3 }, { 0, -1 }, { -8, 3 } })
		button.lowerLayer = Path({ { -8, -2 }, { 0, -6 }, { 8, -2 } })
		button.up = Path({ { 87, -2 }, { 91, 2 }, { 95, -2 } })
		button.down = Path({ { 87, 2 }, { 91, -2 }, { 95, 2 } })
		button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		button.label:SetPoint("LEFT", button, "LEFT", 32, 0)
		button.label:SetTextColor(0.9, 0.85, 0.72)
		button:SetScript("OnClick", function(owner)
			engine.MapStitch.ToggleUndergroundView()
			if owner:IsMouseOver() then owner:GetScript("OnEnter")(owner) end
		end)
		button:SetScript("OnEnter", function(owner)
			owner:SetBackdropColor(0.09, 0.11, 0.12, 1)
			owner:SetBackdropBorderColor(0.85, 0.65, 0.31, 1)
			local _, overworld = engine.MapStitch.GetUndergroundView()
			GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
			GameTooltip:SetText(overworld and "Show Undercity" or "Show overworld")
			GameTooltip:AddLine(overworld and "Current layer: overworld" or "Current layer: Undercity", 1, 1, 1)
			GameTooltip:Show()
		end)
		button:SetScript("OnLeave", function(owner)
			owner:SetBackdropColor(0.035, 0.05, 0.06, 0.96)
			owner:SetBackdropBorderColor(0.42, 0.34, 0.19, 1)
			GameTooltip_Hide()
		end)
		self.layerButton = button
	end
	button.label:SetText(surface and "Overworld" or "Undercity")
	for _, line in ipairs(button.upperLayer) do line:SetColorTexture(surface and 0.96 or 0.4, surface and 0.75 or 0.47, surface and 0.36 or 0.5, 1) end
	for _, line in ipairs(button.lowerLayer) do line:SetColorTexture(surface and 0.4 or 0.96, surface and 0.47 or 0.75, surface and 0.5 or 0.36, 1) end
	for _, line in ipairs(button.up) do line:SetColorTexture(0.9, 0.85, 0.72, 1); line:SetShown(not surface) end
	for _, line in ipairs(button.down) do line:SetColorTexture(0.9, 0.85, 0.72, 1); line:SetShown(surface) end
	button:Show()
end
function Continuous:GetMaxZoom(u, v)
	local S, mod = engine.MapStitch, Controller()
	local id = S.ContinentAt(u, v)
	local rect = id and ns.GetMapRect(id)
	local l, r
	if id then l, r = S.Rect(id) end
	if not rect or not l then return mod.db.maxZoom end
	local half = mod.ViewHalfExtents(1)
	-- Same 140-yard window as the standalone terrain view, regardless of the
	-- continent's size, window aspect ratio or current host map.
	return math.max(16, half * 2 / (r - l) * rect.width / 140)
end
function Continuous:PlaceWaypointAtCursor()
	local id, x, y = ns.OpenMapCompat:CursorPoint()
	if id then ns.Navigation:SetWaypointOnMap(id, x, y) end
end
function Continuous:ZoomToDetail()
	if not self:IsActive() then return false end
	local mod, S = Controller(), engine.MapStitch
	local u, v, zoom = mod.ViewNow()
	local id = S.ContinentAt(u, v)
	local rect = id and ns.GetMapRect(id)
	local l, r
	if id then l, r = S.Rect(id) end
	if rect and l then
		local half = mod.ViewHalfExtents(zoom)
		local span = half * 2 / (r - l) * rect.width
		mod.Glide(u, v, math.max(zoom * 1.25, zoom * span / 2500))
	else
		mod.WheelZoom(1)
	end
	return true
end

-- Only one addon may own the wheel/extents. OptionalDeps loads OpenMap first.
-- Suspend its runtime controller before rebuilding; never alter its saved settings.
function Continuous:SuspendOpenMap()
	local other = OpenMap and OpenMap.GetModule and OpenMap:GetModule("worldmap")
	if other and other.enabled then
		other.enabled = false
		self.suspendedOpenMap = other
		WorldMapFrame.ScrollContainer:OnCanvasSizeChanged()
	end
end

function Continuous:Start()
	if self.started or not ns:GetSetting("continuousMap") then return end
	if not C_Map.GetMapRectOnMap or not C_Map.GetMapInfoAtPosition then return end
	local map = WorldMapFrame
	local sc = map and map.ScrollContainer
	local fl = map and map.GetPinFrameLevelsManager and map:GetPinFrameLevelsManager()
	if not sc or not sc.CreateZoomLevels or not fl or not fl.InsertFrameLevelAbove then return end
	self.started = true
	self:SuspendOpenMap()
	local mod = Controller()
	mod.enabled = true
	mod.OnStitchedChanged = function(on)
		if not on and ns.DetailView:IsFollowingMap() then ns.DetailView:Exit(true) end
		Fire("OpenMap_StitchedChanged", on)
	end
	local last, lastU, lastV, lastZoom, lastMap = 0
	local publishPending
	local function PublishView()
		publishPending = nil
		if not api.IsStitched() or not map:IsShown() then return end
		local u, v, zoom = mod.ViewNow()
		local host = mod.HostMap()
		if u ~= lastU or v ~= lastV or zoom ~= lastZoom or host ~= lastMap then
			last = GetTime()
			lastU, lastV, lastZoom, lastMap = u, v, zoom, host
			Fire("OpenMap_ViewChanged", u, v, zoom)
		end
	end
	mod.OnViewMoved = function()
		if GetTime() - last >= 0.1 then PublishView()
		elseif not publishPending then
			publishPending = true
			C_Timer.After(0.1, PublishView) -- also publishes the final animation frame
		end
	end
	mod:OnEnable()
	ns.OpenMapCompat:Install()
	map:HookScript("OnHide", function() engine.MapStitch.ResetUndergroundView() end)
	-- Quest/exploration events update the detail layer directly. An idle map
	-- does not need to recull artwork and rebuild terrain on a polling timer.
end

function Continuous:OnLogin()
	EventUtil.ContinueOnAddOnLoaded("Blizzard_WorldMap", function()
		C_Timer.After(0, function() self:Start() end)
	end)
	ns:On("SETTING_CHANGED", function(key)
		if key == "continuousMap" then
			ns.Print("Continuous map changes take effect after /reload.")
		elseif self.started and (key == "detailEnabled" or key == "unexploredTerrain") then
			Controller().RefreshView()
		end
	end)
end
