-- Startup and burst regressions use synthetic geometry and icon data only.
local ns,Work,Mini=Wayfinder,Wayfinder.Background,Wayfinder.MinimapTurnIns
local passed,failed=0,0
local function test(name,fn)
	local ok,err=pcall(fn)
	if ok then passed=passed+1;io.write("  ok    ",name,"\n")
	else failed=failed+1;io.write("  FAIL  ",name,"\n        ",tostring(err),"\n") end
end
ns.db.settings.importExploration=false
Minimap=CreateFrame("Frame",nil,UIParent);Minimap:SetSize(200,200)
ns.MinimapServices:Update()
mock.DrainBackground()

test("background jobs share one millisecond per frame and stop when idle",function()
	local original=debugprofilestop
	local clock,units,a,b=0,0,0,0
	debugprofilestop=function() return clock end
	for _,key in ipairs({"budget a","budget b"}) do
		Work:Queue(key,function()
			for _=1,50 do
				clock=clock+0.26;units=units+1
				if key=="budget a" then a=a+1 else b=b+1 end
				coroutine.yield()
			end
		end)
	end
	local accepted=Work:Queue("budget a",function() error("duplicate job ran") end)
	Work:Run()
	local firstFrame,shared=units,a>0 and b>0
	for _=1,100 do if Work:IsIdle() then break end;Work:Run() end
	debugprofilestop=original
	assert(not accepted and shared,"requests merge and both jobs make progress")
	assert(firstFrame==4,"combined budget ends after four 0.26-ms operations")
	assert(units==100 and Work:IsIdle(),"all work finishes and the worker sleeps")
end)

test("expensive client calls yield to a new rendered frame",function()
	local visits={}
	Work:Queue("yield frames",function()
		for _=1,12 do
			visits[GetTime()]=(visits[GetTime()] or 0)+1
			coroutine.yield("frame")
		end
	end)
	mock.DrainBackground("yield frames")
	local count=0
	for _,n in pairs(visits) do assert(n==1,"one API unit per frame");count=count+1 end
	assert(count==12)
end)

test("flight imports prioritize the current map, merge requests and deduplicate nodes",function()
	local original=C_TaxiMap.GetTaxiNodesForMap
	local calls,first,records={},nil,0
	local record=ns.Database.RecordTaxi
	ns.Database.RecordTaxi=function(self,...) records=records+1;return record(self,...) end
	C_TaxiMap.GetTaxiNodesForMap=function(map)
		first=first or map;calls[GetTime()]=(calls[GetTime()] or 0)+1
		return {{nodeID=990001,name="Synthetic flight",faction=2,isUndiscovered=false,position=CreateVector2D(.4,.6)}}
	end
	ns.Recorder:ImportKnownFlightPaths();ns.Recorder:ImportKnownFlightPaths()
	local synchronous=records
	mock.DrainBackground("flight import")
	ns.Database.RecordTaxi=record;C_TaxiMap.GetTaxiNodesForMap=original
	assert(synchronous==0,"the import request itself performs no API or record work")
	assert(first==mock.playerMap and records==1,"local zone first; one recording per node")
	for _,n in pairs(calls) do assert(n==1,"one taxi-map query per rendered frame") end
end)

test("unchanged taxi nodes do not broadcast POI invalidations",function()
	local events=0
	local rec=ns.db.pois.t990001
	ns:On("POI_UPDATED",function(r) if r==rec then events=events+1 end end)
	for i=1,100 do ns.Database:RecordTaxi({nodeID=990001,name=rec.n,faction=rec.f,cont=rec.c,wx=rec.x,wy=rec.y,mapID=1453}) end
	assert(events==0,"same node on another map must not repeatedly invalidate icons")
	ns.Database:RecordTaxi({nodeID=990001,name="Updated synthetic name",faction=rec.f,cont=rec.c,wx=rec.x,wy=rec.y,mapID=rec.m})
	assert(events==1,"a visible change still emits one update")
end)

test("hundreds of POI events request one minimap rebuild in a rendered frame",function()
	mock.Advance(.05)
	local old=ns.MinimapServices.Rebuild
	local calls=0
	ns.MinimapServices.Rebuild=function(self,...) calls=calls+1;return old(self,...) end
	for _=1,400 do ns:Fire("POI_UPDATED",ns.db.pois.t990001) end
	local synchronous=calls
	mock.Advance(.016,.016)
	ns.MinimapServices.Rebuild=old
	assert(synchronous==0 and calls==1,"burst events coalesce rather than nesting full rebuilds")
end)

