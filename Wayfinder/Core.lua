-- Wayfinder: core namespace, events, saved variables and slash commands.
local ADDON_NAME, ns = ...

Wayfinder = ns -- global handle for /dump and other addons

ns.name = ADDON_NAME
ns.version = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "dev"

---------------------------------------------------------------------------
-- Printing
---------------------------------------------------------------------------
local PREFIX = "|cff4fc3f7Wayfinder|r:"

function ns.Print(...)
	print(PREFIX, ...)
end

function ns.Debug(...)
	if ns.db and ns.db.settings.debug then
		print("|cff888888Wayfinder debug:|r", ...)
	end
end

---------------------------------------------------------------------------
-- Secret values (12.x combat / identity restrictions)
-- Anything read from a unit can come back as a secret value that addon code
-- may not inspect. Never compare, index or concatenate such a value.
---------------------------------------------------------------------------
local issecretvalue = issecretvalue
local canaccessvalue = canaccessvalue

function ns.Readable(value)
	if value == nil then
		return false
	end
	if issecretvalue and issecretvalue(value) then
		return false
	end
	if canaccessvalue and not canaccessvalue(value) then
		return false
	end
	return true
end

---------------------------------------------------------------------------
-- Event dispatch
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local eventHandlers = {}

function ns:RegisterEvent(event, handler)
	local list = eventHandlers[event]
	if not list then
		list = {}
		eventHandlers[event] = list
		eventFrame:RegisterEvent(event)
	end
	list[#list + 1] = handler
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	local list = eventHandlers[event]
	if not list then
		return
	end
	for i = 1, #list do
		-- securecallfunction reports errors through the error handler without
		-- stopping the remaining handlers.
		securecallfunction(list[i], event, ...)
	end
end)

---------------------------------------------------------------------------
-- Internal messages between modules
---------------------------------------------------------------------------
local listeners = {}

