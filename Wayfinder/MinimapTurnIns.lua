-- Let the client's quest tracking own live NPC positions and expected-location
-- fallbacks. Questie's database pins must not add a second static question mark
-- to the corner minimap. World-map frames and native blips are never changed.
local _, ns = ...
local Mini = ns:NewModule("MinimapTurnIns")
local observed = setmetatable({}, { __mode = "k" })
local questLists, manualLists = setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" })
local completeFrames, unlocated = setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" })
local buckets = {}
local GRID = 250
-- Questie can add/remove entries while a discovery job is suspended. Restart
-- safely if rehashing invalidates next's cursor, without processing names twice.
local function Entries(tbl)
	local key, seen = nil, {}
	return function()
		while true do
			local ok, k, value = pcall(next, tbl, key)
			if not ok then k, value = next(tbl) end
			key = k
			if k == nil then return end
			if not seen[k] then seen[k] = true; return k, value end
			coroutine.yield()
		end
	end
end
local function Number(v)
	return ns.Readable(v) and type(v) == "number" and v == v and math.abs(v) < math.huge
end
local function RemoveIndex(frame, state)
	if state.bucket then
		state.bucket[frame] = nil
		if not next(state.bucket) then buckets[state.cont][state.key] = nil end
	end
	state.bucket, state.kind, state.cont, state.x, state.y = nil, nil, nil, nil, nil
end
function Mini:IndexFrame(frame, state)
	local data, tag = frame.data, frame.wayfinderServiceTag
	local kind
	if frame.miniMapIcon == true and type(data) == "table" then
		if frame.isManualIcon and tag and tag.data == data then kind = "service"
		elseif data.Type == "complete" or data.Type == "available" then kind = "quest" end
	end
	completeFrames[frame] = frame.miniMapIcon == true and type(data) == "table" and data.Type == "complete" or nil
	unlocated[frame] = nil
	if not kind or not Number(frame.x) or not Number(frame.y) or not Number(frame.UiMapID) then
		if kind then unlocated[frame] = true end
		RemoveIndex(frame, state)
		return
	end
	if state.bucket and state.kind == kind and state.sourceData == data and state.map == frame.UiMapID
		and state.nx == frame.x and state.ny == frame.y then return end
	RemoveIndex(frame, state)
	local c, x, y = ns.MapToWorld(frame.UiMapID, frame.x/100, frame.y/100)
	if not c then return end
	local key = (math.floor(x/GRID)+200)*1000 + math.floor(y/GRID)+200
	buckets[c] = buckets[c] or {}
	local bucket = buckets[c][key]
	if not bucket then bucket = setmetatable({}, {__mode="k"}); buckets[c][key] = bucket end
	bucket[frame] = state
	state.bucket, state.key, state.kind, state.cont, state.x, state.y = bucket, key, kind, c, x, y
	state.map, state.nx, state.ny, state.sourceData = frame.UiMapID, frame.x, frame.y, data
	if ns.MinimapServices then ns.MinimapServices:RequestUpdate() end
end
local function Query(cont, minX, maxX, minY, maxY, callback)
	-- Normally QueueDraw supplies coordinates before indexing. This small set
	-- also supports owners which populate a frame just after announcing it.
	for frame in pairs(unlocated) do Mini:IndexFrame(frame, observed[frame]) end
	local grid = buckets[cont]
	if not grid then return end
	for bx=math.floor(minX/GRID),math.floor(maxX/GRID) do
		for by=math.floor(minY/GRID),math.floor(maxY/GRID) do
			local bucket = grid[(bx+200)*1000+by+200]
			for frame,state in pairs(bucket or {}) do
				if state.x >= minX and state.x <= maxX and state.y >= minY and state.y <= maxY then
					callback(frame,state)
				end
			end
		end
	end
end

