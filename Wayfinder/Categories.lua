-- Icon categories, their icons, and classification of NPCs from their <Title>.
local _, ns = ...

local MEDIA = "Interface\\AddOns\\Wayfinder\\Media\\"
local TRACKING = "Interface\\Minimap\\Tracking\\"

-- Order matters: when a location belongs to several categories (an innkeeper is
-- also a food vendor) the first enabled one in this list picks the icon.
ns.CategoryList = {
	{ id = "flight", label = "Flight Masters", filter = "TaxiNode", path = TRACKING .. "FlightMaster" },
	{ id = "transport", label = "Boats, Zeppelins & Trams", media = "Boat" },
	{ id = "inn", label = "Innkeepers", filter = "Innkeeper", path = TRACKING .. "Innkeeper" },
	{ id = "bank", label = "Bankers", filter = "Banker", path = TRACKING .. "Banker" },
	{ id = "auction", label = "Auctioneers", filter = "Auctioneer", path = TRACKING .. "Auctioneer" },
	{ id = "mailbox", label = "Mailboxes", filter = "Mailbox", path = TRACKING .. "Mailbox" },
	{ id = "stable", label = "Stable Masters", filter = "Stablemaster", path = TRACKING .. "StableMaster" },
	{ id = "battlemaster", label = "Battlemasters", filter = "Battlemaster", path = TRACKING .. "BattleMaster" },
	{ id = "trainer_class", label = "Class Trainers", filter = "TrainerClass", path = TRACKING .. "Class" },
	{ id = "trainer_prof", label = "Profession Trainers", filter = "TrainerProfession", path = TRACKING .. "Profession" },
	{ id = "weaponmaster", label = "Weapon Masters", media = "WeaponMaster" },
	{ id = "quest", label = "Quest Givers", atlas = "QuestNormal", media = "Quest" },
	{ id = "repair", label = "Repair", filter = "Repair", path = TRACKING .. "Repair" },
	{ id = "poison", label = "Poisons", filter = "VendorPoison", path = TRACKING .. "Poisons" },
	{ id = "reagent", label = "Reagents", filter = "VendorReagent", path = TRACKING .. "Reagents" },
	{ id = "ammo", label = "Ammunition", filter = "VendorAmmo", path = TRACKING .. "Ammunition" },
	{ id = "food", label = "Food & Drink", filter = "VenderFood", path = TRACKING .. "Food" },
	{ id = "vendor", label = "Other Vendors", media = "Vendor" },
	{ id = "spirit", label = "Spirit Healers", media = "Spirit" },
}

ns.CategoryByID = {}
for index, cat in ipairs(ns.CategoryList) do
	cat.order = index
	ns.CategoryByID[cat.id] = cat
	ns.defaults.cats[cat.id] = true
end

local TRANSPORT_MEDIA = { boat = "Boat", zeppelin = "Zeppelin", tram = "Tram", portal = "Portal" }

---------------------------------------------------------------------------
-- Icons
---------------------------------------------------------------------------
local Categories = ns:NewModule("Categories")

local probe -- hidden texture used to check that a texture path exists

local function PathExists(path)
	if not probe then
		probe = UIParent:CreateTexture(nil, "BACKGROUND")
		probe:Hide()
	end
	local ok, loaded = pcall(probe.SetTexture, probe, path)
	probe:SetTexture(nil)
	return ok and loaded ~= false
end

local function AtlasExists(atlas)
	return atlas and C_Texture.GetAtlasInfo(atlas) ~= nil
end

