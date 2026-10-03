-- A small stand-in for the WoW API, enough to load Wayfinder and drive its logic
-- outside the game. Frames accept any method call; the parts the addon depends on
-- (sizes, scripts, events, timers, C_Map geometry) behave like the real thing.

mock = { time = 1000, timers = {}, frames = {}, eventFrames = {}, errors = {} }

---------------------------------------------------------------------------
-- Lua/WoW globals
---------------------------------------------------------------------------
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
tinsert, tremove = table.insert, table.remove
format = string.format
function strsplit(sep, s)
	local out = {}
	local i = 1
	for piece in (s .. sep):gmatch("([^" .. sep .. "]*)" .. sep) do
		out[i] = piece
		i = i + 1
	end
	return unpack(out)
end
function GetTime() return mock.time end
function time() return 1700000000 end
function debugprofilestop() return os.clock() * 1000 end
function geterrorhandler() return function(err) table.insert(mock.errors, err) error(err, 0) end end
function securecallfunction(fn, ...)
	local results = { pcall(fn, ...) }
	if not results[1] then
		error(results[2], 0)
	end
	return unpack(results, 2)
end
function hooksecurefunc(tbl, name, hook)
	if type(tbl) == "string" then
		tbl, name, hook = _G, tbl, name
	end
	local original = tbl[name]
	tbl[name] = function(...)
		local r = { original(...) }
		hook(...)
		return unpack(r)
	end
end
function issecretvalue(v) return type(v) == "table" and v.__secret == true end
function canaccessvalue(v) return not issecretvalue(v) end
mock.SECRET = { __secret = true }
function InCombatLockdown() return mock.inCombat or false end
function IsShiftKeyDown() return mock.shift or false end
function IsModifiedClick() return mock.shift or mock.modifiedClick or false end
function IsMouseButtonDown(button) return mock.mouseDown == button end
function GetCursorPosition() return mock.cursorX or 500, mock.cursorY or 350 end
function GetPlayerFacing() return mock.facing or 0.5 end
function GetRealmName() return "TestRealm" end
function GetNormalizedRealmName() return "TestRealm" end
function UnitName(unit) if unit == "player" then return "Tester" end return mock.units[unit] and mock.units[unit].name end
function UnitClass() return "Mage", "MAGE" end
function UnitFactionGroup(unit) if unit == "player" then return "Alliance" end return mock.units[unit] and mock.units[unit].faction end
function UnitExists(unit) return unit == "player" or mock.units[unit] ~= nil end
function UnitIsPlayer(unit) return unit == "player" or (mock.units[unit] and mock.units[unit].isPlayer) or false end
function UnitPlayerControlled(unit) return mock.units[unit] and mock.units[unit].controlled or false end
function UnitGUID(unit) return mock.units[unit] and mock.units[unit].guid end
function UnitCreatureID(unit) return mock.units[unit] and mock.units[unit].npcID end
function CheckInteractDistance(unit, index)
	local d = mock.units[unit] and mock.units[unit].distance or 100
	if index == 3 then return d <= 10 end
	if index == 4 then return d <= 28 end
	return false
end
function CanMerchantRepair() return mock.canRepair or false end
function IsTradeskillTrainer() return mock.tradeskillTrainer or false end
function GetMerchantNumItems() return #(mock.merchantItems or {}) end
function GetMerchantItemLink(i) return mock.merchantItems[i] and mock.merchantItems[i].link end
function GetNumAvailableQuests() return 0 end
function GetNumActiveQuests() return 0 end
mock.units = {}
LEVEL = "Level"
MAILBOX = "Mailbox"
UNKNOWN = "Unknown"
YES, NO = "Yes", "No"
LOCALIZED_CLASS_NAMES_MALE = { WARRIOR = "Warrior", MAGE = "Mage", HUNTER = "Hunter", PRIEST = "Priest",
	ROGUE = "Rogue", DRUID = "Druid", PALADIN = "Paladin", SHAMAN = "Shaman", WARLOCK = "Warlock" }