function Mini:ShouldSuppress(frame)
	if not Minimap then return false end
	local tag = frame.wayfinderServiceTag
	if frame.miniMapIcon == true and frame.isManualIcon and tag and tag.data == frame.data
		and ns:GetSetting("showMinimapServices") and ns.MinimapServices:IsActive() then return true end
	if not ns:GetSetting("nativeMinimapTurnIns") then return false end
	if frame.miniMapIcon ~= true or type(frame.data) ~= "table" or frame.data.Type ~= "complete" then return false end
	-- Only hand off accepted, ready quests that the client can identify. A
	-- missing/restricted quest API must leave the original addon marker intact.
	-- GetForMap already verifies accepted/completed state once per quest.
	-- Do not repeat those client API calls for every pooled copy of a pin.
	local id = frame.data.Id
	if not Number(id) or id <= 0 or id ~= math.floor(id) then return false end
	local mapID = frame.UiMapID or C_Map.GetBestMapForUnit("player")
	if not Number(mapID) then return false end
	if self.readyMaps then
		local ready = self.readyMaps[mapID]
		if not ready then
			ready = {}
			for _, quest in ipairs(ns.QuestTurnIns:GetForMap(mapID, true)) do ready[quest.questID] = true end
			self.readyMaps[mapID] = ready
		end
		return ready[frame.data.Id] == true
	end
	for _, quest in ipairs(ns.QuestTurnIns:GetForMap(mapID, true)) do
		if quest.questID == frame.data.Id then return true end
	end
	return false
end
local SERVICE_TYPES = {
	["repair"] = "repair", ["auctioneer"] = "auction", ["banker"] = "bank", ["battlemaster"] = "battlemaster",
	["flight master"] = "flight", ["innkeeper"] = "inn", ["stable master"] = "stable",
	["spirit healer"] = "spirit", ["weapon master"] = "weaponmaster", ["mailbox"] = "mailbox",
	["class trainer"] = "trainer_class", ["profession trainer"] = "trainer_prof", ["trade goods"] = "vendor",
	["food & drink"] = "food", ["food and drink"] = "food", ["reagents"] = "reagent",
	["poisons"] = "poison", ["ammunition"] = "ammo", ["ammo"] = "ammo",
}
for _, name in ipairs({ "druid", "hunter", "mage", "paladin", "priest", "rogue", "shaman", "warlock", "warrior" }) do SERVICE_TYPES[name] = "trainer_class" end
for _, name in ipairs({ "alchemy", "blacksmithing", "enchanting", "engineering", "herbalism", "inscription", "jewelcrafting",
	"leatherworking", "mining", "skinning", "tailoring", "cooking", "first aid", "fishing", "riding" }) do SERVICE_TYPES[name] = "trainer_prof" end
local function Service(typ)
	local key = type(typ) == "string" and typ:lower() or ""
	local cat = SERVICE_TYPES[key] or ((key:find("vendor",1,true) or key:find("merchant",1,true)) and "vendor")
	return cat, cat == "trainer_class" and key ~= "class trainer" and key:upper() or nil
end
function Mini:TagFrame(frame, typ, id)
	if not frame then return end
	if id and (not frame.isManualIcon or type(frame.data) ~= "table" or frame.data.id ~= id) then return end
	local cat, cls = Service(typ)
	local tag = frame.wayfinderServiceTag
	if not tag or tag.data ~= frame.data or tag.cat ~= cat or tag.cls ~= cls then
		frame.wayfinderServiceTag = cat and {data=frame.data,cat=cat,cls=cls} or nil
	end
	self:ObserveFrame(frame)
	if observed[frame] then self:RefreshFrame(frame,observed[frame]) end
end
function Mini:ObserveManualFrames(map, typ, id, tailOnly)
	local list = map.manualFrames and map.manualFrames[typ] and map.manualFrames[typ][id]
	if type(list) ~= "table" then return end
	local count, cursor = #list, manualLists[list]
	local first = cursor and count >= cursor.count and list[cursor.count] == cursor.last and cursor.count+1 or 1
	-- The installed Questie appends exactly the world/minimap pair per draw.
	-- Existing pools are discovered separately within the background budget.
	if tailOnly then first = math.max(1,count-1) end
	for i=first,count do self:TagFrame(_G[list[i]],typ,id) end
	manualLists[list] = {count=count,last=list[count]}
