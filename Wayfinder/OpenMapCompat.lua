-- Coordinate adapter shared by Wayfinder's continuous map and OpenMap's public
-- API. Locations stay in world yards; neither adapter changes saved map data.
local _, ns = ...
local Compat = ns:NewModule("OpenMapCompat")
local CONTINENTS = { 1415, 1414 }

local function Number(value)
	return ns.Readable(value) and type(value) == "number" and value == value
		and value > -math.huge and value < math.huge
end

function Compat:GetAPI()
	local api = ns.ContinuousMap:IsActive() and ns.ContinuousMap.API or OpenMapAPI
	if type(api) == "table" and api.major == 1 and type(api.IsStitched) == "function"
		and api.IsStitched() then return api end
end

function Compat:IsActive()
	return self:GetAPI() ~= nil
end

function Compat:MapPoint(u, v)
	local api = self:GetAPI()
	if not api or not Number(u) or not Number(v) then return end
	local mapID = api.MapAt(u, v)
	if not mapID then return end
	local x, y = api.MapFromWorld(mapID, u, v)
	if Number(x) and Number(y) and ns.GetMapRect(mapID) then return mapID, x, y end
end

function Compat:CanvasPoint(x, y)
	local api = self:GetAPI()
	if not api or not Number(x) or not Number(y) then return end
	return self:MapPoint(api.WorldFromMap(WorldMapFrame:GetMapID(), x, y))
end

function Compat:CursorPoint()
	local sc = WorldMapFrame.ScrollContainer
	local x, y = sc:GetCursorPosition()
	local scale = sc:GetCanvasScale()
	local canvas = sc.Child
	local l, t, w, h = canvas:GetLeft(), canvas:GetTop(), canvas:GetWidth(), canvas:GetHeight()
	if not Number(x) or not Number(y) or not Number(l) or not Number(t)
		or not Number(scale) or scale <= 0 or w <= 0 or h <= 0 then return end
	-- Blizzard's GetNormalizedCursorPosition saturates to 0..1, which would
	-- send a click in an adjacent zone to the edge of OpenMap's host map.
	return self:CanvasPoint((x / scale - l) / w, (t - y / scale) / h)
end

function Compat:GetDetailMap()
	local api = self:GetAPI()
	if not api then return end
	local mapID = self:MapPoint(api.GetView())
	if not mapID then return end
	local host = WorldMapFrame:GetMapID()
	local view = WorldMapFrame.ScrollContainer:GetViewRect()
	local u0, v0 = api.WorldFromMap(host, view.left, view.top)
	local u1, v1 = api.WorldFromMap(host, view.right, view.bottom)
	if not u0 or not u1 then return end
	local left, top = api.MapFromWorld(mapID, u0, v0)
	local right, bottom = api.MapFromWorld(mapID, u1, v1)
	if Number(left) and Number(top) and Number(right) and Number(bottom) then
		return mapID, { left = left, right = right, top = top, bottom = bottom }
	end
end

function Compat:ShowPlayer()
	local api = self:GetAPI()
	if not api then return false end
	local _, _, _, mapID, x, y = ns.GetPlayerWorld()
	if not mapID then return true end
	local u, v = api.WorldFromMap(mapID, x, y)
	if u then api.ShowWorld(u, v) end
	return true
end

function Compat:RaisePin(pin)
	local api = self:GetAPI()
	local top = api and api.ArtTopLevel and api.ArtTopLevel()
	if Number(top) then pin:SetFrameLevel(math.min(9999, math.max(pin:GetFrameLevel(), top + 2))) end
end

