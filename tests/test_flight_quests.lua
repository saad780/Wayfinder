-- A taxi-node label and an NPC's quest marker can describe the same flight
-- master at slightly different positions. Keep both roles at one location.
local ns, Mini = Wayfinder, Wayfinder.MinimapServices
local C, S = ns.ContinuousMap, ns.ContinuousEngine.MapStitch
local controller = ns.ContinuousEngine:GetModule("worldmap")
local passed, failed, flagReads = 0, 0, 0
local function check(value, message) assert(value, message) end
local function near(a, b) assert(math.abs(a-b)<.00001, tostring(a).." != "..tostring(b)) end
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then passed=passed+1; io.write("  ok    ",name,"\n")
	else failed=failed+1; io.write("  FAIL  ",name,"\n        ",tostring(err),"\n") end
end
local questID, npcID = 899301, 2226
Minimap = CreateFrame("Frame", nil, UIParent); Minimap:SetSize(200,200)
mock.playerMap, mock.playerX, mock.playerY = 1421, .4, .5
local cont, wx, wy = ns.MapToWorld(1421,.4,.5)
local npcX, npcY = wx+12, wy-20
local qx, qy = ns.WorldToMapRect(ns.GetMapRect(1421),npcX,npcY)
local active = true
C_Minimap.GetNumTrackingTypes = function() return 1 end
C_Minimap.GetTrackingFilter = function() return {filterID=Enum.MinimapTrackingFilter.TaxiNode} end
C_Minimap.GetTrackingInfo = function() return {name="Flight Masters",active=active} end
C_Minimap.SetTracking = function(_,enabled) active=enabled end
QuestieLoader = {ImportModule = function(_,name)
	if name == "QuestieDB" then return {
		npcFlags={FLIGHT_MASTER=8},
		QueryNPCSingle=function(id,field)
			check(field=="npcFlags", "flight matching must not read or import spawn datasets")
			flagReads=flagReads+1
			return id==npcID and 10 or 2
		end,
	} end
end}
local taxi=ns.Database:RecordTaxi({nodeID=899302,name="The Sepulcher, Silverpine Forest",faction=0,
	cont=cont,wx=npcX+18,wy=npcY-4,mapID=1421})
local data={Type="complete",Id=questID,Name="Karos Razok",QuestData={Finisher={NPC={npcID}}}}
local corner=CreateFrame("Frame",nil,Minimap)
corner.data,corner.miniMapIcon,corner.UiMapID,corner.x,corner.y=data,true,1421,qx*100,qy*100
function corner:ShouldBeHidden() return self.filtered==true end
function corner:FakeHide() self.hidden=true;self:Hide() end
function corner:FakeShow() self.hidden=false;self:Show() end
ns.MinimapTurnIns:ObserveFrame(corner)
mock.questLog[questID],mock.readyQuests[questID]=true,true
mock.questPOIs[1421]={{questID=questID,x=qx,y=qy}}
local frame=CreateFrame("Frame",nil,WorldMapFrame:GetCanvas())
frame:SetSize(20,20)
local source=CreateFrame("Frame",nil,frame);source:SetSize(20,20);source.data=data
frame.icon=source
local texture=source:CreateTexture(nil,"ARTWORK");texture:SetAllPoints();texture:SetTexture("quest-turn-in")
local u,v=C.API.WorldFromMap(1421,qx,qy)
function frame:GetPosition() return C.API.MapFromWorld(WorldMapFrame:GetMapID(),u,v) end
function frame:GetMap() return WorldMapFrame end
source:SetScript("OnEnter",function() GameTooltip:SetText("Quest at Karos Razok");GameTooltip:Show() end)
local function Show()
	WorldMapFrame:Show();controller.ShowNow(u,v,500);mock.Advance(.8)
	ns.AddonPins:Refresh();mock.Advance(.05)