function Categories:ResolveIcons()
	-- The minimap tracking menu's own icons, keyed by tracking filter.
	local trackingTextures = {}
	if C_Minimap and C_Minimap.GetNumTrackingTypes then
		for index = 1, C_Minimap.GetNumTrackingTypes() do
			local filter = C_Minimap.GetTrackingFilter(index)
			local info = C_Minimap.GetTrackingInfo(index)
			if filter and filter.filterID and info and info.texture then
				trackingTextures[filter.filterID] = info.texture
			end
		end
	end

	for _, cat in ipairs(ns.CategoryList) do
		local icon
		local filterID = cat.filter and Enum.MinimapTrackingFilter and Enum.MinimapTrackingFilter[cat.filter]
		if filterID and trackingTextures[filterID] then
			icon = { texture = trackingTextures[filterID] }
		elseif cat.atlas and AtlasExists(cat.atlas) then
			icon = { atlas = cat.atlas }
		elseif cat.path and PathExists(cat.path) then
			icon = { texture = cat.path }
		else
			icon = { texture = MEDIA .. (cat.media or "Generic") }
		end
		cat.icon = icon
	end

	self.flightAtlas = {
		[0] = AtlasExists("TaxiNode_Neutral") and "TaxiNode_Neutral" or nil,
		[1] = AtlasExists("TaxiNode_Alliance") and "TaxiNode_Alliance" or nil,
		[2] = AtlasExists("TaxiNode_Horde") and "TaxiNode_Horde" or nil,
	}
	self.questTurnInAtlas = AtlasExists("QuestTurnin") and "QuestTurnin" or nil
	self.playerArrowAtlas = AtlasExists("UI-WorldMapArrow") and "UI-WorldMapArrow" or nil
end

function Categories:OnLogin()
	self:ResolveIcons()
end

-- Applies a category icon (optionally specialised for a location) to a texture.
function Categories:ApplyIcon(texture, catID, poi)
	texture:SetTexCoord(0, 1, 0, 1)
	if catID == "waypoint" then
		texture:SetTexture(MEDIA .. "Waypoint")
		return
	end
	if catID == "transport" then
		texture:SetTexture(MEDIA .. (TRANSPORT_MEDIA[poi and poi.sub] or "Boat"))
		return
	end
	if catID == "flight" and poi and self.flightAtlas then
		local atlas = self.flightAtlas[poi.f or 0]
		if atlas then
			texture:SetAtlas(atlas)
			return
		end
	end
	local cat = ns.CategoryByID[catID]
	local icon = cat and cat.icon
	if not icon then
		texture:SetTexture(MEDIA .. "Generic")
	elseif icon.atlas then
		texture:SetAtlas(icon.atlas)
	else
		texture:SetTexture(icon.texture)
	end
end

function Categories:GetMediaPath(name)
	return MEDIA .. name
end

---------------------------------------------------------------------------
-- Which categories decide a location's icon / visibility
---------------------------------------------------------------------------
-- Returns the category whose icon a location should show, or nil if it should be
-- hidden: none of its categories enabled, hostile faction, a trainer for another
-- class, or only seen from a distance when approximate locations are off.
function Categories:GetVisibleCategory(rec)
	local settings = ns.db.settings
	local faction = rec.f
	local mine = ns.playerFaction
	if faction and faction ~= 0 and mine and mine ~= 0 and faction ~= mine and not settings.showOtherFaction then
		return nil
	end
	if not rec.seed and (rec.a or 0) > 20 and not settings.showApproximate then
		return nil
	end
	local best, bestOrder
	for catID in pairs(rec.cats) do
		local cat = ns.CategoryByID[catID]
		if cat and settings.cats[catID] ~= false and (not bestOrder or cat.order < bestOrder) then
			local otherClass = catID == "trainer_class" and rec.cls and rec.cls ~= ns.playerClass
			if not otherClass or settings.showAllClassTrainers then
				best, bestOrder = catID, cat.order
			end
		end
	end
	return best
end

---------------------------------------------------------------------------
-- Title classification
---------------------------------------------------------------------------
local function Words(list)
	local patterns = {}
	for i, word in ipairs(list) do
		-- %f frontier patterns give us whole-word matches ("ale" but not "sale").
		patterns[i] = "%f[%w]" .. word:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1") .. "%f[%W]"
	end
	return patterns
end

local function Matches(text, patterns)
	for i = 1, #patterns do
		if text:find(patterns[i]) then
			return true
		end
	end
	return false
end