LOCALIZED_CLASS_NAMES_FEMALE = LOCALIZED_CLASS_NAMES_MALE
SlashCmdList = {}
StaticPopupDialogs = {}
function StaticPopup_Show(which, a, b, data) mock.popup = { which = which, data = data } end
ChatFrameUtil = {}
function ChatFrameUtil.InsertLink(link)
	if not mock.chatActive then return false end
	mock.chatText = (mock.chatText or "") .. link
	return true
end
function ChatFrameUtil.OpenChat(text)
	mock.chatActive, mock.chatText = true, text
	mock.chatOpened = (mock.chatOpened or 0) + 1
end
function SetItemRef(link, text, button)
	mock.itemRef = { link = link, text = text, button = button }
end
function print(...) mock.printed = (mock.printed or "") .. table.concat({ ... }, " ") .. "\n" end

function Mixin(object, ...)
	for i = 1, select("#", ...) do
		for k, v in pairs((select(i, ...))) do
			object[k] = v
		end
	end
	return object
end
function CreateFromMixins(...) return Mixin({}, ...) end

function CreateVector2D(x, y)
	return {
		x = x, y = y,
		GetXY = function(self) return self.x, self.y end,
		SetXY = function(self, nx, ny) self.x, self.y = nx, ny end,
	}
end

Enum = {
	UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4, Micro = 5, Orphan = 6 },
	MinimapTrackingFilter = { Auctioneer = 1, Banker = 2, Battlemaster = 4, TaxiNode = 8, VenderFood = 16,
		Innkeeper = 32, Mailbox = 64, TrainerProfession = 128, VendorReagent = 256, Repair = 512,
		Stablemaster = 2048, TrainerClass = 8388608, VendorPoison = 1048576, VendorAmmo = 16777216 },
	PlayerInteractionType = { Gossip = 3, QuestGiver = 4, Merchant = 5, TaxiNode = 6, Trainer = 7,
		Banker = 8, MailInfo = 17, SpiritHealer = 18, Binder = 20, Auctioneer = 21, StableMaster = 22,
		BattleMaster = 23 },
	ItemClass = { Consumable = 0, Reagent = 5, Projectile = 6, Tradegoods = 7 },
	FlightPathFaction = { Neutral = 0, Horde = 1, Alliance = 2 },
}

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------
local Region = {}
Region.__index = function(self, key)
	local method = Region[key]
	if method then
		return method
	end
	-- Any API method not modelled is a harmless no-op; data fields stay nil, as on
	-- real frames.
	if type(key) == "string" and key:match("^%u") then
		return function() end
	end
end

local function NewRegion(kind, parent)
	local r = setmetatable({ kind = kind, parent = parent, shown = true, w = 0, h = 0, scale = 1,
		level = parent and (parent.level or 0) + 1 or 0, scripts = {}, points = {} }, Region)
	return r
end

function Region:SetSize(w, h) self.w, self.h = w, h end
function Region:SetWidth(w) self.w = w end
function Region:SetHeight(h) self.h = h end
function Region:GetSize()
	if self.allPoints and self.allPoints ~= true then return self.allPoints:GetSize() end
	return self.w, self.h
end
function Region:GetWidth() return (self:GetSize()) end
function Region:GetHeight() return select(2, self:GetSize()) end
function Region:SetAllPoints(other) self.allPoints = other or self.parent or true end
function Region:SetPoint(point, ...) self.points[point] = { ... } end
function Region:ClearAllPoints() self.points = {} end
function Region:Show() self.shown = true end
function Region:Hide() self.shown = false end
function Region:SetShown(v) self.shown = not not v end
function Region:IsShown() return self.shown end
function Region:IsVisible() return self.shown end
function Region:SetScale(s) assert(type(s) == "number" and s > 0, "bad scale") self.scale = s end
function Region:GetScale() return self.scale end
function Region:GetEffectiveScale() return 1 end
function Region:GetLeft() return 0 end
function Region:GetTop() return select(2, self:GetSize()) end
function Region:SetFrameLevel(l) assert(l >= 0 and l <= 10000, "bad frame level") self.level = l end
function Region:GetFrameLevel() return self.level end
function Region:SetScript(name, fn) self.scripts[name] = fn end
function Region:GetScript(name) return self.scripts[name] end
function Region:HookScript(name, fn)
	local old = self.scripts[name]
	self.scripts[name] = function(...) if old then old(...) end fn(...) end
