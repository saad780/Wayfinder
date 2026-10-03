-- Icons on Blizzard's world map, plus the tooltip shared with the detail view.
local _, ns = ...

local MapPins = ns:NewModule("MapPins")

local PIN_TEMPLATE = "WayfinderMapPinTemplate"
local APPROXIMATE_YARDS = 20

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------
local Tooltip = {}
ns.Tooltip = Tooltip

function Tooltip:Show(owner, rec, catID)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	if rec.waypoint then
		GameTooltip:SetText(rec.n, 1, 0.82, 0)
		if rec.where and rec.where ~= rec.n then
			GameTooltip:AddLine(rec.where, 0.8, 0.8, 0.8)
		end
		GameTooltip:AddLine("Waypoint", 0.6, 0.85, 1)
		GameTooltip:AddLine("Middle-click to remove", 0.5, 0.5, 0.5)
		GameTooltip:Show()
		return
	end
	local cat = ns.CategoryByID[catID]
	GameTooltip:SetText(rec.n or (cat and cat.label) or UNKNOWN, 1, 0.82, 0)
	if rec.s and rec.s ~= rec.n then
		GameTooltip:AddLine("<" .. rec.s .. ">", 0.8, 0.8, 0.8)
	end
	local services = {}
	for _, c in ipairs(ns.CategoryList) do
		if rec.cats[c.id] then
			services[#services + 1] = c.label
		end
	end
	if #services > 1 or (rec.n and #services == 1) then
		GameTooltip:AddLine(table.concat(services, ", "), 0.6, 0.85, 1, true)
	end
	if rec.seed then
		GameTooltip:AddLine("Built-in location, revealed by exploring", 0.5, 0.5, 0.5)
	elseif (rec.a or 0) > APPROXIMATE_YARDS then
		GameTooltip:AddLine(("Approximate (within ~%d yards)"):format(rec.a), 1, 0.6, 0.2)
	end
	GameTooltip:AddLine("Middle-click to set a waypoint here", 0.5, 0.5, 0.5)
	GameTooltip:AddLine("Shift-click to remove", 0.5, 0.5, 0.5)
	GameTooltip:Show()
end

function ns:RemoveLocation(rec)
	if rec.seed then
		ns.Seeds:Hide(rec)
	else
		ns.Database:Remove(rec)
	end
	GameTooltip:Hide()
end

---------------------------------------------------------------------------
-- Which map a location belongs on
---------------------------------------------------------------------------
-- The game decides which uiMap owns each world position (Stormwind City vs. the
-- Elwynn Forest map around it); we show a location on that map and its parents.
local bestMapOf = setmetatable({}, { __mode = "k" })
local ancestry = {} -- [childMapID][mapID] = bool

local function BestMap(rec)
	local mapID = bestMapOf[rec]
	if mapID == nil then
		mapID = false
		local ok, found = pcall(C_Map.GetMapPosFromWorldPos, rec.c, CreateVector2D(rec.x, rec.y))
		-- Only an answer at zone level or finer says which zone owns the spot.
		local info = ok and found and C_Map.GetMapInfo(found)
		if info and info.mapType >= Enum.UIMapType.Zone then
			mapID = found
		end
		bestMapOf[rec] = mapID
	end
	-- Fall back to the map the location was recorded on; with neither, show it
	-- wherever it falls inside the map.
	return mapID or rec.m
end

local function IsWithin(childMapID, mapID)
	if not childMapID then
		return true
	end
	local cache = ancestry[childMapID]
	if not cache then
		cache = {}
		ancestry[childMapID] = cache
	end
	local result = cache[mapID]
	if result == nil then
		result = false
		local current, depth = childMapID, 0
		while current and depth < 12 do
			if current == mapID then
				result = true
				break
			end
			local info = C_Map.GetMapInfo(current)
			current = info and info.parentMapID
			depth = depth + 1
		end
		cache[mapID] = result
	end
	return result
end

ns.BelongsToMap = function(rec, mapID)
	return IsWithin(BestMap(rec), mapID)
end

---------------------------------------------------------------------------
-- Pin
---------------------------------------------------------------------------
WayfinderMapPinMixin = CreateFromMixins(MapCanvasPinMixin)

function WayfinderMapPinMixin:OnLoad()
	self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
	self:SetScalingLimits(1, 1.0, 1.2)
end

function WayfinderMapPinMixin:OnAcquired(rec, catID, x, y)
	self.rec, self.catID = rec, catID
	-- the waypoint sits above everything else
	self:UseFrameLevelType(rec.waypoint and "PIN_FRAME_LEVEL_WAYPOINT_LOCATION" or "PIN_FRAME_LEVEL_AREA_POI")
	local size = (rec.waypoint and 24 or 18) * (ns:GetSetting("iconScale") or 1)
	self:SetSize(size, size)
	ns.Categories:ApplyIcon(self.Icon, catID, rec)
	ns.Categories:ApplyIcon(self.Highlight, catID, rec)
	self.Icon:SetAlpha((not rec.seed and (rec.a or 0) > APPROXIMATE_YARDS) and 0.7 or 1)
	self:SetPosition(x, y)
end

function WayfinderMapPinMixin:OnMouseEnter()
	Tooltip:Show(self, self.rec, self.catID)
end

function WayfinderMapPinMixin:OnMouseLeave()
	GameTooltip:Hide()
end

function WayfinderMapPinMixin:OnMouseClickAction(button)
	if button == "MiddleButton" then
		ns.Navigation:ToggleWaypointAt(self.rec, self.catID)
	elseif button == "LeftButton" and IsShiftKeyDown() then
		if self.rec.waypoint then
			ns.Navigation:ClearWaypoint()
		else
			ns:RemoveLocation(self.rec)
		end
	end
end

---------------------------------------------------------------------------
-- Data provider
---------------------------------------------------------------------------
local provider = CreateFromMixins(MapCanvasDataProviderMixin)

function provider:RemoveAllData()
	self:GetMap():RemoveAllPinsByTemplate(PIN_TEMPLATE)
end

function provider:RefreshAllData()
	self:RemoveAllData()
	if not ns.db or not ns:GetSetting("showOnWorldMap") then
		return
	end
	local map = self:GetMap()
	local mapID = map:GetMapID()
	local info = mapID and C_Map.GetMapInfo(mapID)
	if not info then
		return
	end
	local mapType = info.mapType
	if mapType < Enum.UIMapType.Zone
		and not (mapType == Enum.UIMapType.Continent and ns:GetSetting("showOnContinent")) then
		return
	end
	local rect = ns.GetMapRect(mapID)
	if not rect then
		return
	end
	local minX, maxX = rect.top - rect.height, rect.top
	local minY, maxY = rect.left - rect.width, rect.left
	local function Add(rec)
		local catID = ns.Categories:GetVisibleCategory(rec)
		if catID and ns.BelongsToMap(rec, mapID) then
			local x, y = ns.WorldToMapRect(rect, rec.x, rec.y)
			if x >= 0 and x <= 1 and y >= 0 and y <= 1 then
				map:AcquirePin(PIN_TEMPLATE, rec, catID, x, y)
			end
		end
	end
	ns.Database:Query(rect.cont, minX, maxX, minY, maxY, Add)
	ns.Seeds:Query(rect.cont, minX, maxX, minY, maxY, Add)

	local waypoint = ns.Navigation:GetWaypoint()
	if waypoint and waypoint.c == rect.cont and ns.BelongsToMap(waypoint, mapID) then
		local x, y = ns.WorldToMapRect(rect, waypoint.x, waypoint.y)
		if x >= 0 and x <= 1 and y >= 0 and y <= 1 then
			map:AcquirePin(PIN_TEMPLATE, waypoint, "waypoint", x, y)
		end
	end
end

function MapPins:Refresh()
	if self.pending or not WorldMapFrame or not WorldMapFrame:IsShown() then
		return
	end
	-- Coalesce bursts of updates (walking reveals cells every half second).
	self.pending = true
	C_Timer.After(0.25, function()
		self.pending = false
		if WorldMapFrame:IsShown() then
			provider:RefreshAllData()
		end
	end)
end

function MapPins:OnLogin()
	EventUtil.ContinueOnAddOnLoaded("Blizzard_WorldMap", function()
		WorldMapFrame:AddDataProvider(provider)
	end)
	local function Refresh()
		self:Refresh()
	end
	ns:On("POI_UPDATED", function(rec)
		bestMapOf[rec] = nil
		Refresh()
	end)
	ns:On("POI_REMOVED", Refresh)
	ns:On("SETTING_CHANGED", Refresh)
	ns:On("DATA_CHANGED", Refresh)
	ns:On("EXPLORED", Refresh)
	ns:On("WAYPOINT_CHANGED", Refresh)
end
