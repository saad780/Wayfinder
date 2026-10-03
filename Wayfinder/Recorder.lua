-- Discovers NPCs and objects as you play and records where they are.
--
--   * Talking to someone (vendor, trainer, banker, flight master, mailbox...) records
--     them exactly: you are within a few yards when the window opens.
--   * Mousing over or targeting an NPC whose title names a service records them
--     approximately; repeated sightings from different spots converge on the NPC.
--   * Asking a guard for directions records the place the guard marks.
--   * Flight paths your character already knows are imported at login.
local _, ns = ...

local Recorder = ns:NewModule("Recorder")

local Readable = ns.Readable
local LEVEL_PREFIX = "^" .. (LEVEL or "Level") .. " "

---------------------------------------------------------------------------
-- Reading a unit
---------------------------------------------------------------------------
local function UnitTitle(unit)
	if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then
		return nil
	end
	local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
	if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then
		return nil
	end
	local line = data.lines[2]
	local text = line and line.leftText
	if not Readable(text) or text == "" then
		return nil
	end
	if text:find(LEVEL_PREFIX) or text:find("^%d") then
		return nil -- no subtitle; this is the level line
	end
	return (text:gsub("^<(.*)>$", "%1"))
end

local function FactionOf(unit)
	local ok, faction = pcall(UnitFactionGroup, unit)
	if ok and Readable(faction) then
		if faction == "Alliance" then
			return 1
		elseif faction == "Horde" then
			return 2
		end
	end
	return 0
end

-- Returns { npcID, name, title, faction, isObject } for an NPC or game object,
-- or nil for players, pets and anything the client won't reveal right now.
local function ReadUnit(unit)
	if not UnitExists(unit) or UnitIsPlayer(unit) then
		return nil
	end
	local controlled = UnitPlayerControlled(unit)
	if Readable(controlled) and controlled then
		return nil -- pets, guardians, totems, summoned helpers
	end
	local guid = UnitGUID(unit)
	if not Readable(guid) then
		return nil
	end
	local unitType, _, _, _, _, id = strsplit("-", guid)
	if unitType ~= "Creature" and unitType ~= "GameObject" and unitType ~= "Vehicle" then
		return nil
	end
	local npcID = UnitCreatureID and UnitCreatureID(unit)
	if not Readable(npcID) then
		npcID = tonumber(id)
	end
	local name = UnitName(unit)
	if not Readable(name) then
		name = nil
	end
	return {
		npcID = npcID,
		name = name,
		title = unitType ~= "GameObject" and UnitTitle(unit) or nil,
		faction = unitType ~= "GameObject" and FactionOf(unit) or 0,
		isObject = unitType == "GameObject",
	}
end

local function PlayerPosition()
	local cont, wx, wy, mapID = ns.GetPlayerWorld()
	if cont then
		return { cont = cont, wx = wx, wy = wy, mapID = mapID }
	end
end

local function Record(unitInfo, cats, classToken, accuracy, source)
	local pos = PlayerPosition()
	if not pos or not unitInfo then
		return nil
	end
	local titleCats, titleClass = ns.Categories:ClassifyTitle(unitInfo.title)
	local merged = {}
	for catID in pairs(titleCats or {}) do merged[catID] = true end
	for catID in pairs(cats or {}) do merged[catID] = true end
	if next(merged) == nil then
		return nil
	end
	return ns.Database:RecordNPC({
		npcID = unitInfo.npcID,
		name = unitInfo.name,
		title = unitInfo.title,
		cats = merged,
		class = classToken or titleClass,
		faction = unitInfo.faction,
		cont = pos.cont,
		wx = pos.wx,
		wy = pos.wy,
		mapID = pos.mapID,
		accuracy = accuracy,
		source = source,
	})
end

---------------------------------------------------------------------------
-- Talking to NPCs
---------------------------------------------------------------------------
local TALK_ACCURACY = 4
local T = Enum.PlayerInteractionType or {}

local SIMPLE_INTERACTIONS = {}
local function Map(name, catID)
	if T[name] then
		SIMPLE_INTERACTIONS[T[name]] = catID
	end