end
function Region:RegisterEvent(event)
	mock.eventFrames[event] = mock.eventFrames[event] or {}
	table.insert(mock.eventFrames[event], self)
end
function Region:IsMouseOver() return mock.mouseOver == self end
function Region:SetTexture(t) self.texture = t; return true end
function Region:SetAtlas(a) self.atlas = a end
function Region:SetText(t) self.text = t end
function Region:SetFormattedText(f, ...) self.text = string.format(f, ...) end
function Region:GetText() return self.text end
function Region:SetVertexColor(r, g, b) self.vertex = { r, g, b } end
function Region:SetRotation(r) self.rotation = r end
function Region:SetColorTexture(r, g, b, a) self.texture = "color"; self.color = { r, g, b, a } end
function Region:SetAlpha(a) self.alpha = a end
function Region:SetTexCoord(...) self.texCoord = { ... } end
function Region:SetDesaturation(d) self.desaturation = d end
function Region:SetDrawLayer(layer, subLevel) self.layer, self.subLevel = layer, subLevel end
function Region:CreateTexture(name, layer, template, subLevel)
	local t = NewRegion("Texture", self)
	t.layer, t.subLevel = layer, subLevel
	local list = rawget(self, "textures") or {}
	rawset(self, "textures", list)
	table.insert(list, t)
	return t
end
function Region:CreateFontString() return NewRegion("FontString", self) end

function CreateFrame(kind, name, parent, template)
	local f = NewRegion(kind, parent)
	f.name, f.template = name, template
	if name then _G[name] = f end
	table.insert(mock.frames, f)
	return f
end

SOUNDKIT = { UI_MAP_WAYPOINT_CLICK_TO_PLACE = 1, UI_MAP_WAYPOINT_REMOVE = 2, MAP_PING = 3 }
function PlaySound(id) mock.sounds = mock.sounds or {}; table.insert(mock.sounds, id) end
MapUtil = { GetDisplayableMapForPlayer = function() return mock.playerMap end }
UIParent = CreateFrame("Frame", "UIParent")
UIParent:SetSize(1920, 1080)
GameTooltip = CreateFrame("GameTooltip", "GameTooltip")
function GameTooltip:AddLine(text) self.lines = self.lines or {}; table.insert(self.lines, text) end
function GameTooltip:SetText(text) self.lines = { text } end
function GameTooltip_Hide() end

function mock.Fire(event, ...)
	for _, frame in ipairs(mock.eventFrames[event] or {}) do
		local handler = frame.scripts.OnEvent
		if handler then handler(frame, event, ...) end
	end
end

---------------------------------------------------------------------------
-- Timers
---------------------------------------------------------------------------
C_Timer = {}
function C_Timer.After(delay, fn) table.insert(mock.timers, { at = mock.time + delay, fn = fn }) end
function C_Timer.NewTimer(delay, fn)
	local t = { at = mock.time + delay, fn = fn }
	function t:Cancel() self.cancelled = true end
	table.insert(mock.timers, t)
	return t
end
function C_Timer.NewTicker(interval, fn)
	local t = { at = mock.time + interval, fn = fn, interval = math.max(interval, 0.016) }
	function t:Cancel() self.cancelled = true end
	table.insert(mock.timers, t)
	return t
end
function mock.Advance(seconds, step)
	step = step or 0.05
	local target = mock.time + seconds
	while mock.time < target do
		mock.time = math.min(target, mock.time + step)
		local due = {}
		for i = #mock.timers, 1, -1 do
			local t = mock.timers[i]
			if t.cancelled then
				table.remove(mock.timers, i)
			elseif t.at <= mock.time then
				table.insert(due, t)
				if t.interval then t.at = mock.time + t.interval else table.remove(mock.timers, i) end
			end
		end
		for _, t in ipairs(due) do
			if not t.cancelled then t.fn(t) end
		end
		for _, f in ipairs(mock.frames) do
			if f.shown and f.scripts.OnUpdate then f.scripts.OnUpdate(f, step) end
		end
	end
end

