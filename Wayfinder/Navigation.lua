-- Getting around: a "show my location" button on the map, middle-click waypoints,
-- and a floating arrow that points the way to the waypoint.
local _, ns = ...

local Navigation = ns:NewModule("Navigation")

local MEDIA = "Interface\\AddOns\\Wayfinder\\Media\\"
local NEAR_YARDS = 40      -- arrow turns green inside this distance
local ARRIVE_YARDS = 10    -- close enough to count as arrived
local CYAN = { 0.35, 0.84, 1 }
local GREEN = { 0.45, 0.92, 0.45 }

local sqrt, atan2, min, max = math.sqrt, math.atan2, math.min, math.max

local current -- the waypoint: a location record { waypoint, c, x, y, m, n, where, cats }

local function Sound(name)
	if SOUNDKIT and SOUNDKIT[name] then
		PlaySound(SOUNDKIT[name])
	end
end

---------------------------------------------------------------------------
-- Describing a place
---------------------------------------------------------------------------
-- "Elwynn Forest 42.1, 65.3" for a world point. Uses the zone the game assigns to
-- the spot, or the hint map when the game only names the continent.
function ns.DescribeLocation(cont, wx, wy, hintMapID)
	local ok, mapID = pcall(C_Map.GetMapPosFromWorldPos, cont, CreateVector2D(wx, wy))
	local info = ok and mapID and C_Map.GetMapInfo(mapID)
	if not (info and info.mapType >= Enum.UIMapType.Zone) then
		mapID = hintMapID
		info = mapID and C_Map.GetMapInfo(mapID)
	end
	local rect = mapID and ns.GetMapRect(mapID)
	if info and rect and rect.cont == cont then
		local x, y = ns.WorldToMapRect(rect, wx, wy)
		return ("%s %.1f, %.1f"):format(info.name, x * 100, y * 100), mapID
	end
	return UNKNOWN or "Unknown", hintMapID
end

---------------------------------------------------------------------------
-- The waypoint
---------------------------------------------------------------------------
function Navigation:GetWaypoint()
	return current
end

function Navigation:SetWaypoint(cont, wx, wy, label, mapID)
	local where, zone = ns.DescribeLocation(cont, wx, wy, mapID)
	current = { waypoint = true, c = cont, x = wx, y = wy, m = zone, n = label or where, where = where, cats = {} }
	ns.db.waypoints[ns:GetCharacterKey()] = current
	Sound("UI_MAP_WAYPOINT_CLICK_TO_PLACE")
	ns:Fire("WAYPOINT_CHANGED", current)
	self:RefreshArrow()
end

-- A waypoint at a normalized position on a uiMap.
function Navigation:SetWaypointOnMap(mapID, x, y, label)
	local cont, wx, wy = ns.MapToWorld(mapID, x, y)
	if not cont then
		ns.Print("Waypoints can't be placed on this map.")
		return false
	end
	self:SetWaypoint(cont, wx, wy, label, mapID)
	return true
end

-- A waypoint at a recorded location (vendor, mailbox...).
function Navigation:SetWaypointTo(rec, catID)
	local cat = catID and ns.CategoryByID[catID]
	self:SetWaypoint(rec.c, rec.x, rec.y, rec.n or (cat and cat.label), rec.m)
end

function Navigation:ClearWaypoint()
	if not current then
		return
	end
	current = nil
	ns.db.waypoints[ns:GetCharacterKey()] = nil
	Sound("UI_MAP_WAYPOINT_REMOVE")
	ns:Fire("WAYPOINT_CHANGED", nil)
	self:RefreshArrow()
end

-- What a middle-click on a map icon does: the waypoint itself is removed, anything
-- else becomes the waypoint.
function Navigation:ToggleWaypointAt(rec, catID)
	if rec.waypoint then
		self:ClearWaypoint()
	else
		self:SetWaypointTo(rec, catID)
	end
end