end
Map("TaxiNode", "flight")
Map("Banker", "bank")
Map("CharacterBanker", "bank")
Map("AccountBanker", "bank")
Map("SpiritHealer", "spirit")
Map("AreaSpiritHealer", "spirit")
Map("Binder", "inn")
Map("Auctioneer", "auction")
Map("StableMaster", "stable")
Map("BattleMaster", "battlemaster")
Map("QuestGiver", "quest")

local function HasQuests()
	local gossip = C_GossipInfo
	if gossip then
		local available = gossip.GetNumAvailableQuests and gossip.GetNumAvailableQuests() or 0
		local active = gossip.GetNumActiveQuests and gossip.GetNumActiveQuests() or 0
		if available > 0 or active > 0 then
			return true
		end
	end
	local available = GetNumAvailableQuests and GetNumAvailableQuests() or 0
	local active = GetNumActiveQuests and GetNumActiveQuests() or 0
	return available > 0 or active > 0
end

function Recorder:RecordMailbox()
	local pos = PlayerPosition()
	if not pos then
		return
	end
	ns.Database:RecordObject({
		cat = "mailbox",
		name = MAILBOX or "Mailbox",
		cont = pos.cont,
		wx = pos.wx,
		wy = pos.wy,
		mapID = pos.mapID,
		accuracy = TALK_ACCURACY,
	})
end

function Recorder:OnInteraction(interactionType)
	if interactionType == T.MailInfo then
		self:RecordMailbox()
		return
	end
	local unit = ReadUnit("npc")
	if not unit then
		return
	end
	local cats = {}
	local classToken

	local simple = SIMPLE_INTERACTIONS[interactionType]
	if simple then
		cats[simple] = true
	elseif interactionType == T.Merchant then
		cats.vendor = true
		if CanMerchantRepair and CanMerchantRepair() then
			cats.repair = true
		end
		self:ScheduleMerchantScan()
	elseif interactionType == T.Trainer then
		local titleCats, titleClass = ns.Categories:ClassifyTitle(unit.title)
		if titleCats and titleCats.weaponmaster then
			cats.weaponmaster = true
		elseif IsTradeskillTrainer and IsTradeskillTrainer() then
			cats.trainer_prof = true
		else
			-- The trainer window only opens for your own class's trainers
			-- (and, for hunters, the pet trainer).
			cats.trainer_class = true
			classToken = titleClass or ns.playerClass
		end
	elseif interactionType == T.Gossip then
		if HasQuests() then
			cats.quest = true
		end
	else
		return
	end

	if not unit.isObject or cats.quest then
		self.lastTalked = Record(unit, cats, classToken, TALK_ACCURACY, "talk")
	end
end

function Recorder:OnQuestFrame()
	local unit = ReadUnit("npc")
	if unit then
		Record(unit, { quest = true }, nil, TALK_ACCURACY, "talk")
	end
end

---------------------------------------------------------------------------
-- What a merchant sells
---------------------------------------------------------------------------
local FOOD_SPELLS = { Food = true, Drink = true, Refreshment = true }

function Recorder:ScheduleMerchantScan()
	if self.merchantTimer then
		self.merchantTimer:Cancel()
	end
	self.merchantTimer = C_Timer.NewTimer(0.6, function()
		self.merchantTimer = nil
		self:ScanMerchant()
	end)
end

function Recorder:ScanMerchant()
	local rec = self.lastTalked
	if not rec or not GetMerchantNumItems then
		return
	end
	local food, ammo, reagent, poison = 0, 0, 0, 0
	local IC = Enum.ItemClass or {}
	for i = 1, GetMerchantNumItems() do
		local link = GetMerchantItemLink(i)
		if link then
			local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(link)
			local name = link:match("%[(.-)%]") or ""
			local spellName = C_Item.GetItemSpell and C_Item.GetItemSpell(link)
			if classID == IC.Projectile then
				ammo = ammo + 1
			elseif classID == IC.Reagent then
				reagent = reagent + 1
			elseif classID == IC.Consumable and (subClassID == 5 or FOOD_SPELLS[spellName or ""]) then
				food = food + 1
			end
			if name:find("Poison") or name == "Flash Powder" then
				poison = poison + 1
			end
		end
	end
	local changed = false
	local function Add(catID, condition)
		if condition and not rec.cats[catID] then
			rec.cats[catID] = true
			changed = true
		end
	end
	Add("food", food >= 2)
	Add("ammo", ammo >= 1)
	Add("reagent", reagent >= 2)
	Add("poison", poison >= 2)
	if changed then
		ns:Fire("POI_UPDATED", rec, false)
	end