---------------------------------------------------------------------------
-- Maps: a tiny Azeroth with real Forever map IDs and roughly real rectangles
---------------------------------------------------------------------------
-- rect: cont, top (wx at y=0), left (wy at x=0), width (yards, x), height (yards, y)
-- Values are Classic's real zone rectangles, taken from HereBeDragons' map data.
mock.maps = {
	[947] = { name = "Azeroth", mapType = 0, parent = 0 },
	[1415] = { name = "Eastern Kingdoms", mapType = 2, parent = 947, cont = 0, top = 11176.34, left = 18171.97, width = 40741.18, height = 27149.69 },
	[1429] = { name = "Elwynn Forest", mapType = 3, parent = 1415, cont = 0, top = -7939.58, left = 1535.42, width = 3470.83, height = 2314.58 },
	[1453] = { name = "Stormwind City", mapType = 3, parent = 1415, cont = 0, top = -7995.83, left = 1722.92, width = 1737.50, height = 1158.33 },
	[1414] = { name = "Kalimdor", mapType = 2, parent = 947, cont = 1, top = 12799.9, left = 17066.6, width = 36799.81, height = 24533.2 },
}
local function MapRect(id) local m = mock.maps[id]; return m and m.cont and m end

C_Map = {}
-- GetWorldPosFromMapPos returns a vector whose x is north (wx) and y is west (wy).
local function WorldVector(wx, wy) return CreateVector2D(wx, wy) end
function C_Map.GetWorldPosFromMapPos(mapID, pos)
	local m = MapRect(mapID)
	if not m then return nil end
	local x, y = pos:GetXY()
	return m.cont, WorldVector(m.top - y * m.height, m.left - x * m.width)
end
function C_Map.GetMapPosFromWorldPos(cont, vec)
	local wx, wy = vec:GetXY()
	local best, bestArea
	for id, m in pairs(mock.maps) do
		if m.cont == cont and m.mapType >= 3 then
			local x, y = (m.left - wy) / m.width, (m.top - wx) / m.height
			if x >= 0 and x <= 1 and y >= 0 and y <= 1 and (not bestArea or m.width * m.height < bestArea) then
				best, bestArea = id, m.width * m.height
			end
		end
	end
	if best then
		local m = mock.maps[best]
		return best, CreateVector2D((m.left - wy) / m.width, (m.top - wx) / m.height)
	end
end
function C_Map.GetMapInfo(id)
	local m = mock.maps[id]
	return m and { mapID = id, name = m.name, mapType = m.mapType, parentMapID = m.parent }
end
function C_Map.GetMapChildrenInfo(root, mapType, allDescendants)
	local out = {}
	for id, m in pairs(mock.maps) do
		if (not mapType or m.mapType == mapType) and id ~= root then
			table.insert(out, { mapID = id, name = m.name, mapType = m.mapType })
		end
	end
	return out
end
function C_Map.GetFallbackWorldMapID() return 947 end
function C_Map.IsCityMap(id) return mock.maps[id] ~= nil and mock.maps[id].isCity == true end
mock.playerMap, mock.playerX, mock.playerY = 1429, 0.42, 0.65
function C_Map.GetBestMapForUnit() return mock.playerMap end
function C_Map.GetPlayerMapPosition(mapID, unit)
	if mapID ~= mock.playerMap then return nil end
	return CreateVector2D(mock.playerX, mock.playerY)
end
function C_Map.GetMapArtLayers()
	return { { layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256, minScale = 1, maxScale = 1, additionalZoomSteps = 0 } }
end
function C_Map.GetMapArtLayerTextures() local t = {} for i = 1, 12 do t[i] = 100000 + i end return t end

C_MapExplorationInfo = {}
mock.exploredBox = { 0.3, 0.6, 0.5, 0.8 } -- x0, x1, y0, y1 on Elwynn: Goldshire-ish
function C_MapExplorationInfo.GetExploredAreaIDsAtPosition(mapID, pos)
	local x, y = pos:GetXY()
	local b = mock.exploredBox
	if mapID == 1429 and x >= b[1] and x <= b[2] and y >= b[3] and y <= b[4] then
		return { 87 }
	end