end
local function FlightPins()
	local result={}
	for _,pin in ipairs(Mini.pins or {}) do
		if pin:IsShown() and (pin.rec==taxi or pin.sourceRec==taxi) then result[#result+1]=pin end
	end
	return result
end
local function WorldPins()
	local result={}
	local function Walk(parent)
		for _,pin in ipairs(parent.children or {}) do
			if pin:IsShown() and (pin.rec==taxi or pin.flightService==taxi or pin.external and pin.external.questID==questID) then result[#result+1]=pin end
			Walk(pin)
		end
	end
	Walk(WayfinderDetailView)
	return result
end

test("native minimap quest keeps an adjacent flight icon instead of hiding the service",function()
	ns.MinimapTurnIns:QueryQuestGivers(cont,wx-200,wx+200,wy-200,wy+200,function() end)
	check(flagReads==0,"collecting quest identities alone must not read NPC roles")
	Mini:Update()
	check(flagReads==1,"only the nearby flight candidate needs a cached NPC-role lookup")
	local pins=FlightPins()
	check(#pins==1,"flight master stays identifiable while native tracking shows the quest")
	local pin=pins[1]
	check(pin.flightQuest and pin.flightQuest.native,"flight icon shares the native quest position")
	check(not pin.questBadge or not pin.questBadge:IsShown(),"no second Lua question mark over the native one")
	near(pin.rec.x,npcX);near(pin.rec.y,npcY)
	check(pin.offsetX~=0,"service is visibly adjacent to the quest, not concealed beneath it")
	check(active,"native flight tracking stays enabled")
	pin.scripts.OnClick(pin,"MiddleButton")
	local wp=ns.Navigation:GetWaypoint();near(wp.x,npcX);near(wp.y,npcY)
	ns.Navigation:ClearWaypoint()
	check(taxi.id==nil and taxi.x==npcX+18,"display matching does not overwrite the saved taxi node")
	local previous=pin.px
	mock.playerX=.401;Mini:UpdatePositions()
	near(pin.px,previous-5/Mini.radius*100)
	near(pin.rec.x,npcX);near(pin.rec.y,npcY)
	mock.playerX=.4;Mini:UpdatePositions()
end)

test("world map retains separate flight-node and NPC quest positions",function()
	Show()
	local pins=WorldPins()
	check(#pins==2,"minimap fix must not combine the map's markers")
	local flight,quest
	for _,pin in ipairs(pins) do if pin.rec==taxi then flight=pin else quest=pin end end
	check(flight and quest,"both original sources remain visible")
	local px,py=ns.WorldToPlane(taxi.x,taxi.y);near(flight.px,px);near(flight.py,py)
	px,py=ns.WorldToPlane(npcX,npcY);near(quest.px,px);near(quest.py,py)
	quest.scripts.OnEnter(quest)
	check(GameTooltip.lines[1]=="Quest at Karos Razok","source quest tooltip is preserved")
	quest.scripts.OnLeave(quest)
end)

test("flight checkbox controls the extra role and badges are cleared when pooled pins are reused",function()
	ns:SetCategoryEnabled("flight",false);Mini:Update();mock.Advance(.1)
	check(#FlightPins()==0 and not active,"native flight checkbox and own badge turn off together")
	local pins=WorldPins()
	check(#pins==1 and not pins[1].flightService,"quest stays visible without flight role")
	check(not pins[1].questBadge or not pins[1].questBadge:IsShown(),"pooled combined badge is cleared")
	ns:SetCategoryEnabled("flight",true);Mini:Update();mock.Advance(.1)
	check(#FlightPins()==1 and active,"enabling flight restores the combined role")
end)

test("matching rejects nearby different NPCs and does not scan NPC data repeatedly",function()
	local before=flagReads
	for _=1,10 do Mini:Update();ns.AddonPins:Refresh() end
	check(flagReads==before,"NPC role is cached rather than re-read on each icon refresh")
	local copies={}
	for _=1,100 do
		local copy=CreateFrame("Frame",nil,Minimap)
		copy.data,copy.miniMapIcon,copy.UiMapID,copy.x,copy.y=data,true,1421,qx*100,qy*100
		function copy:ShouldBeHidden() return self.filtered==true end
		function copy:FakeHide() self.hidden=true;self:Hide() end
		function copy:FakeShow() self.hidden=false;self:Show() end
		ns.MinimapTurnIns:ObserveFrame(copy);copies[#copies+1]=copy
	end
	local ready,reads=ns.QuestTurnIns.IsReady,0
	ns.QuestTurnIns.IsReady=function(self,id) reads=reads+1;return ready(self,id) end
	Mini:Update()
	ns.QuestTurnIns.IsReady=ready
	for _,copy in ipairs(copies) do copy.filtered=true;copy:Hide() end
	check(reads<=3,"duplicate quest frames share readiness checks within the nearby query")
	check(not ns.FlightQuests:Matches({id=3000,n="Other flight master",x=npcX,y=npcY},
		{npcID=npcID,n="Karos Razok",x=npcX,y=npcY,turnIn=true,flightGiver=true}),"different known NPC IDs never combine")
	check(not ns.FlightQuests:Matches(taxi,{npcID=3000,n="Nearby quest giver",x=npcX,y=npcY,turnIn=true}),"a nearby unrelated quest cannot claim the taxi node")
	check(not ns.FlightQuests:Matches(taxi,{npcID=npcID,n="Karos Razok",x=npcX+100,y=npcY,turnIn=true,flightGiver=true}),"distant occurrences remain separate")
end)

test("Questie's fallback quest retains one adjacent flight icon without a second question mark",function()
	local poi=mock.questPOIs[1421];mock.questPOIs[1421]={}
	Mini:Update()
	local pins=FlightPins()
	check(#pins==1 and not pins[1].flightQuest.native,"addon fallback retains the flight role")
	ns.MinimapTurnIns:Refresh()
	check(corner:IsShown(),"original quest source returns when native tracking supplies no location")
	check(not pins[1].questBadge or not pins[1].questBadge:IsShown(),"original quest source supplies the only question mark")
	mock.questPOIs[1421]=poi
end)

test("a recorded flight master offering a quest retains both roles without Questie or native quest data",function()
	local own=ns.Database:RecordNPC({npcID=899310,name="Recorded flight master",cats={flight=true,quest=true},
		cont=cont,wx=wx+90,wy=wy-35,mapID=1421,accuracy=1})
	ns.QuestAvailability:Observe(own,{{questID=899311}},true)
	local savedLoader=QuestieLoader;QuestieLoader=nil
	Mini:Update()
	QuestieLoader=savedLoader
	local found
	for _,pin in ipairs(Mini.pins) do if pin:IsShown() and pin.sourceRec==own then found=pin end end
	check(found and found.catID=="flight" and found.questBadge:IsShown(),"verified offer uses a flight icon with its own quest badge")
end)

test("finishing the quest returns flight rendering to native tracking without a leftover badge",function()
	mock.questLog[questID],mock.readyQuests[questID],mock.questPOIs[1421]=nil,nil,nil
	corner.filtered=true;frame:Hide()
	ns:Fire("QUEST_TURN_INS_CHANGED");ns.AddonPins:Refresh();Mini:Update();mock.Advance(.1)
	check(#FlightPins()==0 and active,"ordinary native flight rendering resumes without a duplicate custom icon")
	local pins=WorldPins()
	check(#pins==1 and pins[1].rec==taxi,"map retains its ordinary flight marker")
	check(not pins[1].questBadge or not pins[1].questBadge:IsShown(),"completed quest leaves no pooled badge")
end)

check(#mock.errors==0,"no asynchronous errors")
io.write("\n",passed," flight quest checks passed, ",failed," failed\n")
return failed