end

---------------------------------------------------------------------------
-- Seeing NPCs from a distance
---------------------------------------------------------------------------
local recentSightings = {} -- guid-free key -> { time, accuracy }

local function EstimateAccuracy(unit)
	if not CheckInteractDistance then
		return nil
	end
	local ok, close = pcall(CheckInteractDistance, unit, 3) -- about 10 yards
	if ok and Readable(close) and close then
		return 10
	end
	ok, close = pcall(CheckInteractDistance, unit, 4) -- about 28 yards
	if ok and Readable(close) and close then
		return 28
	end
	return nil -- too far away to place usefully
end

function Recorder:OnSighting(unit)
	if not ns:GetSetting("recordMouseover") or InCombatLockdown() then
		return
	end
	local info = ReadUnit(unit)
	if not info or info.isObject or not info.title then
		return
	end
	local cats, classToken = ns.Categories:ClassifyTitle(info.title)
	if not cats then
		return
	end
	local accuracy = EstimateAccuracy(unit)
	if not accuracy then
		return
	end
	local key = (info.npcID or 0) .. ":" .. (info.name or "")
	local last = recentSightings[key]
	local now = GetTime()
	if last and now - last.time < 5 and accuracy >= last.accuracy then
		return
	end
	recentSightings[key] = { time = now, accuracy = accuracy }
	Record(info, cats, classToken, accuracy, "sight")
end

---------------------------------------------------------------------------
-- Guards giving directions
---------------------------------------------------------------------------
local GUARD_TOPICS = {
	{ "mailbox", "mailbox" },
	{ "auction", "auction" },
	{ "bank", "bank" },
	{ "inn", "inn" },
	{ "flight master", "flight" }, { "gryphon", "flight" }, { "wind rider", "flight" },
	{ "hippogryph", "flight" }, { "bat handler", "flight" },
	{ "zeppelin", "transport", "zeppelin" }, { "tram", "transport", "tram" },
	{ "boat", "transport", "boat" }, { "ship", "transport", "boat" }, { "docks", "transport", "boat" },
	{ "stable", "stable" },
	{ "battlemaster", "battlemaster" }, { "battlemasters", "battlemaster" },
	{ "weapon master", "weaponmaster" }, { "weapons master", "weaponmaster" }, { "weapons trainer", "weaponmaster" },
}

local selectedOptions = {}