end
function C_MapExplorationInfo.GetExploredMapTextures()
	return { { textureWidth = 300, textureHeight = 200, offsetX = 100, offsetY = 150, isShownByMouseOver = false,
		fileDataIDs = { 9001, 9002 } } }
end

C_Minimap = {}
function C_Minimap.GetNumTrackingTypes() return 2 end
function C_Minimap.GetTrackingFilter(i) return { filterID = i == 1 and 64 or 2 } end
function C_Minimap.GetTrackingInfo(i) return { texture = i == 1 and 136460 or 136453, name = "x" } end
function C_Minimap.GetViewRadius() return 120 end

C_Texture = {}
local atlases = { QuestNormal = true, TaxiNode_Alliance = true, TaxiNode_Horde = true, TaxiNode_Neutral = true, ["UI-WorldMapArrow"] = true }
function C_Texture.GetAtlasInfo(a) return atlases[a] and { width = 16, height = 16 } or nil end

C_AddOns = { GetAddOnMetadata = function() return "1.0.0" end }
C_TooltipInfo = {}
function C_TooltipInfo.GetUnit(unit)
	local u = mock.units[unit]
	if not u then return nil end
	local lines = { { leftText = u.name } }
	if u.title then table.insert(lines, { leftText = u.title }) end
	table.insert(lines, { leftText = "Level 30" })
	return { lines = lines }
end
C_Item = {}
function C_Item.GetItemInfoInstant(link)
	for _, item in ipairs(mock.merchantItems or {}) do
		if item.link == link then return 1, nil, nil, nil, nil, item.classID, item.subClassID end
	end
end
function C_Item.GetItemSpell(link)
	for _, item in ipairs(mock.merchantItems or {}) do
		if item.link == link then return item.spell end
	end
end
C_GossipInfo = { options = {} }
function C_GossipInfo.GetOptions() return C_GossipInfo.options end
function C_GossipInfo.GetNumAvailableQuests() return mock.gossipQuests or 0 end
function C_GossipInfo.GetNumActiveQuests() return 0 end
function C_GossipInfo.SelectOption() end
function C_GossipInfo.GetPoiForUiMapID() return mock.gossipPoi and 1 or nil end
function C_GossipInfo.GetPoiInfo() return mock.gossipPoi end
C_QuestLine = {}
function C_QuestLine.GetAvailableQuestLines() return { { questName = "A quest", x = 0.45, y = 0.62, isHidden = false } } end
function C_QuestLine.RequestQuestLinesForMap() end
C_TaxiMap = {}
function C_TaxiMap.GetTaxiNodesForMap(mapID)
	if mapID == 1453 then
		return { { nodeID = 2, name = "Stormwind, Elwynn", position = CreateVector2D(0.66, 0.62), faction = 2, isUndiscovered = false } }
	end
	return {}
end

EventUtil = { ContinueOnAddOnLoaded = function(_, fn) fn() end }
MenuUtil = {}
function MenuUtil.CreateContextMenu(owner, generator)
	local root = { items = {} }
	local function add(kind) return function(self, text, a, b) table.insert(self.items, { kind = kind, text = text, a = a, b = b }); return self end end
	root.CreateTitle, root.CreateCheckbox, root.CreateButton, root.CreateDivider = add("title"), add("checkbox"), add("button"), add("divider")
	root.CreateRadio = add("radio")
	generator(owner, root)
	mock.lastMenu = root
	return root
end

---------------------------------------------------------------------------
-- Settings panel
---------------------------------------------------------------------------
Settings = { VarType = { Boolean = "boolean", Number = "number" } }
function Settings.RegisterVerticalLayoutCategory(name)
	local layout = { items = {}, AddInitializer = function(self, i) table.insert(self.items, i) end }
	return { name = name, GetID = function() return 42 end }, layout
end
function Settings.RegisterAddOnSetting(cat, variable, key, tbl, varType, name, default)
	if tbl[key] == nil then tbl[key] = default end
	assert(type(tbl[key]) == varType, "setting " .. variable .. " has wrong type")
	local s = { tbl = tbl, key = key }
	function s:SetValueChangedCallback(cb) self.cb = cb end
	function s:SetValue(v) self.tbl[self.key] = v; if self.cb then self.cb(self, v) end end
	mock.settings = mock.settings or {}
	mock.settings[variable] = s
	return s
