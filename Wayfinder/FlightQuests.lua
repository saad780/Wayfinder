-- Keep the flight-master role when a quest takes over the same NPC's icon.
-- Read live marker identities and one cached NPC-role field, never spawn data.
local _, ns = ...
local Flights = ns:NewModule("FlightQuests")
local roleCache, database, loader, query = {}, nil, nil, nil
local function ID(value)
	return ns.Readable(value) and type(value)=="number" and value>0 and value<math.huge and value==math.floor(value)
end
local function FlightRole(id)
	if loader ~= QuestieLoader then loader, database, query, roleCache = QuestieLoader, nil, nil, {} end
	if not database and loader and type(loader.ImportModule)=="function" then
		local ok, db = pcall(loader.ImportModule,loader,"QuestieDB")
		if ok and type(db)=="table" then database=db end
	end
	local getter = database and database.QueryNPCSingle
	if type(getter)~="function" then return end
	if getter~=query then query,roleCache=getter,{} end
	if roleCache[id]~=nil then return roleCache[id] end
	local mask=database.npcFlags and database.npcFlags.FLIGHT_MASTER
	if not ID(mask) then return end
	local ok, flags=pcall(getter,id,"npcFlags")
	if ok and ns.Readable(flags) and type(flags)=="number" and flags>=0 and flags<math.huge then
		local flight=math.floor(flags/mask)%2==1
		roleCache[id]=flight
		return flight
	end
end
function Flights:Giver(data)
	if type(data)~="table" then return end
	local id=data.npcID
	if not ID(id) then
		local quest=data.QuestData
		local targets=type(quest)=="table" and (data.Type=="complete" and quest.Finisher or data.Type=="available" and quest.Starts)
		local npcs=type(targets)=="table" and targets.NPC
		local objects=type(targets)=="table" and targets.GameObject
		-- Mixed targets are ambiguous. Do not build an all-NPC name index just
		-- to guess which finisher owns a marker.
		if type(npcs)=="table" and not npcs[2] and not (type(objects)=="table" and objects[1]) then id=npcs[1] end
	end
	if ID(id) then return id end
end
function Flights:Matches(rec, quest)
	if not (quest.turnIn or quest.kind=="available") then return false end
	local distance=ns.Distance(rec.x,rec.y,quest.x,quest.y)
	if distance>40 then return false end
	local a,b=ID(rec.id) and rec.id,ID(quest.npcID) and quest.npcID
	if a and b then return a==b end
	local name=quest.n or quest.name
	if rec.n and name and rec.n==name then return distance<=25 end
	-- Taxi nodes name a destination, not its NPC. A nearby live marker whose
	-- NPC is a confirmed flight master can bridge that naming difference.
	if not a and b then
		if quest.flightGiver==nil then quest.flightGiver=FlightRole(b) end
		if quest.flightGiver then return true end
	end
	if rec.n and name and rec.n~=name then return false end
	return distance<2
end
function Flights:Find(rec, quests)
	local best,score
	for _,quest in ipairs(quests) do
		if self:Matches(rec,quest) then
			local rank=(quest.native and 10000 or 0)+(quest.turnIn and 1000 or 0)-ns.Distance(rec.x,rec.y,quest.x,quest.y)
			if not score or rank>score then best,score=quest,rank end
		end
	end
	return best
end
function Flights:DisplayRecord(rec, quest)
	local display={}
	for k,v in pairs(rec) do display[k]=v end
	display.x,display.y,display.id,display.n=quest.x,quest.y,quest.npcID or rec.id,quest.n or rec.n
	return display
end
function Flights:Badge(pin, kind, size)
	local badge=pin.questBadge
	if not kind then if badge then badge:Hide() end; return end
	if not badge then
		badge=pin:CreateTexture(nil,"OVERLAY",nil,7)
		badge:SetPoint("TOPRIGHT",pin,"TOPRIGHT",4,4)
		pin.questBadge=badge
	end
	if pin.questBadgeKind~=kind then
		if kind=="complete" then ns.Categories:ApplyTurnInIcon(badge)
		else ns.Categories:ApplyIcon(badge,"quest") end
		pin.questBadgeKind=kind
	end
	local width=math.floor(size*.65+.5)
	if pin.questBadgeSize~=width then badge:SetSize(width,width);pin.questBadgeSize=width end
	badge:Show()
end