local function GuardTopic()
	local text = table.concat(selectedOptions, " "):lower()
	if text == "" then
		return nil
	end
	for _, topic in ipairs(GUARD_TOPICS) do
		if text:find("%f[%w]" .. topic[1]) then
			return topic[2], topic[3], nil
		end
	end
	if text:find("class trainer") then
		local _, classToken = ns.Categories:ClassifyTitle(selectedOptions[#selectedOptions] .. " Trainer")
		return "trainer_class", nil, classToken
	end
	if text:find("profession") or text:find("trade") then
		return "trainer_prof"
	end
	return nil
end

function Recorder:OnGossipOptionSelected(optionID)
	if not Readable(optionID) then
		return
	end
	local options = C_GossipInfo.GetOptions() or {}
	for _, option in ipairs(options) do
		if option.gossipOptionID == optionID and Readable(option.name) then
			selectedOptions[#selectedOptions + 1] = option.name
			if #selectedOptions > 3 then
				table.remove(selectedOptions, 1)
			end
			return
		end
	end
end

function Recorder:OnGossipPOI()
	local mapID = C_Map.GetBestMapForUnit("player")
	if not mapID or not C_GossipInfo.GetPoiForUiMapID then
		return
	end
	local poiID = C_GossipInfo.GetPoiForUiMapID(mapID)
	local info = poiID and C_GossipInfo.GetPoiInfo(mapID, poiID)
	if not info or not info.position then
		return
	end
	local catID, sub, classToken = GuardTopic()
	wipe(selectedOptions)
	if not catID then
		return
	end
	local x, y = info.position:GetXY()
	local cont, wx, wy = ns.MapToWorld(mapID, x, y)
	if not cont then
		return
	end
	local name = Readable(info.name) and info.name or nil
	if catID == "mailbox" then
		ns.Database:RecordObject({ cat = "mailbox", name = MAILBOX or "Mailbox", cont = cont, wx = wx, wy = wy,
			mapID = mapID, accuracy = 8 })
		return
	end
	local rec = ns.Database:RecordNPC({
		name = name,
		cats = { [catID] = true },
		class = classToken,
		cont = cont,
		wx = wx,
		wy = wy,
		mapID = mapID,
		accuracy = 8,
		source = "guard",
	})
	if rec then
		rec.guard = true
		rec.sub = rec.sub or sub
	end
end

---------------------------------------------------------------------------
-- Flight paths the character knows
---------------------------------------------------------------------------
local FLIGHT_FACTION = { [0] = 0, [1] = 2, [2] = 1 } -- Enum.FlightPathFaction -> ours

function Recorder:ImportKnownFlightPaths()
	if not (C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap) then
		return
	end
	local root = C_Map.GetFallbackWorldMapID and C_Map.GetFallbackWorldMapID() or 947
	local maps = C_Map.GetMapChildrenInfo(root, Enum.UIMapType.Zone, true) or {}
	for _, mapInfo in ipairs(maps) do
		local ok, nodes = pcall(C_TaxiMap.GetTaxiNodesForMap, mapInfo.mapID)
		if ok and type(nodes) == "table" then
			for _, node in ipairs(nodes) do
				if not node.isUndiscovered and node.position then
					local x, y = node.position:GetXY()
					local cont, wx, wy = ns.MapToWorld(mapInfo.mapID, x, y)
					if cont then
						ns.Database:RecordTaxi({
							nodeID = node.nodeID,
							name = node.name,
							faction = FLIGHT_FACTION[node.faction] or 0,
							cont = cont,
							wx = wx,
							wy = wy,
							mapID = mapInfo.mapID,
						})
					end
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------
function Recorder:OnLogin()
	ns:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(_, interactionType)
		self:OnInteraction(interactionType)
	end)
	ns:RegisterEvent("MERCHANT_UPDATE", function()
		if MerchantFrame and MerchantFrame:IsShown() then
			self:ScheduleMerchantScan()
		end
	end)
	-- Quest counts can arrive with GOSSIP_SHOW rather than the interaction event;
	-- recording twice just merges into the same NPC.
	ns:RegisterEvent("GOSSIP_SHOW", function()
		self:OnInteraction(T.Gossip)
	end)
	for _, event in ipairs({ "QUEST_DETAIL", "QUEST_GREETING", "QUEST_PROGRESS", "QUEST_COMPLETE" }) do
		ns:RegisterEvent(event, function()
			self:OnQuestFrame()
		end)
	end
	ns:RegisterEvent("UPDATE_MOUSEOVER_UNIT", function()
		self:OnSighting("mouseover")
	end)
	ns:RegisterEvent("PLAYER_TARGET_CHANGED", function()
		self:OnSighting("target")
	end)
	ns:RegisterEvent("GOSSIP_CLOSED", function()
		-- keep the chosen topic briefly: the guard's marker arrives after the window closes
		C_Timer.After(2, function()
			if not (GossipFrame and GossipFrame:IsShown()) then
				wipe(selectedOptions)
			end
		end)
	end)
	ns:RegisterEvent("DYNAMIC_GOSSIP_POI_UPDATED", function()
		self:OnGossipPOI()
	end)
	if C_GossipInfo and C_GossipInfo.SelectOption then
		pcall(hooksecurefunc, C_GossipInfo, "SelectOption", function(optionID)
			self:OnGossipOptionSelected(optionID)
		end)
	end
	ns:RegisterEvent("TAXIMAP_OPENED", function()
		C_Timer.After(0.5, function() self:ImportKnownFlightPaths() end)
	end)
	C_Timer.After(8, function()
		self:ImportKnownFlightPaths()
	end)
end
