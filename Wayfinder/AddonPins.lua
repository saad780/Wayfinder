-- Carry other addons' displayed world-map markers into the terrain detail view.
-- Read the live frames rather than importing addon databases or moving their pins.
local _, ns = ...
local AddonPins = ns:NewModule("AddonPins")
local entries = {}
local byFrame = {}
local CaptureAppearance, SameAppearance
local hovered
local masked = setmetatable({}, { __mode = "k" })

local function WriteAlpha(frame, state, alpha)
	state.writing = true
	frame:SetAlpha(alpha)
	state.writing = nil
end

-- The persistent copy and the original must never draw together. Keep frames
-- shown so their owners can update positions, visibility, artwork and tooltips.
-- Remember owner alpha changes while masked, including pooled-frame reuse.
function AddonPins:SyncSources(sources)
	for frame, state in pairs(masked) do
		if state.owned and not sources[frame] then
			state.owned = nil
			WriteAlpha(frame, state, state.alpha)
		end
	end
	for frame in pairs(sources) do
		local state = masked[frame]
		if not state then
			state = {}
			masked[frame] = state
			hooksecurefunc(frame, "SetAlpha", function(owner, alpha)
				if state.owned and not state.writing then
					state.alpha = alpha
					if alpha ~= 0 then WriteAlpha(owner, state, 0) end
				end
			end)
		end
		if not state.owned then state.alpha = frame:GetAlpha() end
		state.owned = true
		WriteAlpha(frame, state, 0)
	end
end

local function EffectiveAlpha(frame)
	local alpha, depth = 1, 0
	while frame and depth < 20 do
		local state = masked[frame]
		alpha = alpha * (state and state.owned and state.alpha or frame:GetAlpha())
		if frame.IsIgnoringParentAlpha and frame:IsIgnoringParentAlpha() then break end
		frame, depth = frame:GetParent(), depth + 1
	end
	return alpha
end

local function Number(value)
	return ns.Readable(value) and type(value) == "number" and value == value
		and value > -math.huge and value < math.huge
end

local function Text(value)
	return ns.Readable(value) and type(value) == "string" and value ~= "" and value or nil
end

local function IsOwn(frame)
	return frame == WayfinderDetailView or frame.pinTemplate == "WayfinderMapPinTemplate"
		or (type(frame.rec) == "table" and frame.rec.cats)
end
local function IgnoreZoomFade(frame)
	return ns.DetailView and ns.DetailView:IsFollowingMap() and not frame.hidden
		and frame.GetPosition and frame.GetMap
end

local function Label(frame)
	local data = frame.data or frame.POI or frame.poiInfo or frame.vignetteInfo
	if type(data) == "table" then
		local name = Text(data.Name) or Text(data.name) or Text(data.questName)
		if name then return name end
	end
	-- SilverDragon keeps the name in its core rather than on the overlay pin.
	if frame.coord and frame.uiMapID and frame.id and SilverDragon and SilverDragon.GetLabel then
		local ok, name = pcall(SilverDragon.GetLabel, SilverDragon, frame.id, frame.isTreasure)
		if ok and Text(name) then return name end
	end
	return Text(frame.name) or "Map icon"
end

