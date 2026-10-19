-- Preserve the live update cadence while avoiding redundant native/UI work.
local ns,Mini=Wayfinder,Wayfinder.MinimapServices
local passed,failed=0,0
local function test(name,fn)
	local ok,err=pcall(fn)
	if ok then passed=passed+1;io.write("  ok    ",name,"\n")
	else failed=failed+1;io.write("  FAIL  ",name,"\n        ",tostring(err),"\n") end
end
ns.db.settings.importExploration=false
WorldMapFrame:Hide()
Minimap=CreateFrame("Frame",nil,UIParent);Minimap:SetSize(200,200)
local active={true,true,true,true}
local calls={tracking=0,filter=0,ready=0,title=0,art=0,position=0,rebuild=0}
local function ResetCounts() for key in pairs(calls) do calls[key]=0 end end
C_Minimap.GetNumTrackingTypes=function() return 4 end
local filters={Enum.MinimapTrackingFilter.Banker,Enum.MinimapTrackingFilter.Repair,90000001,90000002}
C_Minimap.GetTrackingFilter=function(i) calls.filter=calls.filter+1;return {filterID=filters[i]} end
C_Minimap.GetTrackingInfo=function(i) calls.tracking=calls.tracking+1;return {active=active[i],name=({"Bankers","Repair","Quests","Minerals"})[i]} end
C_Minimap.SetTracking=function(i,v) active[i]=v end
local radius,rotate=120,false
C_Minimap.GetViewRadius=function() return radius end
GetCVarBool=function(key) return key=="rotateMinimap" and rotate end
Mini:InstallTrackingMenu()
local on,title,art,rebuild=C_QuestLog.IsOnQuest,C_QuestLog.GetTitleForQuestID,ns.Categories.ApplyIcon,Mini.Rebuild
C_QuestLog.IsOnQuest=function(...) calls.ready=calls.ready+1;return on(...) end
C_QuestLog.GetTitleForQuestID=function(...) calls.title=calls.title+1;return title(...) end
ns.Categories.ApplyIcon=function(self,...) calls.art=calls.art+1;return art(self,...) end
Mini.Rebuild=function(self,...) calls.rebuild=calls.rebuild+1;return rebuild(self,...) end
mock.playerMap,mock.playerX,mock.playerY=1429,.8,.8
local c,x,y=ns.MapToWorld(1429,.8,.8)
local merchants,questFrames={},{}
for i=1,3 do merchants[i]=ns.Database:RecordNPC({npcID=800000+i,name="Idle merchant "..i,cats={vendor=true},cont=c,wx=x+(i-2)*35,wy=y,mapID=1429,accuracy=1}) end
for i=1,5 do
	local id=810000+i
	mock.questLog[id],mock.readyQuests[id],mock.questTitles[id]=true,true,"Quest title "..i
	mock.questPOIs[1429]=mock.questPOIs[1429] or {}
	table.insert(mock.questPOIs[1429],{questID=id,x=.7,y=.7})
	for _=1,100 do
		local f=CreateFrame("Frame",nil,Minimap)
		f.miniMapIcon,f.UiMapID,f.x,f.y=true,1429,70,70
		f.data={Type="complete",Id=id,Name="Idle quest giver"}
		f.ShouldBeHidden=function() return false end
		f.FakeHide=function(self) self.hidden=true;self:Hide() end
		f.FakeShow=function(self) self.hidden=false;self:Show() end
		ns.MinimapTurnIns:ObserveFrame(f);questFrames[#questFrames+1]=f
	end
end
mock.Advance(1,.01)
for _,pin in ipairs(Mini.pins or {}) do
	local point=pin.SetPoint
	pin.SetPoint=function(self,...) calls.position=calls.position+1;return point(self,...) end
end
local function Find(rec)
	for _,pin in ipairs(Mini.pins or {}) do if pin.rec==rec and pin:IsShown() then return pin end end
end
local measured

test("idle markers retain artwork and anchors while the live poll keeps its cadence",function()
	ResetCounts()
	local started=os.clock();mock.Advance(10,.01);local ms=(os.clock()-started)*1000
	measured={};for k,v in pairs(calls) do measured[k]=v end
	assert(calls.art==0 and calls.position==0,"unchanged pins cause no texture or anchor writes")
	assert(calls.rebuild>=40,"native quest and service data still refresh at the existing 0.2-second cadence")
	for _,rec in ipairs(merchants) do assert(Find(rec),"all three merchants remain usable") end
	io.write(("        10s idle stress: %d readiness checks, %d tracking reads, %d artwork writes, %d anchor writes; %.1f ms mock CPU\n"):format(calls.ready,calls.tracking,calls.art,calls.position,ms))
end)

test("duplicate quest copies share validation and avoid tooltip-title API calls",function()
	assert(measured.ready<1000,"five quests with 500 pins must not repeat validation 20,000 times")
	assert(measured.title==0,"minimap ownership/positions do not request tooltip titles")
	assert(ns.QuestTurnIns:GetForMap(1429)[1].questName=="Quest title 1","normal tooltip/title interface remains intact")
end)

test("tracking checks are event driven with a low-cost compatibility fallback",function()
	assert(measured.tracking<30 and measured.filter<30,"idle tracking is not enumerated five times per second")
	local before=calls.tracking
	active[1]=true;mock.Fire("MINIMAP_UPDATE_TRACKING");mock.Advance(.03,.01)
	assert(active[1] and calls.tracking>before,"native service selections stay enabled after their event")
	C_Minimap.SetTracking(2,true)
	assert(ns:IsCategoryEnabled("repair"),"external native checkbox edits update Wayfinder immediately")
	mock.Advance(.03,.01)
	assert(active[2],"native service blips remain enabled on the next frame")
	active[2]=false;mock.Advance(2.2,.01)
	assert(active[2],"compatibility fallback retains the selected native category")
end)

test("movement, rotation and zoom still reposition minimap pins at the normal cadence",function()
	ResetCounts()
	local pin=assert(Find(merchants[1]));local px,py=pin.px,pin.py
	mock.playerX=mock.playerX+.001;mock.Advance(.25,.01)
	assert(pin.px~=px or pin.py~=py,"moving the player repositions services")
	px,py=pin.px,pin.py;rotate=true;mock.facing=1.5;mock.Advance(.25,.01)
	assert(pin.px~=px or pin.py~=py,"rotation remains live")
	px,py=pin.px,pin.py;radius=90;mock.Fire("MINIMAP_UPDATE_ZOOM");mock.Advance(.25,.01)
	assert(pin.px~=px or pin.py~=py,"zoom projects positions using the new radius")
	assert(calls.position>0 and calls.art==0,"movement updates geometry while retaining unchanged artwork")
	for _,rec in ipairs(merchants) do assert(Find(rec)) end
end)

test("category changes hide and restore cached pins and refresh changed artwork",function()
	ns:SetCategoryEnabled("vendor",false);mock.Advance(.03,.01)
	for _,rec in ipairs(merchants) do assert(not Find(rec),"category hide applies on the next frame") end
	ns:SetCategoryEnabled("vendor",true);mock.Advance(.03,.01)
	for _,rec in ipairs(merchants) do assert(Find(rec),"cached pins return after enabling the category") end
	local rec=merchants[2]
	ResetCounts()
	ns.Database:RecordNPC({npcID=rec.id,name=rec.n,cats={repair=true},cont=rec.c,wx=rec.x,wy=rec.y,mapID=rec.m,accuracy=1})
	mock.Advance(.03,.01)
	assert(not Find(rec) and active[2],"native repair blip replaces the custom marker without duplicate artwork")
	rec.cats.repair=nil
	ns:Fire("POI_UPDATED",rec);mock.Advance(.03,.01)
	assert(Find(rec),"custom vendor marker returns when native tracking cannot represent the service")
end)

test("quest changes restore and suppress fixed fallbacks without delaying native tracking",function()
	local id=810001
	mock.readyQuests[id]=false;mock.Fire("QUEST_LOG_UPDATE");mock.Advance(.5,.01)
	for _,f in ipairs(questFrames) do if f.data.Id==id then assert(not f.hidden,"quest ceasing to be ready restores its fallback") end end
	mock.readyQuests[id]=true;mock.Fire("QUEST_POI_UPDATE");mock.Advance(.5,.01)
	for _,f in ipairs(questFrames) do if f.data.Id==id then assert(f.hidden,"ready native location suppresses every duplicate") end end
	assert(active[3] and active[4],"native quests and gathering stay enabled")
end)

test("native quest movement is read live even without an accompanying event",function()
	local rec=merchants[2]
	local nx,ny=ns.WorldToMapRect(ns.GetMapRect(1429),rec.x,rec.y)
	mock.questPOIs[1429][1].x,mock.questPOIs[1429][1].y=nx,ny
	mock.Advance(.25,.01)
	assert(not Find(rec),"live native quest position takes precedence over the overlapping service")
	mock.questPOIs[1429][1].x,mock.questPOIs[1429][1].y=.7,.7
	mock.Advance(.25,.01)
	assert(Find(rec),"moving away restores the merchant on the next poll")
end)
test("quest events invalidate readiness cached by a suspended ownership batch",function()
	mock.DrainBackground()
	local profile,refresh,get=debugprofilestop,ns.MinimapTurnIns.RefreshFrame,ns.QuestTurnIns.GetForMap
	local clock,reads=0,0
	debugprofilestop=function() return clock end
	ns.MinimapTurnIns.RefreshFrame=function(self,...) clock=clock+.26;return refresh(self,...) end
	ns.QuestTurnIns.GetForMap=function(self,...) reads=reads+1;return get(self,...) end
	ns.MinimapTurnIns:RequestRefresh();ns.Background:Run()
	local first=reads
	mock.readyQuests[810001]=false;mock.Fire("QUEST_LOG_UPDATE");ns.Background:Run()
	local invalidated=reads>first
	debugprofilestop,ns.MinimapTurnIns.RefreshFrame,ns.QuestTurnIns.GetForMap=profile,refresh,get
	mock.DrainBackground("minimap ownership")
	assert(first>0 and invalidated,"the next resumed slice must re-read readiness after a quest event")
	for _,f in ipairs(questFrames) do if f.data.Id==810001 then assert(not f.hidden) end end
end)
assert(#mock.errors==0,"no asynchronous Lua errors")
io.write("\n",passed," idle efficiency checks passed, ",failed," failed\n")
return failed