local function Frame(name,kind,id,x,y)
	local f=CreateFrame("Frame",name,Minimap)
	f.miniMapIcon,f.isManualIcon,f.UiMapID=true,kind=="manual",1429
	f.data={Type=kind,id=id,Id=id,Name="Synthetic NPC "..id}
	f.x,f.y=x or 10,y or 10
	function f:ShouldBeHidden() self.filterCalls=(self.filterCalls or 0)+1;return self.filtered==true end
	function f:FakeHide() self.hidden=true;self:Hide() end
	function f:FakeShow() self.hidden=false;self:Show() end
	function f:Unload() self.data=nil;self.miniMapIcon=nil;self.isManualIcon=nil;self:Hide() end
	return f
end

test("growing manual lists are processed linearly",function()
	local list,map={}, {manualFrames={Repair={}}}
	map.manualFrames.Repair[990002]=list
	local original,calls=Mini.ObserveFrame,0
	Mini.ObserveFrame=function(self,...) calls=calls+1;return original(self,...) end
	for i=1,500 do
		local f=Frame("StartupGrowing"..i,"manual",990002)
		list[#list+1]=f:GetName();Mini:ObserveManualFrames(map,"Repair",990002)
	end
	Mini.ObserveFrame=original
	assert(calls==500,"500 appends require 500 observations, not 125,250")
end)

test("nearby queries do not inspect distant service and quest pools",function()
	local far={}
	for i=1,2000 do
		local f=Frame("StartupDistant"..i,i%2==0 and "manual" or "available",991000+i,10,10)
		if f.isManualIcon then Mini:TagFrame(f,"Repair") else Mini:ObserveFrame(f) end
		f.filterCalls=0;far[#far+1]=f
	end
	local c,x,y=ns.MapToWorld(1429,.8,.8)
	local records=0
	Mini:QueryServices(c,x-120,x+120,y-120,y+120,function() records=records+1 end)
	Mini:QueryQuestGivers(c,x-120,x+120,y-120,y+120,function() records=records+1 end)
	assert(records==0)
	for _,f in ipairs(far) do assert(f.filterCalls==0,"distant original visibility filters are never called") end
end)

local module={CreateIconFrame=function() end}
local map={questIdFrames={},manualFrames={Repair={}},ICON_MINIMAP_TYPE=2}
function map:QueueDraw(_,_,frame) return frame end
function map:DrawManualIcon(data,_,_,_,typ)
	local list=self.manualFrames[typ][data.id] or {};self.manualFrames[typ][data.id]=list
	for i=1,2 do
		local f=Frame("StartupHook"..data.id.."_"..(#list+1),"manual",data.id,40,60)
		f.data=data;f.miniMapIcon=i==2
		self:QueueDraw(2,nil,f);list[#list+1]=f:GetName()
	end
end
QuestieLoader={ImportModule=function(_,name) return name=="QuestieFrame" and module or map end}

test("pre-existing dictionary pools are discovered over multiple frames",function()
	local list={};map.questIdFrames[999001]=list
	for i=1,800 do
		local f=Frame("StartupDictionary"..i,"available",999001)
		list[f:GetName()]=f:GetName()
	end
	local original,calls=Mini.ObserveFrame,0
	Mini.ObserveFrame=function(self,...) calls=calls+1;return original(self,...) end
	Mini:Install()
	local synchronous=calls
	Work:Run();local first=calls
	mock.DrainBackground("questie discovery")
	Mini.ObserveFrame=original
	assert(synchronous==0 and first>0 and first<=256,"discovery respects the shared work cap")
	assert(calls==800,"dictionary entries are discovered exactly once")
end)

test("Questie draw hooks process only the new pair and index reused frames",function()
	local old,calls=Mini.ObserveFrame,0
	Mini.ObserveFrame=function(self,...) calls=calls+1;return old(self,...) end
	for _=1,400 do map:DrawManualIcon({Type="manual",id=990003,Id=990003,Name="Hook merchant"},85,40,60,"Repair") end
	Mini.ObserveFrame=old
	assert(calls==1600,"two QueueDraw plus two tagging observations per draw, independent of list length")
	local f=Frame("StartupRecycled","manual",990004,80,80)
	Mini:TagFrame(f,"Repair")
	local c,x,y=ns.MapToWorld(1429,.8,.8)
	local function Count()
		local count=0;Mini:QueryServices(c,x-5,x+5,y-5,y+5,function(r) if r.id==990004 then count=count+1 end end);return count
	end
	assert(Count()==1,"initial source indexed")
	f:Unload();assert(Count()==0,"unloaded source removed")
	f.data={Type="manual",id=990004,Name="Reused merchant"};f.miniMapIcon=true;f.isManualIcon=true
	f.UiMapID,f.x,f.y=1429,80,80;f:Show()
	map:QueueDraw(2,nil,f);Mini:TagFrame(f,"Repair")
	assert(Count()==1,"recycled frame reappears once")
	f.x=10;f.y=10;map:QueueDraw(2,nil,f)
	assert(Count()==0,"moving to another bucket removes the old location")
end)

test("dictionary quest additions use QueueDraw without rescanning existing quests",function()
	local id=990005
	mock.questLog[id],mock.readyQuests[id]=true,true
	mock.questPOIs[1429]={{questID=id,x=.8,y=.8}}
	local f=Frame("StartupReady","complete",id,80,80)
	map:QueueDraw(2,nil,f)
	assert(f.hidden,"new completed quest yields to the native marker immediately")
	mock.questPOIs[1429]={};Mini:RequestRefresh();mock.DrainBackground("minimap ownership")
	assert(not f.hidden,"native API losing its location restores the fallback")
end)

test("exploration checks the frame budget between individual API samples",function()
	mock.DrainBackground()
	local api,profile=C_MapExplorationInfo.GetExploredAreaIDsAtPosition,debugprofilestop
	local clock,calls=0,0
	debugprofilestop=function() return clock end
	C_MapExplorationInfo.GetExploredAreaIDsAtPosition=function() clock=clock+.26;calls=calls+1;return {} end
	ns.db.settings.importExploration=true;ns.Exploration:Reset();ns.Exploration:QueueImportCurrentZone()
	Work:Run();local first=calls
	for _=1,10000 do if Work:IsIdle() then break end;Work:Run() end
	local completed=ns.db.imported[ns:GetCharacterKey()][mock.playerMap]
	C_MapExplorationInfo.GetExploredAreaIDsAtPosition,debugprofilestop=api,profile
	ns.db.settings.importExploration=false
	assert(first>0 and first<=4,"no fixed block of 64 API calls can overrun the budget")
	assert(completed and Work:IsIdle(),"completed exploration is marked imported only at the end")
end)

test("reset cancels incomplete exploration without marking the new save imported",function()
	local api,profile=C_MapExplorationInfo.GetExploredAreaIDsAtPosition,debugprofilestop
	local clock=0
	debugprofilestop=function() return clock end
	C_MapExplorationInfo.GetExploredAreaIDsAtPosition=function() clock=clock+.26;return {} end
	ns.db.settings.importExploration=true
	ns.Exploration:Reset();ns.Exploration:QueueImportCurrentZone();Work:Run()
	ns.Exploration:Reset();Work:Run()
	local imported=ns.db.imported[ns:GetCharacterKey()][mock.playerMap]
	C_MapExplorationInfo.GetExploredAreaIDsAtPosition,debugprofilestop=api,profile
	ns.db.settings.importExploration=false
	assert(not imported,"an old coroutine cannot mark the reset character's exploration complete")
end)

test("manual exploration import works when automatic import is disabled and finishes the local zone first",function()
	local api=C_MapExplorationInfo.GetExploredAreaIDsAtPosition
	local remote=0
	C_MapExplorationInfo.GetExploredAreaIDsAtPosition=function(mapID)
		if mapID~=mock.playerMap then
			assert(ns.db.imported[ns:GetCharacterKey()][mock.playerMap],"local exploration finishes before remote sampling")
			remote=remote+1
		end
		return {}
	end
	ns.Exploration:QueueImportAll(true);mock.DrainBackground()
	C_MapExplorationInfo.GetExploredAreaIDsAtPosition=api
	assert(ns.db.imported[ns:GetCharacterKey()][mock.playerMap] and remote>0)
end)

test("debug timings are opt-in and report bounded work",function()
	local before=next(Work.stats)
	ns.db.settings.debug=true
	Work:Queue("timed job",function() coroutine.yield() end)
	mock.DrainBackground("timed job")
	ns.MinimapServices:Update()
	ns.db.settings.debug=false
	assert(before==nil,"normal play collected no timing tables")
	assert(Work.stats["timed job"] and Work.stats["background frame"] and Work.stats["minimap refresh"])
end)
assert(#mock.errors==0,"no asynchronous Lua errors")
io.write("\n",passed," startup performance checks passed, ",failed," failed\n")
return failed
