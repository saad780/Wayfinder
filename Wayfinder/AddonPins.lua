-- Carry other addons' displayed world-map markers into the terrain detail view.
-- Read the live frames rather than importing addon databases or moving their pins.
local _, ns = ...
local AddonPins = ns:NewModule("AddonPins")
local entries = {}

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

local function ReadPin(frame)
	if IsOwn(frame) or not frame:IsVisible() then return nil end
	local mapID = WorldMapFrame:GetMapID()
	local x, y
	-- Native MapCanvas pins and the HBD wrappers used by Questie/HandyNotes.
	if frame.GetPosition and frame.GetMap then
		x, y = frame:GetPosition()
		local map = frame:GetMap()
		if map and map.GetMapID then mapID = map:GetMapID() end
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
	local source = frame
	if frame.icon and frame.icon.IsObjectType and frame.icon:IsObjectType("Frame") then
		source = frame.icon -- HBD's wrapper has no art or dimensions of its own.
	end
	if not source:IsVisible() then return nil end
	local alpha = source:GetEffectiveAlpha()
	if not Number(alpha) or alpha <= 0 then return nil end
	local w, h = source:GetSize()
	if not Number(w) or not Number(h) or w <= 0 or h <= 0 or w > 128 or h > 128 then return nil end
	return { frame = frame, source = source, c = c, x = wx, y = wy, m = mapID, n = Label(source) }
end

-- Some third-party pins contain restricted values or are briefly half released.
-- One unreadable pin must not interrupt the rest of the map.
local function TryRead(frame)
	local ok, entry = pcall(ReadPin, frame)
	return ok and entry or nil
end

function AddonPins:NavigateTo(entry)
	local current = TryRead(entry.frame)
	if not current or current.source ~= entry.source or current.m ~= entry.m
		or current.x ~= entry.x or current.y ~= entry.y then return false end
	ns.Navigation:SetWaypoint(current.c, current.x, current.y, current.n, current.m)
	return true
end

function AddonPins:Refresh()
	wipe(entries)
	local function Walk(frame, depth)
		if depth > 4 or IsOwn(frame) or not frame:IsVisible() then return end
		local entry = TryRead(frame)
		if entry then
			entries[#entries + 1] = entry
		elseif frame.GetChildren then
			for _, child in ipairs({ frame:GetChildren() }) do Walk(child, depth + 1) end
		end
	end
	Walk(WorldMapFrame:GetCanvasContainer(), 0)
	ns:Fire("ADDON_PINS_CHANGED")
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
-- icons. The originals stay with their owners and retain all normal interactions.
function AddonPins:ApplyAppearance(pin, entry)
	local source = entry.source
	local viewScale = pin:GetEffectiveScale()
	local sourceScale = source:GetEffectiveScale() / viewScale
	local iconScale = ns:GetSetting("detailIconScale") or 1
	local w, h = source:GetSize()
	pin:SetSize(w * sourceScale * iconScale, h * sourceScale * iconScale)
	pin.externalTextures = pin.externalTextures or {}
	local used = 0
	local sx, sy = source:GetCenter()
	local function Copy(frame, depth)
		if depth > 2 or not frame:IsVisible() then return end
		for _, region in ipairs({ frame:GetRegions() }) do
			if region:IsObjectType("Texture") and region:IsShown() then
				local atlas, texture = region:GetAtlas(), region:GetTexture()
				local layer, sublevel = region:GetDrawLayer()
				local alpha = region:GetAlpha() * frame:GetEffectiveAlpha()
				local r, g, b, a = region:GetVertexColor()
				if (atlas or texture) and layer ~= "HIGHLIGHT" and Number(alpha) and alpha > 0
					and Number(a) and a > 0 then
					used = used + 1
					local copy = pin.externalTextures[used]
					if not copy then
						copy = pin:CreateTexture()
						pin.externalTextures[used] = copy
					end
					copy:ClearAllPoints()
					copy:SetDrawLayer(layer, sublevel)
					if atlas then copy:SetAtlas(atlas) else copy:SetTexture(texture) end
					copy:SetTexCoord(region:GetTexCoord())
					copy:SetVertexColor(r, g, b, a)
					copy:SetAlpha(alpha)
					copy:SetBlendMode(region:GetBlendMode())
					copy:SetDesaturation(region:GetDesaturation())
					copy:SetRotation(region:GetRotation())
					local ratio = region:GetEffectiveScale() / viewScale
					local rw, rh = region:GetSize()
					copy:SetSize(rw * ratio * iconScale, rh * ratio * iconScale)
					local rx, ry = region:GetCenter()
					local dx = rx and sx and (rx * ratio - sx * sourceScale) or 0
					local dy = ry and sy and (ry * ratio - sy * sourceScale) or 0
					copy:SetPoint("CENTER", pin, "CENTER", dx * iconScale, dy * iconScale)
					copy:Show()
				end
			end
		end
		for _, child in ipairs({ frame:GetChildren() }) do Copy(child, depth + 1) end
	end
	local ok = pcall(Copy, source, 0)
	for i = used + 1, #pin.externalTextures do pin.externalTextures[i]:Hide() end
	return ok and used > 0
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
		C_Timer.NewTicker(0.5, function()
			if WorldMapFrame:IsShown() and ns.DetailView:IsActive() then self:Refresh() end
		end)
	end)
end