end
function Settings.CreateCheckbox() end
function Settings.CreateDropdown(cat, setting, getOptions)
	mock.dropdowns = mock.dropdowns or {}
	mock.dropdowns[setting.key] = getOptions()
end
function Settings.CreateControlTextContainer()
	local c = { data = {} }
	function c:Add(value, text) table.insert(self.data, { value = value, text = text }) end
	function c:GetData() return self.data end
	return c
end
function Settings.CreateSlider() end
function Settings.CreateSliderOptions() return { SetLabelFormatter = function() end } end
function Settings.RegisterAddOnCategory() end
function Settings.OpenToCategory(id) mock.openedSettings = id end
function CreateSettingsListSectionHeaderInitializer(t) return { header = t } end
function CreateSettingsButtonInitializer(...) return { button = { ... } } end
MinimalSliderWithSteppersMixin = { Label = { Right = 1 } }

---------------------------------------------------------------------------
-- World map
---------------------------------------------------------------------------
MapCanvasDataProviderMixin = {}
function MapCanvasDataProviderMixin:OnAdded(map) self.owningMap = map end
function MapCanvasDataProviderMixin:GetMap() return self.owningMap end
MapCanvasPinMixin = {}
function MapCanvasPinMixin:UseFrameLevelType(t) self.frameLevelType = t end
function MapCanvasPinMixin:SetScalingLimits() end
function MapCanvasPinMixin:SetPosition(x, y) self.normalizedX, self.normalizedY = x, y end

WorldMapFrame = CreateFrame("Frame", "WorldMapFrame")
WorldMapFrame:SetSize(1002, 668)
WorldMapFrame.mapID = 1429
WorldMapFrame.pins = {}
WorldMapFrame.providers = {}
local container = CreateFrame("ScrollFrame", nil, WorldMapFrame)
container:SetSize(1002, 668)
container.viewRect = { left = 0.3, right = 0.6, top = 0.5, bottom = 0.8 }
container.atMax = true
function container:GetViewRect() return self.viewRect end
function container:GetNormalizedCursorPosition() return mock.mapCursorX or 0.5, mock.mapCursorY or 0.5 end
function container:IsAtMaxZoom() return self.atMax end
function container:GetCanvasScale() return 2 end
function container:CalculateScrollExtentsAtScale() return 0.25, 0.75, 0.25, 0.75 end
WorldMapFrame.ScrollContainer = container
function WorldMapFrame:GetCanvasContainer() return self.ScrollContainer end
function WorldMapFrame:GetMapID() return self.mapID end
function WorldMapFrame:SetMapID(id) self.mapID = id end
function WorldMapFrame:IsAtMinZoom() return mock.atMinZoom ~= false end
WorldMapFrame.WorldMapTrackingPinButton = CreateFrame("Button", nil, WorldMapFrame)
function WorldMapFrame:AddDataProvider(p) table.insert(self.providers, p); p:OnAdded(self) end
function WorldMapFrame:GetPinFrameLevelsManager() return { maxLevel = 3100 } end
function WorldMapFrame:PanTo(x, y) self.pannedTo = { x, y } end
function WorldMapFrame:OnCanvasScaleChanged() end
function WorldMapFrame:OnMapChanged() end
function WorldMapFrame:RemoveAllPinsByTemplate(template)
	for i = #self.pins, 1, -1 do
		if self.pins[i].template == template then table.remove(self.pins, i) end
	end
end
function WorldMapFrame:AcquirePin(template, ...)
	local pin = CreateFrame("Frame", nil, self, template)
	Mixin(pin, _G[template:gsub("Template$", "Mixin")])
	pin.template = template
	pin.Icon = pin:CreateTexture()
	pin.Highlight = pin:CreateTexture()
	pin.GetMap = function() return self end
	pin:OnLoad()
	pin:OnAcquired(...)
	table.insert(self.pins, pin)
	return pin
end
function WorldMapFrame:RefreshProviders()
	for _, p in ipairs(self.providers) do p:RefreshAllData() end
end