---------------------------------------------------------------------------
-- Copyable waypoint text, made clickable locally by the receiving addon
---------------------------------------------------------------------------
local function LinkLabel(label)
	-- Labels are display text, never hyperlink markup. Keep room for the payload
	-- in a chat message, without cutting a UTF-8 character in half.
	label = (label or "Waypoint"):gsub("|", ""):gsub("[%c%[%]]", " ")
	local parts, length = {}, 0
	for char in label:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
		if length + #char > 80 then break end
		parts[#parts + 1], length = char, length + #char
	end
	return table.concat(parts)
end

function Navigation:GetWaypointLink(rec)
	rec = rec or current
	if not rec then return nil end
	local mapID = rec.m
	-- Detail-view points can lie outside the map it opened from. Use a parent
	-- map that contains the point so the link has valid normalized coordinates.
	for _ = 1, 12 do
		local rect = ns.GetMapRect(mapID)
		if rect and rect.cont == rec.c then
			local x, y = ns.WorldToMapRect(rect, rec.x, rec.y)
			if x >= 0 and x <= 1 and y >= 0 and y <= 1 then
				-- The visible text carries the coordinates too: clipboard copies and
				-- chat transports must not need to preserve hidden hyperlink markup.
				return ("[Wayfinder:%d:%d:%d:%s]"):format(
					mapID, math.floor(x * 10000 + 0.5), math.floor(y * 10000 + 0.5), LinkLabel(rec.n))
			end
		end
		local info = mapID and C_Map.GetMapInfo(mapID)
		mapID = info and info.parentMapID
		if not mapID or mapID == 0 then break end
	end
	return nil
end

local function ValidPosition(mapID, x, y)
	mapID, x, y = tonumber(mapID), tonumber(x), tonumber(y)
	if not mapID or not x or not y or mapID < 1 or mapID > 2147483647
		or x < 0 or x > 10000 or y < 0 or y > 10000 then return nil end
	if not C_Map.GetMapInfo(mapID) or not ns.GetMapRect(mapID) then return nil end
	return mapID, x, y
end

local function ParseShare(text)
	if type(text) ~= "string" or #text > 128 then return nil end
	local mapID, x, y, label = text:match("^%[Wayfinder:(%d+):(%d+):(%d+):([^|%c%[%]]*)%]$")
	mapID, x, y = ValidPosition(mapID, x, y)
	if not mapID or #label > 80 then return nil end
	return mapID, x, y, label
end

-- A message filter changes only the local rendering. The wire/clipboard format
-- remains ordinary text, and receiving a message never creates a waypoint.
function Navigation:FormatWaypointMessage(message)
	if not ns.Readable(message) or type(message) ~= "string" then return message end
	local function Decorate(plain)
		return (plain:gsub("%[Wayfinder:[^%]]*%]", function(token)
			local mapID, x, y, label = ParseShare(token)
			if not mapID then return token end
			return ("|cffffff00|Hwayfinder:%d:%d:%d:%s|h%s|h|r"):format(mapID, x, y, label, token)
		end))
	end
	-- Don't nest links if another filter (or another chat window) already
	-- formatted the token, or if it appears in an unrelated hyperlink.
	local parts, cursor = {}, 1
	while true do
		local first, last = message:find("|H[^|]*|h.-|h", cursor)
		if not first then
			parts[#parts + 1] = Decorate(message:sub(cursor))
			break
		end
		parts[#parts + 1] = Decorate(message:sub(cursor, first - 1))
		parts[#parts + 1] = message:sub(first, last)
		cursor = last + 1
	end
	return table.concat(parts)
end

function Navigation:ImportWaypointShare(text)
	local mapID, x, y, label = ParseShare(text)
	if not mapID then return false end
	return self:SetWaypointOnMap(mapID, x / 10000, y / 10000, label ~= "" and label or nil)
end

function Navigation:CopyWaypoint(rec)
	local link = self:GetWaypointLink(rec)
	if not link then
		ns.Print(current and "This waypoint can't be shared on a map." or "Set a waypoint first.")
		return false
	end
	-- Insert into the current draft (and its selected channel/whisper), or open
	-- chat with the link ready to send. The player chooses when to send it.
	if not ChatFrameUtil.InsertLink(link) then
		ChatFrameUtil.OpenChat(link)
	end
	return true
end

function Navigation:ReceiveWaypointLink(link, text, button)
	-- Modified clicks retain the game's normal copy/dress-up behavior.
	if button ~= "LeftButton" or IsModifiedClick() or type(link) ~= "string" or #link > 128 then
		return false
	end
	local share = link:match("^wayfinder:(.*)$")
	if share then
		return self:ImportWaypointShare("[Wayfinder:" .. share .. "]")
	end
	-- Continue to accept standard game map-pin links and 1.3.1's links.
	local mapID, x, y = link:match("^worldmap:(%d+):(%d+):(%d+)$")
	mapID, x, y = ValidPosition(mapID, x, y)
	if not mapID then return false end
	local label = type(text) == "string" and text:match("|h%[Wayfinder: (.-)%]|h")
	label = label and LinkLabel(label)
	return self:SetWaypointOnMap(mapID, x / 10000, y / 10000, label ~= "" and label or nil)
end

---------------------------------------------------------------------------
-- The arrow
---------------------------------------------------------------------------
local arrow
local ARROW_FRAMES, ARROW_COLUMNS, ARROW_ROWS = 128, 16, 8
local TURN = 2 * math.pi

local function ShowBearing(angle)
	-- Projected facets keep a fixed camera/light; rotate by selecting a yaw frame.
	local index = math.floor((angle % TURN) / TURN * ARROW_FRAMES + 0.5) % ARROW_FRAMES
	arrow.bearingFrame = index
	if arrow.useAtlas then
		if arrow.drawnFrame ~= index then
			local column, row = index % ARROW_COLUMNS, math.floor(index / ARROW_COLUMNS)
			arrow.head:SetTexCoord(column / ARROW_COLUMNS, (column + 1) / ARROW_COLUMNS,
				row / ARROW_ROWS, (row + 1) / ARROW_ROWS)
			arrow.drawnFrame = index
		end
	else
		-- A running client may not see newly installed texture files until restarted.
		arrow.head:SetRotation(angle)
	end
end

local function FormatDistance(yards)
	if yards >= 10000 then
		return ("%.1fk yd"):format(yards / 1000)
	end
	return ("%d yd"):format(yards + 0.5)
end

local function Tint(colour)
	arrow.head:SetVertexColor(colour[1], colour[2], colour[3])
	arrow.distance:SetTextColor(colour[1], colour[2], colour[3])
end

-- Points the arrow from the player toward the waypoint.
function Navigation:UpdateArrow()
	if not current then
		return
	end
	arrow.label:SetText(current.n)
	local cont, wx, wy = ns.GetPlayerWorld()
	if not cont then
		arrow.head:Hide()
		arrow.distance:SetText("?")
		Tint(CYAN)
		return
	end
	if cont ~= current.c then
		arrow.head:Hide()
		arrow.distance:SetText("Far away")
		arrow.label:SetText(current.n .. " (another continent)")
		Tint(CYAN)
		return
	end
	local dx, dy = current.x - wx, current.y - wy -- yards north, yards west
	local distance = sqrt(dx * dx + dy * dy)
	if distance <= ARRIVE_YARDS and ns:GetSetting("clearOnArrival") then
		ns.Print("Arrived at " .. current.n .. ".")
		Sound("MAP_PING")
		self:ClearWaypoint()
		return
	end
	-- Both bearing and player facing count counter-clockwise from north.
	ShowBearing(atan2(dy, dx) - (GetPlayerFacing() or 0))
	arrow.head:Show()
	arrow.distance:SetText(FormatDistance(distance))
	Tint(distance <= NEAR_YARDS and GREEN or CYAN)
end

local function CreateArrow()
	local f = CreateFrame("Button", "WayfinderArrow", UIParent)
	f:SetSize(130, 128)
	f:SetFrameStrata("MEDIUM")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:RegisterForClicks("RightButtonUp")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relativePoint, x, y = self:GetPoint()
		if point then
			ns.db.arrowPosition = { point, relativePoint, x, y }
		end
	end)
	f:SetScript("OnClick", function(_, button)
		if button == "RightButton" then
			Navigation:ClearWaypoint()
		end
	end)
	f:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText(current and current.n or "Wayfinder", 1, 0.82, 0)
		if current and current.where and current.where ~= current.n then
			GameTooltip:AddLine(current.where, 0.8, 0.8, 0.8)
		end
		GameTooltip:AddLine("Drag to move. Right-click to remove the waypoint.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	f:SetScript("OnLeave", GameTooltip_Hide)

	local hub = CreateFrame("Frame", nil, f)
	hub:SetSize(100, 90)
	hub:SetPoint("TOP")
	local function Layer(file, layer, subLevel, size)
		local tex = f:CreateTexture(nil, layer, nil, subLevel)
		local loaded = tex:SetTexture(MEDIA .. "Arrow\\" .. file)
		tex:SetSize(size, size)
		tex:SetPoint("CENTER", hub, "CENTER")
		return tex, loaded ~= false
	end
	f.base = Layer("CompassBase", "BACKGROUND", 0, 100)
	f.head, f.useAtlas = Layer("NeedleAtlas", "ARTWORK", 0, 100)
	if not f.useAtlas then
		f.head:SetTexture(MEDIA .. "PlayerArrow")
		f.head:SetSize(64, 64)
		f.base:Hide()
		ns.Print("Restart the game to load the new compass artwork; a simple pointer is shown until then.")
	end

	local plate = CreateFrame("Frame", nil, f)
	plate:SetSize(124, 36)
	plate:SetPoint("TOP", hub, "BOTTOM", 0, 0)
	local background = plate:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	background:SetColorTexture(0.03, 0.06, 0.08, 0.9)
	for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" } }) do
		local line = plate:CreateTexture(nil, "BORDER")
		line:SetColorTexture(CYAN[1], CYAN[2], CYAN[3], 0.3)
		line:SetPoint(side[1])
		line:SetPoint(side[2])
		line:SetHeight(1)
	end
	f.distance = plate:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f.distance:SetPoint("TOP", 0, -2)
	f.label = plate:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.label:SetPoint("TOP", f.distance, "BOTTOM", 0, -1)
	f.label:SetWidth(118)
	f.label:SetWordWrap(false)

	local elapsedSince = 0
	f:SetScript("OnUpdate", function(_, elapsed)
		elapsedSince = elapsedSince + elapsed
		if elapsedSince >= 0.03 then
			elapsedSince = 0
			Navigation:UpdateArrow()
		end
	end)
	f:Hide()
	return f
end

function Navigation:PlaceArrow()
	arrow:ClearAllPoints()
	local position = ns.db.arrowPosition
	if position then
		arrow:SetPoint(position[1], UIParent, position[2], position[3], position[4])
	else
		arrow:SetPoint("TOP", UIParent, "TOP", 0, -140)
	end
	arrow:SetScale(ns:GetSetting("arrowScale") or 1)
end

function Navigation:RefreshArrow()
	if not arrow then
		return
	end
	if current and ns:GetSetting("showArrow") then
		arrow:Show()
		self:UpdateArrow()
	else
		arrow:Hide()
	end
end

---------------------------------------------------------------------------
-- The world map: middle-click and "show my location"
---------------------------------------------------------------------------
function Navigation:ShowPlayerOnMap()
	if ns.DetailView:IsActive() then
		if ns.DetailView:CenterOnPlayer() then
			return
		end
		ns.DetailView:Exit(true)
	end
	local mapID = (MapUtil and MapUtil.GetDisplayableMapForPlayer and MapUtil.GetDisplayableMapForPlayer())
		or C_Map.GetBestMapForUnit("player")
	if not mapID then
		return
	end
	if WorldMapFrame:GetMapID() ~= mapID then
		WorldMapFrame:SetMapID(mapID)
		return
	end
	-- Already on your map: if zoomed in, slide over to you.
	local position = C_Map.GetPlayerMapPosition(mapID, "player")
	if position and not WorldMapFrame:IsAtMinZoom() then
		local x, y = position:GetXY()
		local container = WorldMapFrame.ScrollContainer
		local minX, maxX, minY, maxY = container:CalculateScrollExtentsAtScale(container:GetCanvasScale())
		WorldMapFrame:PanTo(min(max(x, minX), maxX), min(max(y, minY), maxY))
	end
end

function Navigation:CreateLocateButton()
	local button = CreateFrame("Button", "WayfinderLocateButton", WorldMapFrame)
	button:SetSize(32, 32)
	button:SetFrameStrata("HIGH")
	-- Forever puts Blizzard's map pin button in the top-left corner; sit beside it.
	local pinButton = WorldMapFrame.WorldMapTrackingPinButton
	if pinButton then
		button:SetPoint("LEFT", pinButton, "RIGHT", 2, 0)
	else
		button:SetPoint("TOPLEFT", WorldMapFrame:GetCanvasContainer(), "TOPLEFT", 3, 0)
	end

	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	background:SetSize(25, 25)
	background:SetPoint("TOPLEFT", 3, -4)
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(MEDIA .. "Locate")
	icon:SetSize(20, 20)
	icon:SetPoint("TOPLEFT", 7, -6)
	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(54, 54)
	border:SetPoint("TOPLEFT")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")

	button:SetScript("OnMouseDown", function()
		icon:SetPoint("TOPLEFT", 8, -7)
	end)
	button:SetScript("OnMouseUp", function()
		icon:SetPoint("TOPLEFT", 7, -6)
	end)
	button:SetScript("OnClick", function()
		Navigation:ShowPlayerOnMap()
	end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Show my location")
		GameTooltip:AddLine("Middle-click anywhere on the map to set a waypoint.", 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	self.locateButton = button
end

function Navigation:HookWorldMap()
	local container = WorldMapFrame.ScrollContainer
	container:HookScript("OnMouseUp", function(_, button)
		if button ~= "MiddleButton" then
			return
		end
		local x, y = container:GetNormalizedCursorPosition()
		if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
			self:SetWaypointOnMap(WorldMapFrame:GetMapID(), x, y)
		end
	end)
	self:CreateLocateButton()
end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------
function Navigation:OnLogin()
	current = ns.db.waypoints[ns:GetCharacterKey()]
	arrow = CreateArrow()
	self.arrow = arrow
	self:PlaceArrow()
	self:RefreshArrow()
	-- Register our local link type so Blizzard won't try to show an item tooltip.
	LinkUtil.RegisterLinkHandler("wayfinder", function(link, text, _, context)
		if context.button == "LeftButton" and IsModifiedClick("CHATLINK") then
			-- Re-sharing uses the copyable token, never a custom link on the wire.
			local token = "[Wayfinder:" .. link:sub(11) .. "]"
			if ParseShare(token) then
				if not ChatFrameUtil.InsertLink(token) then ChatFrameUtil.OpenChat(token) end
			end
		else
			self:ReceiveWaypointLink(link, text, context.button)
		end
	end)
	local function ChatFilter(_, _, message, ...)
		return false, self:FormatWaypointMessage(message), ...
	end
	for _, event in ipairs({ "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
		"CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
		"CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_CHANNEL", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
		"CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM", "CHAT_MSG_COMMUNITIES_CHANNEL" }) do
		ChatFrameUtil.AddMessageEventFilter(event, ChatFilter)
	end
	-- Keep the game's handler intact for native map-pin links.
	hooksecurefunc("SetItemRef", function(link, text, button)
		if type(link) == "string" and link:match("^worldmap:") then
			self:ReceiveWaypointLink(link, text, button)
		end
	end)
	ns:On("SETTING_CHANGED", function(key)
		if key == "arrowScale" then
			arrow:SetScale(ns:GetSetting("arrowScale") or 1)
		elseif key == "showArrow" then
			self:RefreshArrow()
		end
	end)
	EventUtil.ContinueOnAddOnLoaded("Blizzard_WorldMap", function()
		self:HookWorldMap()
	end)
end