function ns:On(message, handler)
	local list = listeners[message]
	if not list then
		list = {}
		listeners[message] = list
	end
	list[#list + 1] = handler
end

function ns:Fire(message, ...)
	local list = listeners[message]
	if not list then
		return
	end
	for i = 1, #list do
		securecallfunction(list[i], ...)
	end
end

---------------------------------------------------------------------------
-- Modules
---------------------------------------------------------------------------
local modules = {}

function ns:NewModule(name)
	local module = { name = name }
	modules[#modules + 1] = module
	ns[name] = module
	return module
end

---------------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------------
-- How the detail view draws terrain you have not explored.
ns.UNEXPLORED_HIDDEN = 1   -- not at all; the zone's map art shows through
ns.UNEXPLORED_DARKENED = 2 -- dimmed, like fog of war
ns.UNEXPLORED_SHOWN = 3    -- at full brightness
ns.UNEXPLORED_NAMES = { "Hidden", "Darkened", "Shown" }

ns.defaults = {
	-- category id -> enabled; filled in by Categories.lua
	cats = {},
	showOnWorldMap = true,       -- draw icons on the regular world map
	showOnContinent = false,     -- also on continent-level maps
	showOtherFaction = false,    -- show NPCs hostile to your faction
	showAllClassTrainers = false, -- otherwise only trainers for your class
	showApproximate = true,      -- NPCs only seen from a distance (mouseover)
	useSeedData = true,          -- reveal known town services as you explore
	recordMouseover = true,      -- record NPCs you mouse over, not only ones you talk to
	iconScale = 1.0,             -- world map icons
	detailIconScale = 1.0,       -- detail view icons
	detailEnabled = true,        -- zooming past the map's limit opens the detail view
	unexploredTerrain = ns.UNEXPLORED_DARKENED, -- one of the UNEXPLORED_* modes above
	unexploredBrightness = 0.4,  -- how bright darkened terrain is (0..1)
	shareExploration = false,    -- combine exploration from all your characters
	revealRadius = 0,            -- yards; 0 = whatever the minimap currently shows
	importExploration = true,    -- seed exploration from the world map's discovered areas
	showLiveQuests = true,       -- available-quest markers from the game in the detail view
	debug = false,
}

local function ApplyDefaults(target, defaults)
	for key, value in pairs(defaults) do
		if type(value) == "table" then
			if type(target[key]) ~= "table" then
				target[key] = {}
			end
			ApplyDefaults(target[key], value)
		elseif target[key] == nil then
			target[key] = value
		end
	end
end

local function InitializeDatabase()
	WayfinderDB = WayfinderDB or {}
	local db = WayfinderDB
	db.schema = db.schema or 1
	db.settings = db.settings or {}
	db.pois = db.pois or {}
	db.hidden = db.hidden or {}
	db.explored = db.explored or {}
	db.imported = db.imported or {}
	-- 1.0 had an on/off "show unexplored terrain" setting.
	if db.settings.revealAll ~= nil then
		if db.settings.revealAll == true and db.settings.unexploredTerrain == nil then
			db.settings.unexploredTerrain = ns.UNEXPLORED_SHOWN
		end
		db.settings.revealAll = nil
	end
	ApplyDefaults(db.settings, ns.defaults)
	ns.db = db
end

function ns:GetSetting(key)
	return self.db.settings[key]
end

function ns:SetSetting(key, value)
	if self.db.settings[key] == value then
		return
	end
	-- Go through the options panel's setting object when there is one, so the panel
	-- shows the new value; its change callback fires SETTING_CHANGED.
	local object = self.settingObjects and self.settingObjects[key]
	if object then
		object:SetValue(value)
		return
	end
	self.db.settings[key] = value
	self:Fire("SETTING_CHANGED", key, value)
end

function ns:IsCategoryEnabled(catID)
	return self.db.settings.cats[catID] ~= false
end

function ns:SetCategoryEnabled(catID, enabled)
	enabled = not not enabled
	if self:IsCategoryEnabled(catID) == enabled then
		return
	end
	local object = self.settingObjects and self.settingObjects["cats." .. catID]
	if object then
		object:SetValue(enabled)
		return
	end
	self.db.settings.cats[catID] = enabled
	self:Fire("SETTING_CHANGED", "cats", catID)
end

---------------------------------------------------------------------------
-- Player identity
---------------------------------------------------------------------------
function ns:GetCharacterKey()
	if not self.charKey then
		local name = UnitName("player")
		local realm = GetNormalizedRealmName and GetNormalizedRealmName() or GetRealmName()
		if name and realm and realm ~= "" then
			self.charKey = name .. "-" .. realm
		end
	end
	return self.charKey or "unknown"
end

function ns:GetPlayerFaction()
	-- 1 = Alliance, 2 = Horde, matching the seed data's convention.
	local faction = UnitFactionGroup("player")
	if faction == "Alliance" then
		return 1
	elseif faction == "Horde" then
		return 2
	end
	return 0
end

---------------------------------------------------------------------------
-- Startup
---------------------------------------------------------------------------
ns:RegisterEvent("ADDON_LOADED", function(_, name)
	if name ~= ADDON_NAME then
		return
	end
	InitializeDatabase()
	for _, module in ipairs(modules) do
		if module.OnInitialize then
			securecallfunction(module.OnInitialize, module)
		end
	end
end)

ns:RegisterEvent("PLAYER_LOGIN", function()
	ns:GetCharacterKey()
	ns.playerFaction = ns:GetPlayerFaction()
	ns.playerClass = select(2, UnitClass("player"))
	for _, module in ipairs(modules) do
		if module.OnLogin then
			securecallfunction(module.OnLogin, module)
		end
	end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function CountTable(t)
	local n = 0
	for _ in pairs(t) do
		n = n + 1
	end
	return n
end

local function PrintStats()
	local db = ns.db
	local byCat = {}
	for _, poi in pairs(db.pois) do
		for catID in pairs(poi.cats) do
			byCat[catID] = (byCat[catID] or 0) + 1
		end
	end
	ns.Print(("%d recorded locations, %d revealed built-in locations."):format(
		CountTable(db.pois), ns.Seeds and ns.Seeds:CountRevealed() or 0))
	for _, cat in ipairs(ns.CategoryList) do
		if byCat[cat.id] then
			print(("   %s: %d"):format(cat.label, byCat[cat.id]))
		end
	end
	local cells = ns.Exploration and ns.Exploration:CountExploredCells() or 0
	ns.Print(("Explored %.1f square miles of terrain (%d cells)."):format(
		cells * ns.CELL * ns.CELL / (1760 * 1760), cells))
end

local function HandleSlash(input)
	local command, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
	command = command:lower()
	if command == "" or command == "options" or command == "config" then
		ns.Options:Open()
	elseif command == "stats" then
		PrintStats()
	elseif command == "reveal" then
		local modes = { hide = ns.UNEXPLORED_HIDDEN, dim = ns.UNEXPLORED_DARKENED, show = ns.UNEXPLORED_SHOWN }
		local mode = modes[rest:lower()]
		if rest ~= "" and not mode then
			ns.Print("Usage: /wf reveal [hide|dim|show]")
			return
		end
		mode = mode or (ns:GetSetting("unexploredTerrain") % 3 + 1)
		ns:SetSetting("unexploredTerrain", mode)
		ns.Print("Unexplored terrain: " .. ns.UNEXPLORED_NAMES[mode] .. ".")
	elseif command == "show" or command == "hide" then
		local enable = command == "show"
		local matched = false
		for _, cat in ipairs(ns.CategoryList) do
			if rest == "all" or cat.id == rest or cat.label:lower() == rest:lower() then
				ns:SetCategoryEnabled(cat.id, enable)
				matched = true
			end
		end
		if not matched then
			ns.Print("Unknown category. Try one of:")
			for _, cat in ipairs(ns.CategoryList) do
				print("   " .. cat.id .. "  (" .. cat.label .. ")")
			end
		end
	elseif command == "here" then
		local cont, wx, wy, mapID, mx, my = ns.GetPlayerWorld()
		if cont then
			local col, row = ns.WorldToTile(wx, wy)
			ns.Print(("map %d (%.1f, %.1f) continent %d world %.1f, %.1f tile %d_%d"):format(
				mapID, mx * 100, my * 100, cont, wx, wy, col, row))
		else
			ns.Print("Position unavailable here.")
		end
	elseif command == "import" then
		ns.Exploration:QueueImportAll(true)
		ns.Print("Re-importing explored areas from the world map in the background.")
	elseif command == "debug" then
		ns:SetSetting("debug", not ns:GetSetting("debug"))
		ns.Print("Debug output " .. (ns:GetSetting("debug") and "on." or "off."))
	elseif command == "reset" then
		if not ns:ConfirmReset(rest:lower()) then
			ns.Print("Usage: /wf reset pois|exploration|all")
		end
	else
		ns.Print("Commands:")
		print("   /wf  - options")
		print("   /wf show|hide <category|all>")
		print("   /wf reveal [hide|dim|show]  - how unexplored terrain is drawn")
		print("   /wf stats  - what has been recorded")
		print("   /wf import  - re-read explored areas from the world map")
		print("   /wf reset pois|exploration|all")
	end
end

SLASH_WAYFINDER1 = "/wayfinder"
SLASH_WAYFINDER2 = "/wf"
SlashCmdList.WAYFINDER = HandleSlash

local RESET_LABELS = {
	pois = "every location you have recorded",
	exploration = "this character's explored terrain",
	all = "all recorded locations and explored terrain",
}

function ns:ConfirmReset(what)
	if not RESET_LABELS[what] then
		return false
	end
	StaticPopup_Show("WAYFINDER_RESET", RESET_LABELS[what], nil, what)
	return true
end

StaticPopupDialogs.WAYFINDER_RESET = {
	text = "Wayfinder: erase %s? This cannot be undone.",
	button1 = YES,
	button2 = NO,
	OnAccept = function(_, what)
		if what == "pois" or what == "all" then
			wipe(ns.db.pois)
			wipe(ns.db.hidden)
			ns.Database:Rebuild()
		end
		if what == "exploration" or what == "all" then
			wipe(ns.db.explored)
			wipe(ns.db.imported)
			ns.Exploration:Reset()
		end
		ns:Fire("DATA_CHANGED")
		ns.Print("Erased " .. (RESET_LABELS[what] or tostring(what)) .. ".")
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

-- Addon compartment (the minimap's addon list button)
function Wayfinder_OnAddonCompartmentClick()
	ns.Options:Open()
end