-- Small world-space boxes for visibility tests, without resolving a zone for
-- every icon. Useful before reading artwork or scheduling another addon's pins.
function Compat:GetViewBoxes(padding)
	local api = self:GetAPI()
	if not api then return {} end
	local map, boxes = WorldMapFrame, {}
	local view = map.ScrollContainer:GetViewRect()
	local w, h = view.right-view.left, view.bottom-view.top
	padding = padding or 0
	local u0,v0 = api.WorldFromMap(map:GetMapID(),view.left-w*padding,view.top-h*padding)
	local u1,v1 = api.WorldFromMap(map:GetMapID(),view.right+w*padding,view.bottom+h*padding)
	if not u0 or not u1 then return boxes end
	for _, id in ipairs(CONTINENTS) do
		local x0,y0 = api.MapFromWorld(id,u0,v0)
		local x1,y1 = api.MapFromWorld(id,u1,v1)
		if Number(x0) and Number(y0) and Number(x1) and Number(y1) then
			x0,y0,x1,y1 = math.max(0,x0),math.max(0,y0),math.min(1,x1),math.min(1,y1)
			if x0 <= x1 and y0 <= y1 then
				local c,wx0,wy0 = ns.MapToWorld(id,x0,y0)
				local _,wx1,wy1 = ns.MapToWorld(id,x1,y1)
				if c then boxes[#boxes+1] = {cont=c,minX=wx1,maxX=wx0,minY=wy1,maxY=wy0} end
			end
		end
	end
	return boxes
end

-- Query both continents in the visible canvas rectangle, even when the host
-- is Azeroth or a different zone. Positions outside 0..1 are valid here.
function Compat:RefreshPins(map, add)
	local api = self:GetAPI()
	if not api or not api.CanvasFromWorldPos then return false end
	local view = map.ScrollContainer:GetViewRect()
	local host = map:GetMapID()
	local u0, v0 = api.WorldFromMap(host, view.left, view.top)
	local u1, v1 = api.WorldFromMap(host, view.right, view.bottom)
	if not u0 or not u1 then return true end
	local _, _, zoom = api.GetView()
	if zoom and zoom < 3 and not ns:GetSetting("showOnContinent") then return true end
	local function Add(rec, catID)
		catID = catID or ns.Categories:GetVisibleCategory(rec)
		if not catID then return end
		local x, y = api.CanvasFromWorldPos(rec.c, rec.x, rec.y)
		if Number(x) and Number(y) and x >= view.left and x <= view.right
			and y >= view.top and y <= view.bottom then add(rec, catID, x, y) end
	end
	for _, mapID in ipairs(CONTINENTS) do
		local x0, y0 = api.MapFromWorld(mapID, u0, v0)
		local x1, y1 = api.MapFromWorld(mapID, u1, v1)
		if Number(x0) and Number(y0) and Number(x1) and Number(y1) then
			x0, y0, x1, y1 = math.max(0, x0), math.max(0, y0), math.min(1, x1), math.min(1, y1)
			local c, wx0, wy0 = ns.MapToWorld(mapID, x0, y0)
			local _, wx1, wy1 = ns.MapToWorld(mapID, x1, y1)
			if c and x0 <= x1 and y0 <= y1 then
				local a, b, l, r = math.min(wx0, wx1), math.max(wx0, wx1), math.min(wy0, wy1), math.max(wy0, wy1)
				ns.Database:Query(c, a, b, l, r, Add)
				ns.Seeds:Query(c, a, b, l, r, Add)
			end
		end
	end
	local waypoint = ns.Navigation:GetWaypoint()
	if waypoint then Add(waypoint, "waypoint") end
	return true
end

function Compat:Install()
	local api = ns.ContinuousMap.started and ns.ContinuousMap.API or OpenMapAPI
	if self.installed == api or type(api) ~= "table" or api.major ~= 1 or not WorldMapFrame then return end
	self.installed = api
	if api.RegisterCallback then
		local function Refresh()
			ns.MapPins:Refresh()
		end
		api.RegisterCallback(self, "OpenMap_ViewChanged", Refresh)
		api.RegisterCallback(self, "OpenMap_StitchedChanged", function()
			if ns.DetailView:IsActive() then ns.DetailView:Exit(true) end
			Refresh()
		end)
	end
	-- OpenMap's middle-click recentres the map. Keep Wayfinder's established
	-- waypoint gesture on the stitched canvas, before that recenter can move it.
	-- Every other button and every non-stitched map uses the original scripts.
	local container = WorldMapFrame.ScrollContainer
	if container:GetScript("OnMouseUp") ~= self.mouseScript then
		local original = container:GetScript("OnMouseUp")
		self.mouseScript = function(frame, button, ...)
			if button == "MiddleButton" and self:IsActive() and not ns.DetailView:IsActive() then
				local mapID, x, y = self:CursorPoint()
				if mapID then ns.Navigation:SetWaypointOnMap(mapID, x, y) end
				return
			end
			if original then return original(frame, button, ...) end
		end
		container:SetScript("OnMouseUp", self.mouseScript)
	end
	ns.MapPins:Refresh()
end

function Compat:OnLogin()
	EventUtil.ContinueOnAddOnLoaded("Blizzard_WorldMap", function()
		C_Timer.After(0, function() self:Install() end)
	end)
	ns:RegisterEvent("ADDON_LOADED", function(_, name)
		if name == "OpenMap" then C_Timer.After(0, function() self:Install() end) end
	end)
end