local function ReadPin(frame, clip)
	if IsOwn(frame) or not frame:IsVisible() then return nil end
	local mapID = WorldMapFrame:GetMapID()
	local x, y
	-- Native MapCanvas pins and the HBD wrappers used by Questie/HandyNotes.
	if frame.GetPosition and frame.GetMap then
		x, y = frame:GetPosition()
		local map = frame:GetMap()
		if map and map.GetMapID then mapID = map:GetMapID() end
		-- Reject offscreen canvas pins before looking up zones, NPC metadata or
		-- texture layers. A world/continent host can contain thousands of pins.
		local box = clip and clip.canvas
		if box and map == WorldMapFrame and Number(x) and Number(y)
			and (x < box.left or x > box.right or y < box.top or y > box.bottom) then return end
		if ns.OpenMapCompat:IsActive() then
			mapID, x, y = ns.OpenMapCompat:CanvasPoint(x, y)
		end
	end
	-- OpenMap's own pins live in clipped cells over the scroll container,
	-- positioned in its stitched world instead of a MapCanvas pin template.
	if frame.anchor and frame.look and Number(frame.u) and Number(frame.v) then
		mapID, x, y = ns.OpenMapCompat:MapPoint(frame.u, frame.v)
	end
	-- RareScanner and SilverDragon also have their own canvas/pin pools.
	if not Number(x) or not Number(y) then
		if not (frame.provider or frame.dataProvider or frame.POI) then return nil end
		x, y = frame.x, frame.y
	end
	-- SilverDragon nudges overlapping markers; navigate to the original spawn.
	if Number(frame.coord) and Number(frame.uiMapID) then
		mapID = frame.uiMapID
		x, y = math.floor(frame.coord / 10000) / 10000, (frame.coord % 10000) / 10000
	end
	if not Number(x) or not Number(y) or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
	local c, wx, wy = ns.MapToWorld(mapID, x, y)
	if not c then return nil end
	if clip and (c ~= clip.cont or wx < clip.minX or wx > clip.maxX or wy < clip.minY or wy > clip.maxY) then return end
	local source = frame
	if frame.icon and frame.icon.IsObjectType and frame.icon:IsObjectType("Frame") then
		source = frame.icon -- HBD's wrapper has no art or dimensions of its own.
	end
	if not source:IsVisible() then return nil end
	local alpha = EffectiveAlpha(source)
	if not Number(alpha) or (alpha <= 0 and not IgnoreZoomFade(frame)) then return nil end
	local w, h = source:GetSize()
	if not Number(w) or not Number(h) or w <= 0 or h <= 0 or w > 128 or h > 128 then return nil end
	local questID = frame.questID
	local data = source.data
	local kind, npcID, service
	if type(data) == "table" then
		if data.Type == "complete" or data.Type == "available" then
			questID, kind = data.Id, data.Type
		elseif data.Type == "manual" then
			npcID = data.id
			local tag = source.wayfinderServiceTag or frame.wayfinderServiceTag
			if tag and tag.data == data then service = tag.cat end
		end
	end
	if not Number(questID) or questID <= 0 then questID = nil end
	if not Number(npcID) or npcID <= 0 then npcID = nil end
	local turnIn = ns.QuestTurnIns:IsReady(questID) and true or nil
	local giver = kind or turnIn or (questID and ns.QuestAvailability:IsQuestAvailable(questID))
	return { frame = frame, source = source, c = c, x = wx, y = wy, m = mapID, n = Label(source),
		questID = questID, turnIn = turnIn, kind = kind, giver = giver, npcID = npcID, service = service }
end

-- Some third-party pins contain restricted values or are briefly half released.
-- One unreadable pin must not interrupt the rest of the map.
local function TryRead(frame, clip)
	local ok, entry = pcall(ReadPin, frame, clip)
	return ok and entry or nil
end

local function CurrentEntry(entry)
	local current = TryRead(entry.frame)
	if not current or current.source ~= entry.source or current.m ~= entry.m
		or current.x ~= entry.x or current.y ~= entry.y then return nil end
	return current
end

function AddonPins:NavigateTo(entry)
	local current = CurrentEntry(entry)
	if not current then return false end
	ns.Navigation:SetWaypoint(current.c, current.x, current.y, current.n, current.m)
	return true
end

-- Use the owner's actual hover scripts with its original frame/data. Questie
-- builds quest objectives dynamically, and some addons use their own tooltip.
-- A mirrored icon must not replace that information with navigation help.
function AddonPins:HideTooltip(pin)
	if not hovered or (pin and hovered.pin ~= pin) then return end
	local previous = hovered
	hovered = nil
	if previous.leave then pcall(previous.leave, previous.source) end
	GameTooltip:Hide()
end

function AddonPins:ShowTooltip(pin, entry)
	self:HideTooltip()
	local current = CurrentEntry(entry)
	if not current then return false end
	local source = current.source
	local enter = source:GetScript("OnEnter")
	if not enter and source ~= current.frame then
		source = current.frame
		enter = source:GetScript("OnEnter")
	end
	if not enter then return false end
	hovered = { pin = pin, source = source, leave = source:GetScript("OnLeave"), entry = current }
	if not pcall(enter, source) then
		self:HideTooltip(pin)
		return false
	end
	return true
end

-- The detail view rebuilds its pooled pins as the map moves or artwork changes.
-- Keep an open tooltip tied to the same live marker across those rebuilds.
function AddonPins:RestoreTooltip(pins)
	if not hovered then return end
	if CurrentEntry(hovered.entry) then
		for _, pin in ipairs(pins) do
			if pin.external and pin.external.source == hovered.entry.source
				and pin:IsVisible() and pin:IsMouseOver() then
				hovered.pin = pin
				return
			end
		end
	end
	self:HideTooltip()
end

local ENTRY_FIELDS = { "source", "c", "x", "y", "m", "n", "questID", "turnIn", "kind", "giver", "npcID", "service" }
local function SameEntry(a, b)
	if not b then return false end
	for _, key in ipairs(ENTRY_FIELDS) do if a[key] ~= b[key] then return false end end
	return SameAppearance(a.appearance, b.appearance)
end

