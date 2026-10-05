-- Settings panel (Esc > Options > AddOns > Wayfinder) and the world map's quick menu.
local _, ns = ...

local Options = ns:NewModule("Options")

ns.settingObjects = {} -- settings key (or "cats.<id>") -> Settings API object

---------------------------------------------------------------------------
-- Settings panel
---------------------------------------------------------------------------
local function Header(layout, text)
	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
end

local function Checkbox(category, key, label, tooltip)
	local setting = Settings.RegisterAddOnSetting(category, "WAYFINDER_" .. key, key, ns.db.settings,
		Settings.VarType.Boolean, label, ns.defaults[key])
	setting:SetValueChangedCallback(function(_, value)
		ns:Fire("SETTING_CHANGED", key, value)
	end)
	Settings.CreateCheckbox(category, setting, tooltip)
	ns.settingObjects[key] = setting
end

local function Slider(category, key, label, tooltip, minValue, maxValue, step, formatter)
	local setting = Settings.RegisterAddOnSetting(category, "WAYFINDER_" .. key, key, ns.db.settings,
		Settings.VarType.Number, label, ns.defaults[key])
	setting:SetValueChangedCallback(function(_, value)
		ns:Fire("SETTING_CHANGED", key, value)
	end)
	local options = Settings.CreateSliderOptions(minValue, maxValue, step)
	options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, formatter)
	Settings.CreateSlider(category, setting, options, tooltip)
	ns.settingObjects[key] = setting
end

-- choices: list of labels; the saved value is the chosen label's index.
local function Dropdown(category, key, label, tooltip, choices)
	local setting = Settings.RegisterAddOnSetting(category, "WAYFINDER_" .. key, key, ns.db.settings,
		Settings.VarType.Number, label, ns.defaults[key])
	setting:SetValueChangedCallback(function(_, value)
		ns:Fire("SETTING_CHANGED", key, value)
	end)
	local function GetOptions()
		local container = Settings.CreateControlTextContainer()
		for value, text in ipairs(choices) do
			container:Add(value, text)
		end
		return container:GetData()
	end
	Settings.CreateDropdown(category, setting, GetOptions, tooltip)
	ns.settingObjects[key] = setting
end

local function Button(layout, label, buttonText, onClick, tooltip)
	layout:AddInitializer(CreateSettingsButtonInitializer(label, buttonText, onClick, tooltip, true))
end

local function Percent(value)
	return ("%d%%"):format(value * 100 + 0.5)
end

function Options:BuildPanel()
	local category, layout = Settings.RegisterVerticalLayoutCategory("Wayfinder")
	self.category = category

	Header(layout, "Detail view")
	Checkbox(category, "detailEnabled", "Zoom past the map into minimap detail",
		"When the world map is zoomed in all the way, scrolling in again opens the detail view: the minimap's own terrain for the places you have explored.")
	Dropdown(category, "unexploredTerrain", "Unexplored terrain",
		"How the detail view draws terrain you have not explored yet.\n\nHidden: the zone's map art shows through.\nDarkened: the real terrain, dimmed.\nShown: the real terrain at full brightness.",
		ns.UNEXPLORED_NAMES)
	Slider(category, "unexploredBrightness", "Darkened terrain brightness",
		"How bright unexplored terrain is when it is darkened.", 0.15, 0.8, 0.05, Percent)
	Checkbox(category, "shareExploration", "Share exploration between characters",
		"Show terrain explored by any of your characters, not only this one.")
	Checkbox(category, "showLiveQuests", "Show available quests",
		"Mark quests you can pick up in the zone (the same quest markers the game shows).")
	Slider(category, "detailIconScale", "Detail view icon size", nil, 0.6, 2, 0.1, Percent)
	Slider(category, "revealRadius", "Reveal radius",
		"How far around you counts as explored. \"Minimap\" uses whatever your minimap currently shows.",
		0, 300, 10, function(value)
			return value == 0 and "Minimap" or ("%d yd"):format(value)
		end)

	Header(layout, "Waypoints")
	Checkbox(category, "showArrow", "Show the waypoint arrow",
		"Middle-click the map (or any icon) to set a waypoint; a floating arrow then points the way. Drag the arrow to move it, right-click it to remove the waypoint.")
	Checkbox(category, "clearOnArrival", "Remove the waypoint when you arrive")
	Slider(category, "arrowScale", "Arrow size", nil, 0.5, 2, 0.1, Percent)

	Header(layout, "World map")
	Checkbox(category, "showOnWorldMap", "Show icons on the world map")
	Checkbox(category, "showOnContinent", "Also show icons on continent maps")
	Slider(category, "iconScale", "World map icon size", nil, 0.6, 2, 0.1, Percent)

	Header(layout, "Icons")
	for _, cat in ipairs(ns.CategoryList) do
		local key = "cats." .. cat.id
		local setting = Settings.RegisterAddOnSetting(category, "WAYFINDER_CAT_" .. cat.id, cat.id, ns.db.settings.cats,
			Settings.VarType.Boolean, cat.label, true)
		setting:SetValueChangedCallback(function()
			ns:Fire("SETTING_CHANGED", "cats", cat.id)
		end)
		Settings.CreateCheckbox(category, setting)
		ns.settingObjects[key] = setting
	end

	Header(layout, "Discovery")
	Checkbox(category, "recordMouseover", "Record NPCs you mouse over",
		"Besides NPCs you talk to, remember service NPCs you mouse over or target nearby. Their position is approximate until you get closer or talk to them.")
	Checkbox(category, "showApproximate", "Show approximate locations",
		"Show NPCs whose position is only known roughly (drawn slightly faded).")
	Checkbox(category, "useSeedData", "Built-in town services",
		"Mailboxes, bankers, innkeepers, trainers and flight masters known in advance. Each one only appears once you have explored the spot, just as it would appear on your minimap.")
	Checkbox(category, "importExploration", "Import explored areas from the world map",
		"Count every area the world map shows as discovered as explored terrain, so characters who explored before installing Wayfinder start with their map filled in.")
	Checkbox(category, "showOtherFaction", "Show the other faction's NPCs")
	Checkbox(category, "showAllClassTrainers", "Show trainers for every class")

	Header(layout, "Data")
	Button(layout, "Explored areas", "Re-import", function()
		ns.Exploration:QueueImportAll(true)
		ns.Print("Re-importing explored areas from the world map in the background.")
	end, "Read the world map's discovered areas again for this character.")
	Button(layout, "Recorded locations", "Erase...", function()
		ns:ConfirmReset("pois")
	end, "Forget every location you have recorded (built-in ones come back).")
	Button(layout, "Exploration", "Erase...", function()
		ns:ConfirmReset("exploration")
	end, "Forget this character's explored terrain.")

	Settings.RegisterAddOnCategory(category)
