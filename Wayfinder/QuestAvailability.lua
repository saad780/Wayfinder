-- Pickup availability belongs to a character, not to an NPC's permanent roles.
-- Saved data: questAvailability[character][recordKey] = { [questID] = metadata }.
local _, ns = ...
local Quests = ns:NewModule("QuestAvailability")
local unavailableByCharacter = {}
local pendingLocationsByCharacter = {}

local function CharacterState()
	local key = ns:GetCharacterKey()
	ns.db.questAvailability[key] = ns.db.questAvailability[key] or {}
	unavailableByCharacter[key] = unavailableByCharacter[key] or {}
	pendingLocationsByCharacter[key] = pendingLocationsByCharacter[key] or {}
	return ns.db.questAvailability[key], unavailableByCharacter[key], pendingLocationsByCharacter[key]
end

local function ValidID(id)
	return ns.Readable(id) and type(id) == "number" and id > 0 and id == math.floor(id)
end

local function Flag(fn, id)
	if not fn then return nil end
	local ok, value = pcall(fn, id)
	if ok and ns.Readable(value) and type(value) == "boolean" then return value end
end

-- The game must expose readable character state before we draw a pickup pin.
local function Eligible(id, metadata)
	if not ValidID(id) then return false end
	if not C_QuestLog then return nil end
	local onQuest = Flag(C_QuestLog.IsOnQuest, id)
	if onQuest == nil then return nil end
	if onQuest then return false end
	local completed = Flag(C_QuestLog.IsQuestFlaggedCompleted, id)
	if completed == nil then return nil end
	return not completed or (metadata and metadata.repeatable == true)
end

function Quests:IsQuestAvailable(id, metadata)
	local _, unavailable = CharacterState()
	return ValidID(id) and not unavailable[id] and Eligible(id, metadata) == true
end

function Quests:HasAvailableQuest(rec, questID)
	local state = CharacterState()
	local offers = rec and state[rec.k]
	if type(offers) ~= "table" then return false end
	for id, metadata in pairs(offers) do
		if (not questID or questID == id) and self:IsQuestAvailable(id, metadata) then return true end
	end
	return false
end

-- Only full, successfully read greetings can replace the list with an empty one.
-- A detail page confirms just one offer and must preserve the other offers.
function Quests:Observe(rec, offers, replace)
	if not rec or not rec.k or type(offers) ~= "table" then return end
	local state, unavailable, pending = CharacterState()
	local saved = replace and {} or state[rec.k] or {}
	for _, offer in ipairs(offers) do
		local eligible = Eligible(offer.questID, offer)
		if ValidID(offer.questID) and eligible ~= false then
			saved[offer.questID] = { repeatable = offer.repeatable == true }
			-- Unreadable log state must not erase the confirmed offer; wait until
			-- it can be checked before clearing an acceptance/turn-in suppression.
			if eligible then unavailable[offer.questID] = nil end
		end
	end
	if replace then
		local removed = pending[rec.k] or {}
		for id in pairs(state[rec.k] or {}) do
			if not saved[id] then removed[id] = true end
		end
		for id in pairs(saved) do removed[id] = nil end
		pending[rec.k] = removed
	elseif pending[rec.k] then
		for id in pairs(saved) do pending[rec.k][id] = nil end
	end
	state[rec.k] = saved
	ns:Fire("QUEST_AVAILABILITY_CHANGED")
	self:RequestLiveData(rec.m)
end

function Quests:RequestLiveData(mapID)
	if mapID and C_QuestLine and C_QuestLine.RequestQuestLinesForMap then
		pcall(C_QuestLine.RequestQuestLinesForMap, mapID)
	end
end