end
-- Temporary positions remain owned by Questie and are never written to saves.
function Mini:QueryServices(cont, minX, maxX, minY, maxY, callback)
	local locations = {}
	Query(cont,minX,maxX,minY,maxY,function(frame,state)
		local tag = frame.wayfinderServiceTag
		if state.kind ~= "service" or not tag or tag.data ~= frame.data or not frame.isManualIcon or frame.miniMapIcon ~= true then return end
		local ok, filtered = pcall(state.original, frame)
		if not ok or filtered then return end
		local x,y = state.x,state.y
		local id, rec = frame.data.id or frame.data.Id
		if not ns.Readable(id) then id = nil end
		for _, prior in ipairs(locations) do
			if id and prior.id == id and ns.Distance(prior.x,prior.y,x,y) < 0.5 then rec=prior; break end
		end
		if not rec then
			rec = {id=id,n=frame.data.Name or ns.CategoryByID[tag.cat].label,cats={},c=cont,x=x,y=y,
				m=frame.UiMapID,a=0,cls=tag.cls,ephemeral=true,
				k=("minimap:%s:%s:%d:%d"):format(tostring(id or "service"),tostring(frame.UiMapID),math.floor(x),math.floor(y))}
			locations[#locations+1]=rec
		end
		rec.cats[tag.cat]=true
	end)
	for _,rec in ipairs(locations) do if not ns.db.hidden[rec.k] then callback(rec) end end
end
function Mini:QueryQuestGivers(cont, minX, maxX, minY, maxY, callback)
	Query(cont,minX,maxX,minY,maxY,function(frame,state)
		local data=frame.data
		if state.kind ~= "quest" or frame.miniMapIcon ~= true or not (frame:IsVisible() or state.owned)
			or type(data) ~= "table" or (data.Type ~= "complete" and data.Type ~= "available") then return end
		-- Refresh just this nearby entry if an owner changes a location in place.
		self:IndexFrame(frame,state)
		local ok,filtered=pcall(state.original,frame)
		if ok and not filtered and state.cont == cont then
			local name=ns.Readable(data.Name) and type(data.Name)=="string" and data.Name~="" and data.Name or nil
			local id=Number(data.Id) and data.Id>0 and data.Id or nil
			callback({x=state.x,y=state.y,n=name,questID=id})
		end
	end)
end
function Mini:ObserveFrame(frame)
	if not frame or type(frame.ShouldBeHidden) ~= "function" then return end
	local state=observed[frame]
	if not state then
		local original=frame.ShouldBeHidden
		state={original=original}
		observed[frame]=state
		frame.ShouldBeHidden=function(owner,...)
			if original(owner,...) then return true end
			local ok,suppress=pcall(self.ShouldSuppress,self,owner)
			if ok and suppress then
				if not owner.hidden then state.owned=true end
				return true
			end
			return false
		end
		if type(frame.Unload)=="function" then
			hooksecurefunc(frame,"Unload",function(owner)
				-- Questie defers unloading a frame still waiting in its draw queue.
				if not owner.data or owner.miniMapIcon == nil then
					RemoveIndex(owner,state)
					completeFrames[owner],unlocated[owner],state.owned=nil,nil,nil
					owner.wayfinderServiceTag=nil
					if ns.MinimapServices then ns.MinimapServices:RequestUpdate() end
				end
			end)
		end
	end
	self:IndexFrame(frame,state)
end
function Mini:ObserveQuestFrames(map,questID)
	local list=map.questIdFrames and map.questIdFrames[questID]
	if type(list)~="table" then return end
	local function Observe(name)
		local frame=_G[name]
		self:ObserveFrame(frame)
		local state=frame and observed[frame]
		if state then self:RefreshFrame(frame,state) end
	end
	if #list>0 then
		local count,cursor=#list,questLists[list]
		local first=cursor and count>=cursor.count and list[cursor.count]==cursor.last and cursor.count+1 or 1
		for i=first,count do Observe(list[i]) end
		questLists[list]={count=count,last=list[count]}
	else
		-- Current Questie stores frame-name keys, rather than an array. Its
		-- QueueDraw hook handles additions individually; this is discovery only.
		for _,name in pairs(list) do Observe(name) end
	end
end
function Mini:RefreshFrame(frame,state,ownershipOnly)
	-- QueueDraw and Unload keep positions current. The ownership poll does not
	-- need to validate/reindex every coordinate of an unchanged pooled frame.
	if not ownershipOnly or not state.bucket or state.sourceData ~= frame.data or frame.miniMapIcon ~= true
		or type(frame.data) ~= "table" or frame.data.Type ~= "complete" then self:IndexFrame(frame,state) end
	local ok,suppress=true,false
	if frame.miniMapIcon == true then ok,suppress=pcall(self.ShouldSuppress,self,frame) end
	if ok and suppress then
		if not frame.hidden and frame.FakeHide then state.owned=true; pcall(frame.FakeHide,frame) end
	elseif state.owned then
		state.owned=nil
		local readable,hidden=pcall(state.original,frame)
		if readable and not hidden and frame.FakeShow then pcall(frame.FakeShow,frame) end
	end
end
-- Explicit synchronous refresh for callers/tests; event paths use the worker.
function Mini:Refresh()
	self.readyMaps={}
	for frame,state in pairs(observed) do self:RefreshFrame(frame,state) end
	self.readyMaps=nil
end
function Mini:RequestRefresh(all)
	if all then self.refreshAll=true end
	if ns.Background:Has("minimap ownership") then self.refreshAgain=true; return end
	ns.Background:Queue("minimap ownership",function()
		repeat
			local full,ready,revision=self.refreshAll,{},self.questRevision
			self.refreshAll,self.refreshAgain=nil,nil
			for frame in Entries(full and observed or completeFrames) do
				if revision ~= self.questRevision then wipe(ready); revision = self.questRevision end
				self.readyMaps=ready
				self:RefreshFrame(frame,observed[frame],not full)
				self.readyMaps=nil
				coroutine.yield()
			end
		until not self.refreshAgain
	end)
end
function Mini:Install()
	if not QuestieLoader or not QuestieLoader.ImportModule then return end
	local ok,module=pcall(QuestieLoader.ImportModule,QuestieLoader,"QuestieFrame")
	if not ok or type(module)~="table" or type(module.CreateIconFrame)~="function" then return end
	if self.installed~=module then
		self.installed=module
		hooksecurefunc(module,"CreateIconFrame",function(id) self:ObserveFrame(_G["QuestieFrame"..id]) end)
	end
	local found,map=pcall(QuestieLoader.ImportModule,QuestieLoader,"QuestieMap")
	if not found or type(map)~="table" then return end
	if self.queueInstalled~=map and type(map.QueueDraw)=="function" then
		self.queueInstalled=map
		hooksecurefunc(map,"QueueDraw",function(_,_,_,frame)
			self:ObserveFrame(frame)
			if frame and observed[frame] then self:RefreshFrame(frame,observed[frame]) end
		end)
	end
	if self.manualInstalled~=map and type(map.DrawManualIcon)=="function" then
		self.manualInstalled=map
		hooksecurefunc(map,"DrawManualIcon",function(_,data,_,_,_,typ)
			if type(data)=="table" then self:ObserveManualFrames(map,typ or "any",data.id,true) end
		end)
	end
	if self.mapInstalled~=map and type(map.DrawWorldIcon)=="function" then
		self.mapInstalled=map
		hooksecurefunc(map,"DrawWorldIcon",function(_,data)
			if self.queueInstalled~=map and type(data)=="table" then self:ObserveQuestFrames(map,data.Id) end
		end)
	end
	if self.discoveredMap~=map then
		self.discoveredMap=map
		ns.Background:Queue("questie discovery",function()
			for _,list in Entries(map.questIdFrames or {}) do
				for _,name in Entries(list) do
					local frame=_G[name]
					self:ObserveFrame(frame)
					if frame and observed[frame] then self:RefreshFrame(frame,observed[frame]) end
					coroutine.yield()
				end
			end
			for typ,byID in Entries(map.manualFrames or {}) do
				for id,list in Entries(byID) do
					for _,name in Entries(list) do self:TagFrame(_G[name],typ,id); coroutine.yield() end
				end
			end
		end)
	end
end
function Mini:OnLogin()
	C_Timer.After(0,function() self:Install() end)
	C_Timer.NewTicker(0.25,function() if next(completeFrames) then self:RequestRefresh() end end)
	ns:On("QUEST_TURN_INS_CHANGED",function()
		self.questRevision = (self.questRevision or 0) + 1
		self:RequestRefresh()
	end)
	ns:On("SETTING_CHANGED",function(key)
		if key=="nativeMinimapTurnIns" or key=="showMinimapServices" then self:Install(); self:RequestRefresh(true) end
	end)
	ns:RegisterEvent("ADDON_LOADED",function(_,name)
		if name=="Questie" then C_Timer.After(0,function() self:Install() end) end
	end)
end
