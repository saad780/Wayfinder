-- Turn-ins are active, completed quests, separate from unaccepted pickups.
local _, ns = ...
local TurnIns = ns:NewModule("QuestTurnIns")
local removed = {}

local function Number(value)
	return ns.Readable(value) and type(value) == "number" and value == value
		and value > -math.huge and value < math.huge
end

local function ValidID(id)
	return Number(id) and id > 0 and id == math.floor(id)
end

local function Read(fn, ...)
	if type(fn) ~= "function" then return end
	local ok, value = pcall(fn, ...)
	if ok and ns.Readable(value) then return value end
end

function TurnIns:IsReady(id)
	return ValidID(id) and not removed[id] and C_QuestLog
		and Read(C_QuestLog.IsOnQuest, id) == true and Read(C_QuestLog.IsComplete, id) == true
end

function TurnIns:GetForMap(mapID, positionsOnly)
	local result, seen = {}, {}
	local quests = C_QuestLog and Read(C_QuestLog.GetQuestsOnMap, mapID)
	if type(quests) ~= "table" then return result end
	for _, info in ipairs(quests) do
		if ns.Readable(info) and type(info) == "table" and self:IsReady(info.questID)
			and not seen[info.questID] and Number(info.x) and Number(info.y)
			and info.x >= 0 and info.x <= 1 and info.y >= 0 and info.y <= 1
			and (info.isMapIndicatorQuest == nil or (ns.Readable(info.isMapIndicatorQuest) and info.isMapIndicatorQuest == false)) then
			local title = not positionsOnly and Read(C_QuestLog.GetTitleForQuestID, info.questID)
			result[#result + 1] = { questID = info.questID, questName = type(title) == "string" and title or (QUESTS_LABEL or "Quest"),
				x = info.x, y = info.y, turnIn = true }
			seen[info.questID] = true
		end
	end
	return result
end

function TurnIns:OnLogin()
	local function Changed() ns:Fire("QUEST_TURN_INS_CHANGED") end
	for _, event in ipairs({ "QUEST_LOG_UPDATE", "QUEST_POI_UPDATE", "QUEST_WATCH_UPDATE", "QUEST_WATCH_LIST_CHANGED" }) do
		ns:RegisterEvent(event, Changed)
	end
	for _, event in ipairs({ "QUEST_TURNED_IN", "QUEST_REMOVED" }) do
		ns:RegisterEvent(event, function(_, id)
			if ValidID(id) then removed[id] = true end -- suppress stale POIs immediately
			Changed()
		end)
	end
	ns:RegisterEvent("QUEST_ACCEPTED", function(_, id)
		if ValidID(id) then removed[id] = nil end -- repeatable quests can return
		Changed()
	end)
end