-- A complete greeting is newer than the map's cached offers. Suppress cached
-- offers at that NPC until the requested live map data arrives; also avoid
-- drawing the same known offer both as a recorded pin and a live pin.
function Quests:ShouldHideLiveQuestAt(cont, wx, wy, id)
	local _, _, pending = CharacterState()
	return ns.Database:FindNearest(cont, wx, wy, 25, function(rec)
		if not rec.cats.quest then return false end
		local available = self:HasAvailableQuest(rec, id)
		return (pending[rec.k] and pending[rec.k][id] and not available)
			or (available and ns.Categories:GetVisibleCategory(rec) == "quest")
	end) ~= nil
end

-- Also suppress stale live map data until the next quest-line update. This makes
-- accepting the final offer take effect even before the quest log has caught up.
function Quests:ForgetQuest(id)
	if not ValidID(id) then return end
	local state, unavailable = CharacterState()
	unavailable[id] = true
	for _, offers in pairs(state) do offers[id] = nil end
	ns:Fire("QUEST_AVAILABILITY_CHANGED")
	self:RequestLiveData(C_Map.GetBestMapForUnit("player"))
end

function Quests:Reconcile()
	local state = CharacterState()
	for _, offers in pairs(state) do
		for id, metadata in pairs(offers) do
			local onQuest = C_QuestLog and Flag(C_QuestLog.IsOnQuest, id)
			local completed = C_QuestLog and Flag(C_QuestLog.IsQuestFlaggedCompleted, id)
			if onQuest == true or (completed == true and not metadata.repeatable) then offers[id] = nil end
		end
	end
	ns:Fire("QUEST_AVAILABILITY_CHANGED")
end

function Quests:IsLiveQuestAvailable(info)
	if not ns.Readable(info) or type(info) ~= "table" then return false end
	if not ns.Readable(info.isHidden) or not ns.Readable(info.inProgress)
		or info.isHidden or info.inProgress then return false end
	local repeatable = ns.Readable(info.isDaily) and info.isDaily == true
	if not repeatable and ValidID(info.questID) then
		repeatable = C_QuestLog and Flag(C_QuestLog.IsRepeatableQuest, info.questID) == true
	end
	return self:IsQuestAvailable(info.questID, { repeatable = repeatable })
end

function Quests:RemoveRecord(rec)
	if not rec or not rec.k then return end
	for _, state in pairs(ns.db.questAvailability) do state[rec.k] = nil end
	for _, pending in pairs(pendingLocationsByCharacter) do pending[rec.k] = nil end
end

function Quests:Reset()
	wipe(ns.db.questAvailability)
	wipe(unavailableByCharacter)
	wipe(pendingLocationsByCharacter)
	ns:Fire("QUEST_AVAILABILITY_CHANGED")
end

function Quests:OnInitialize()
	-- Older records have no per-character evidence and consequently stay hidden.
	-- Drop orphaned or malformed availability without deleting NPC/service data.
	wipe(unavailableByCharacter)
	wipe(pendingLocationsByCharacter)
	for character, state in pairs(ns.db.questAvailability) do
		if type(state) ~= "table" then
			ns.db.questAvailability[character] = nil
		else
			for key, offers in pairs(state) do
				if not ns.db.pois[key] or type(offers) ~= "table" then
					state[key] = nil
				else
					for id, metadata in pairs(offers) do
						if not ValidID(id) or type(metadata) ~= "table" then offers[id] = nil end
					end
				end
			end
		end
	end
end

function Quests:OnLogin()
	self:Reconcile()
	for _, event in ipairs({ "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED" }) do
		ns:RegisterEvent(event, function(_, id) self:ForgetQuest(id) end)
	end
	ns:RegisterEvent("QUEST_LOG_UPDATE", function() self:Reconcile() end)
	ns:RegisterEvent("QUESTLINE_UPDATE", function()
		-- The live list is fresh; it can confirm abandoned/repeatable quests again.
		local _, unavailable, pending = CharacterState()
		wipe(unavailable)
		wipe(pending)
		self:Reconcile()
	end)
	ns:On("POI_REMOVED", function(rec) self:RemoveRecord(rec) end)
end