function AddonPins:RequestRefresh()
	if self.pending or not WorldMapFrame:IsShown() or not (ns.DetailView:IsActive() or ns.DetailView:IsFollowingMap()) then return end
	self.pending = true
	C_Timer.After(0, function()
		self.pending = nil
		if WorldMapFrame:IsShown() and (ns.DetailView:IsActive() or ns.DetailView:IsFollowingMap()) then self:Refresh() end
	end)
end

function AddonPins:Refresh()
	local nextEntries, nextByFrame, changed = {}, {}, false
	local clip = ns.DetailView:GetPinBounds()
	if clip and ns.DetailView:IsFollowingMap() then
		local rect = WorldMapFrame.ScrollContainer:GetViewRect()
		local w, h = rect.right - rect.left, rect.bottom - rect.top
		clip.canvas = { left = rect.left - w*0.2, right = rect.right + w*0.2,
			top = rect.top - h*0.2, bottom = rect.bottom + h*0.2 }
	end
	local function Walk(frame, depth)
		if depth > 4 or IsOwn(frame) or not frame:IsVisible() then return end
		local entry = TryRead(frame, clip)
		if entry then
			local ok, appearance = pcall(CaptureAppearance, entry)
			if ok and appearance then
				entry.appearance = appearance
				if SameEntry(entry, byFrame[frame]) then entry = byFrame[frame] else changed = true end
				nextEntries[#nextEntries + 1], nextByFrame[frame] = entry, entry
			end
		elseif frame.GetChildren then
			for _, child in ipairs({ frame:GetChildren() }) do Walk(child, depth + 1) end
		end
	end
	Walk(WorldMapFrame:GetCanvasContainer(), 0)
	changed = changed or #entries ~= #nextEntries
	entries, byFrame = nextEntries, nextByFrame
	if changed then ns:Fire("ADDON_PINS_CHANGED") end
end

function AddonPins:Query(cont, minX, maxX, minY, maxY, callback)
	for _, entry in ipairs(entries) do
		if entry.c == cont and entry.x >= minX and entry.x <= maxX
			and entry.y >= minY and entry.y <= maxY and entry.source:IsVisible() then
			callback(entry)
		end
	end
end

-- Copy the displayed texture layers, including atlas crops, tint and composite
-- icons. The originals stay with their owners; continuous-mode copies take over
-- their drawing until the terrain layer closes.
CaptureAppearance = function(entry)
	local source = entry.source
	local viewScale = (WayfinderDetailView or WorldMapFrame:GetCanvasContainer()):GetEffectiveScale()
	local sourceScale = source:GetEffectiveScale() / viewScale
	local iconScale = ns:GetSetting("detailIconScale") or 1
	local w, h = source:GetSize()
	local zoomFade = IgnoreZoomFade(entry.frame)
	local displayScale = 1
	if zoomFade then
		local original = math.max(w, h) * sourceScale
		if original > 0 then displayScale = math.max(14, math.min(28, original)) / original end
		sourceScale = sourceScale * displayScale
	end
	local appearance = { w = w * sourceScale * iconScale, h = h * sourceScale * iconScale, layers = {} }
	local sx, sy = source:GetCenter()
	local function Copy(frame, depth)
		if depth > 2 or not frame:IsVisible() then return end
		for _, region in ipairs({ frame:GetRegions() }) do
			if region:IsObjectType("Texture") and region:IsShown() then
				local atlas, texture = region:GetAtlas(), region:GetTexture()
				local layer, sublevel = region:GetDrawLayer()
				local frameAlpha = EffectiveAlpha(frame)
				if zoomFade and frameAlpha <= 0 then frameAlpha = 1 end
				local alpha = region:GetAlpha() * frameAlpha
				local r, g, b, a = region:GetVertexColor()
				if (atlas or texture) and layer ~= "HIGHLIGHT" and Number(alpha) and alpha > 0
					and Number(a) and a > 0 then
					if entry.service then appearance.service = true; return true end
					local ratio = region:GetEffectiveScale() / viewScale * displayScale
					local rw, rh = region:GetSize()
					local rx, ry = region:GetCenter()
					local dx = rx and sx and (rx * ratio - sx * sourceScale) or 0
					local dy = ry and sy and (ry * ratio - sy * sourceScale) or 0
					appearance.layers[#appearance.layers+1] = { atlas = atlas, texture = texture,
						layer = layer, sublevel = sublevel, tc = { region:GetTexCoord() }, r = r, g = g, b = b, a = a,
						alpha = alpha, blend = region:GetBlendMode(), desaturation = region:GetDesaturation(), rotation = region:GetRotation(),
						w = rw * ratio * iconScale, h = rh * ratio * iconScale, dx = dx * iconScale, dy = dy * iconScale }
				end
			end
		end
		for _, child in ipairs({ frame:GetChildren() }) do if Copy(child, depth + 1) then return true end end
	end
	Copy(source, 0)
	if appearance.service then
		appearance.w, appearance.h = 20 * iconScale, 20 * iconScale
		return appearance
	end
	if #appearance.layers > 0 then return appearance end
end

local STYLE_FIELDS = { "atlas", "texture", "layer", "sublevel", "r", "g", "b", "a", "alpha", "blend", "desaturation", "rotation", "w", "h", "dx", "dy" }
SameAppearance = function(a, b)
	if not a or not b or a.w ~= b.w or a.h ~= b.h or a.service ~= b.service or #a.layers ~= #b.layers then return false end
	for i, layer in ipairs(a.layers) do
		local other = b.layers[i]
		for _, key in ipairs(STYLE_FIELDS) do if layer[key] ~= other[key] then return false end end
		if #layer.tc ~= #other.tc then return false end
		for j, value in ipairs(layer.tc) do if value ~= other.tc[j] then return false end end
	end
	return true
end

function AddonPins:ApplyAppearance(pin, entry)
	local appearance = entry.appearance or CaptureAppearance(entry)
	if not appearance then return false end
	pin:SetSize(appearance.w, appearance.h)
	if appearance.service then
		-- Services use one canonical size and Blizzard artwork, regardless of
		-- the source addon's scale. Keep the source for its original tooltip.
		ns.Categories:ApplyIcon(pin.icon, entry.service)
		ns.Categories:ApplyIcon(pin.highlight, entry.service)
		pin.icon:SetAlpha(1); pin.icon:Show(); pin.highlight:Show()
		return true
	end
	pin.externalTextures = pin.externalTextures or {}
	for i, layer in ipairs(appearance.layers) do
		local copy = pin.externalTextures[i]
		if not copy then copy = pin:CreateTexture(); pin.externalTextures[i] = copy end
		copy:ClearAllPoints()
		copy:SetDrawLayer(layer.layer, layer.sublevel)
		if layer.atlas then copy:SetAtlas(layer.atlas) else copy:SetTexture(layer.texture) end
		copy:SetTexCoord(unpack(layer.tc))
		copy:SetVertexColor(layer.r, layer.g, layer.b, layer.a)
		copy:SetAlpha(layer.alpha)
		copy:SetBlendMode(layer.blend)
		copy:SetDesaturation(layer.desaturation)
		copy:SetRotation(layer.rotation)
		copy:SetSize(layer.w, layer.h)
		copy:SetPoint("CENTER", pin, "CENTER", layer.dx, layer.dy)
		copy:Show()
	end
	for i = #appearance.layers + 1, #pin.externalTextures do pin.externalTextures[i]:Hide() end
	return true
end

local function FocusPin()
	local container = WorldMapFrame:GetCanvasContainer()
	for _, focus in ipairs(GetMouseFoci()) do
		local frame, entry = focus, nil
		for _ = 1, 12 do
			if not frame or IsOwn(frame) then break end
			if frame == container then return entry end
			entry = TryRead(frame) or entry
			frame = frame.GetParent and frame:GetParent()
		end
	end
end

function AddonPins:OnLogin()
	EventUtil.ContinueOnAddOnLoaded("Blizzard_WorldMap", function()
		local function Refresh() self:RequestRefresh() end
		for _, method in ipairs({ "AcquirePin", "RemoveAllPinsByTemplate" }) do
			hooksecurefunc(WorldMapFrame, method, function(_, template)
				if template ~= "WayfinderMapPinTemplate" then Refresh() end
			end)
		end
		hooksecurefunc(WorldMapFrame, "OnMapChanged", Refresh)
		WorldMapFrame:HookScript("OnShow", Refresh)
		ns:On("SETTING_CHANGED", Refresh)
		ns:On("QUEST_AVAILABILITY_CHANGED", Refresh)
		ns:On("QUEST_TURN_INS_CHANGED", Refresh)
		-- Global events also see clicks consumed by Buttons which only registered
		-- left/right clicks, without changing another addon's click handlers.
		local pressed
		ns:RegisterEvent("GLOBAL_MOUSE_DOWN", function(_, button)
			if button ~= "MiddleButton" then return end
			pressed = nil
			if WorldMapFrame:IsShown() and not ns.DetailView:IsActive() then pressed = FocusPin() end
		end)
		ns:RegisterEvent("GLOBAL_MOUSE_UP", function(_, button)
			if button ~= "MiddleButton" then return end
			local entry = pressed
			pressed = nil
			if not entry or not WorldMapFrame:IsShown() or ns.DetailView:IsActive() then return end
			local released = FocusPin()
			if released and released.frame == entry.frame then
				self:NavigateTo(entry)
			end
		end)
		C_Timer.NewTicker(0.25, function()
			if WorldMapFrame:IsShown() and (ns.DetailView:IsActive() or ns.DetailView:IsFollowingMap()) then self:Refresh() end
		end)
	end)
end