local P = {
	flight = Words({ "flight master", "gryphon master", "wind rider master", "hippogryph master", "bat handler", "flightmaster" }),
	inn = Words({ "innkeeper" }),
	auction = Words({ "auctioneer" }),
	bank = Words({ "banker" }),
	stable = Words({ "stable master", "stablemaster" }),
	battlemaster = Words({ "battlemaster" }),
	transport = Words({ "zeppelin master", "dockmaster", "dock master", "harbormaster", "harbor master", "ferry", "tram" }),
	spirit = Words({ "spirit healer", "spirit guide" }),
	weaponmaster = Words({ "weapon master", "weapons master" }),
	trainer = Words({ "trainer", "instructor" }),
	riding = Words({ "riding" }),
	pet = Words({ "pet trainer" }),
	reagent = Words({ "reagent", "reagents" }),
	poison = Words({ "poison", "poisons" }),
	ammo = Words({ "ammunition", "arrows", "bullets", "bowyer", "gunsmith", "bow merchant", "gun merchant" }),
	food = Words({ "food", "drink", "drinks", "baker", "bread", "butcher", "meat", "cheese", "fruit",
		"mushroom", "mushrooms", "wine", "spirits", "bartender", "brewer", "brewmaster", "ale",
		"provisioner", "provisions", "grocer", "fish vendor", "chef" }),
	vendor = Words({ "merchant", "vendor", "supplies", "supplier", "goods", "seller", "trader", "tradesman",
		"armorer", "weaponsmith", "armorsmith", "outfitter", "clothier", "quartermaster", "shopkeeper",
		"peddler", "bags", "tabard", "general goods", "smith", "bowyer", "gunsmith", "fletcher" }),
}

local classByName -- lowercase localized class name -> class token

local function ClassFromTitle(lower)
	if not classByName then
		classByName = {}
		for _, names in ipairs({ LOCALIZED_CLASS_NAMES_MALE, LOCALIZED_CLASS_NAMES_FEMALE }) do
			if names then
				for token, name in pairs(names) do
					classByName[name:lower()] = token
				end
			end
		end
	end
	for name, token in pairs(classByName) do
		if lower:find("%f[%w]" .. name .. "%f[%W]") then
			return token
		end
	end
end

-- Returns a set of category ids for an NPC subtitle (without the angle brackets),
-- plus a class token for class trainers. Returns nil when the title names no
-- service we track.
function Categories:ClassifyTitle(title)
	if type(title) ~= "string" or title == "" then
		return nil
	end
	local lower = title:lower()
	local cats, classToken = {}, nil

	if Matches(lower, P.flight) then cats.flight = true end
	if Matches(lower, P.inn) then cats.inn = true; cats.food = true end
	if Matches(lower, P.auction) then cats.auction = true end
	if Matches(lower, P.bank) then cats.bank = true end
	if Matches(lower, P.stable) then cats.stable = true end
	if Matches(lower, P.battlemaster) then cats.battlemaster = true end
	if Matches(lower, P.transport) then cats.transport = true end
	if Matches(lower, P.spirit) then cats.spirit = true end

	if Matches(lower, P.weaponmaster) then
		cats.weaponmaster = true
	elseif Matches(lower, P.trainer) then
		if Matches(lower, P.pet) then
			cats.trainer_class = true
			classToken = "HUNTER"
		else
			classToken = ClassFromTitle(lower)
			if classToken then
				cats.trainer_class = true
			else
				cats.trainer_prof = true
			end
		end
	else
		-- Vendors. Spirit healers are checked first so "Wine & Spirits" stays food.
		if Matches(lower, P.reagent) then cats.reagent = true; cats.vendor = true end
		if Matches(lower, P.poison) then cats.poison = true; cats.vendor = true end
		if Matches(lower, P.ammo) then cats.ammo = true; cats.vendor = true end
		if not cats.spirit and Matches(lower, P.food) then cats.food = true; cats.vendor = true end
		if Matches(lower, P.vendor) then cats.vendor = true end
	end

	if next(cats) == nil then
		return nil
	end
	return cats, classToken
end