end

function Options:Open()
	if self.category then
		Settings.OpenToCategory(self.category:GetID())
	end
end

---------------------------------------------------------------------------
-- World map button and menu
---------------------------------------------------------------------------
local function SetEverything(enabled)
	for _, cat in ipairs(ns.CategoryList) do
		ns:SetCategoryEnabled(cat.id, enabled)
	end
end

local function BuildMenu(_, root)
	root:CreateTitle("Wayfinder")
	for _, cat in ipairs(ns.CategoryList) do
		root:CreateCheckbox(cat.label, function()
			return ns:IsCategoryEnabled(cat.id)
		end, function()
			ns:SetCategoryEnabled(cat.id, not ns:IsCategoryEnabled(cat.id))
		end)
	end
	root:CreateButton("Show all", function()
		SetEverything(true)
	end)
	root:CreateButton("Hide all", function()
		SetEverything(false)
	end)
	root:CreateDivider()
	root:CreateCheckbox("Zoom into minimap detail", function()
		return ns:GetSetting("detailEnabled")
	end, function()
		ns:SetSetting("detailEnabled", not ns:GetSetting("detailEnabled"))
	end)
	root:CreateCheckbox("Icons on the world map", function()
		return ns:GetSetting("showOnWorldMap")
	end, function()
		ns:SetSetting("showOnWorldMap", not ns:GetSetting("showOnWorldMap"))
	end)
	root:CreateDivider()
	root:CreateTitle("Unexplored terrain")
	for mode, text in ipairs(ns.UNEXPLORED_NAMES) do
		root:CreateRadio(text, function()
			return ns:GetSetting("unexploredTerrain") == mode
		end, function()
			ns:SetSetting("unexploredTerrain", mode)
		end, mode)
	end
	root:CreateDivider()
	root:CreateButton("Open detail view", function()
		local opened, reason = ns.DetailView:EnterFromMap()
		if not opened then
			ns.Print(reason == "city" and "The detail view isn't available on city maps."
				or "No minimap terrain for this map.")
		end
	end)
	root:CreateButton("Settings...", function()
		Options:Open()
	end)
end

function Options:CreateMapButton()
	local button = CreateFrame("Button", "WayfinderMapButton", WorldMapFrame)
	button:SetSize(32, 32)
	button:SetFrameStrata("HIGH")
	-- Forever moves Blizzard's own map buttons away from this corner.
	button:SetPoint("TOPRIGHT", WorldMapFrame:GetCanvasContainer(), "TOPRIGHT", -6, -6)

	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	background:SetSize(25, 25)
	background:SetPoint("CENTER")

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
	icon:SetSize(20, 20)
	icon:SetPoint("CENTER")
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	pcall(icon.SetMask, icon, "Interface\\CharacterFrame\\TempPortraitAlphaMask")

	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(54, 54)
	border:SetPoint("TOPLEFT")

	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:SetScript("OnClick", function(self)
		MenuUtil.CreateContextMenu(self, BuildMenu)
	end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("Wayfinder")
		GameTooltip:AddLine("Choose which icons to show.", 1, 1, 1)
		GameTooltip:AddLine("Zoom all the way in, then keep scrolling to see minimap detail.", 0.7, 0.7, 0.7, true)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	self.mapButton = button
end

function Options:OnLogin()
	self:BuildPanel()
	EventUtil.ContinueOnAddOnLoaded("Blizzard_WorldMap", function()
		self:CreateMapButton()
	end)
end
