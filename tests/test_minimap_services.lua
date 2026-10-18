local ns, Mini = Wayfinder, Wayfinder.MinimapServices
local passed, failed = 0, 0
local old = { map = mock.playerMap, x = mock.playerX, y = mock.playerY, minimap = Minimap,
	count = C_Minimap.GetNumTrackingTypes, filter = C_Minimap.GetTrackingFilter,
	info = C_Minimap.GetTrackingInfo, set = C_Minimap.SetTracking,
	setting = ns:GetSetting("showMinimapServices"), cvar = GetCVarBool, facing = mock.facing }
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then passed=passed+1; io.write("  ok    ",name,"\n")
	else failed=failed+1; io.write("  FAIL  ",name,"\n        ",tostring(err),"\n") end
end
local function near(a,b) assert(math.abs(a-b)<0.00001, tostring(a).." != "..tostring(b)) end
Minimap = CreateFrame("Frame", nil, UIParent)
Minimap:SetSize(200,200)
local filters = { Enum.MinimapTrackingFilter.Banker, Enum.MinimapTrackingFilter.Repair, 90000001, 90000002 }
local active = {true,true,true,true}
C_Minimap.GetNumTrackingTypes = function() return 4 end
C_Minimap.GetTrackingFilter = function(i) return {filterID=filters[i]} end
C_Minimap.GetTrackingInfo = function(i) return {active=active[i],name=({"Bankers","Repair","Quest turn-ins","Find Minerals"})[i]} end
C_Minimap.SetTracking = function(i,value) active[i]=value end
mock.playerMap,mock.playerX,mock.playerY = 1429,0.8,0.8
local cont,wx,wy = ns.MapToWorld(1429,0.8,0.8)
local function Find(rec)
	local result={}
	for _,pin in ipairs(Mini.pins or {}) do if pin.rec==rec and pin:IsShown() then result[#result+1]=pin end end
	return result
end
local rec
test("a merchant who repairs receives one Wayfinder minimap marker", function()
	rec=ns.Database:RecordNPC({npcID=887761,name="Minimap repairer",cats={vendor=true},cont=cont,wx=wx+12,wy=wy-10,mapID=1429,accuracy=1})
	local merged=ns.Database:RecordNPC({npcID=887761,name="Minimap repairer",cats={repair=true},cont=cont,wx=wx+12,wy=wy-10,mapID=1429,accuracy=1})
	assert(merged==rec,"same NPC merges its services")
	Mini:Update()
	local pins=Find(rec)
	assert(#pins==1 and pins[1].catID=="repair","one repair icon rather than separate merchant/repair markers")
	assert(Mini:IsActive())
	near(pins[1].points.CENTER[3],10/120*100)
	near(pins[1].points.CENTER[4],12/120*100)
end)
test("native service duplicates are disabled while quest and gathering tracking stay enabled", function()
	assert(active[1]==false and active[2]==false,"duplicate native services suppressed")
	assert(active[3] and active[4],"native quest movement and minerals untouched")
end)
test("minimap rotation and middle-click use the NPC position", function()
	GetCVarBool=function(key) return key=="rotateMinimap" end
	mock.facing=math.pi/2
	Mini:Update()
	local pin=Find(rec)[1]
	near(pin.points.CENTER[3],12/120*100)
	near(pin.points.CENTER[4],-10/120*100)
	pin.scripts.OnClick(pin,"MiddleButton")
	local waypoint=ns.Navigation:GetWaypoint()
	near(waypoint.x,rec.x); near(waypoint.y,rec.y)
	GetCVarBool=old.cvar
end)
test("only other-addon minimap services are suppressed, including merchant/repair copies", function()
	local map={manualFrames={Repair={[rec.id]={"WayfinderServiceTestMini","WayfinderServiceTestWorld"}}}}
	for _,case in ipairs({{"WayfinderServiceTestMini",true},{"WayfinderServiceTestWorld",false}}) do
		local frame=CreateFrame("Frame",case[1],Minimap)
		frame.data={Type="manual",id=rec.id}
		frame.isManualIcon,frame.miniMapIcon=true,case[2]
		function frame:ShouldBeHidden() return false end
		function frame:FakeHide() self.hidden=true; self:Hide() end
		function frame:FakeShow() self.hidden=false; self:Show() end
	end
	ns.MinimapTurnIns:ObserveManualFrames(map,"Repair",rec.id)
	ns.MinimapTurnIns:Refresh()
	assert(not WayfinderServiceTestMini:IsShown(),"other minimap repair icon hidden")
	assert(WayfinderServiceTestWorld:IsShown(),"world-map repair icon unchanged")
	WayfinderServiceTestMini.data={Type="monster",Id=887762}
	ns.MinimapTurnIns:Refresh()
	assert(WayfinderServiceTestMini:IsShown(),"recycled quest objective is not treated as a service")
end)
test("disabling Wayfinder services restores native tracking and hides its own pins", function()
	ns:SetSetting("showMinimapServices",false)
	Mini:Update()
	assert(not Mini:IsActive() and #Find(rec)==0)
	assert(active[1] and active[2] and active[3] and active[4],"original native preferences restored")
end)
test("unrecorded visible merchant/repair locations get one temporary Wayfinder replacement", function()
	ns:SetSetting("showMinimapServices",true)
	local id=887779
	local x,y=ns.WorldToMapRect(ns.GetMapRect(1429),wx-24,wy-30)
	local map={manualFrames={}}
	for _,typ in ipairs({"Repair","Vendor"}) do
		local frame=CreateFrame("Frame","WayfinderUnrecorded"..typ,Minimap)
		frame.data={Type="manual",id=id,Name="Unrecorded repair merchant"}
		frame.isManualIcon,frame.miniMapIcon,frame.UiMapID=true,true,1429
		frame.x,frame.y=x*100,y*100
		function frame:ShouldBeHidden() return false end
		function frame:FakeHide() self.hidden=true; self:Hide() end
		function frame:FakeShow() self.hidden=false; self:Show() end
		map.manualFrames[typ]={[id]={frame:GetName()}}
		ns.MinimapTurnIns:ObserveManualFrames(map,typ,id)
	end
	ns.MinimapTurnIns:Refresh()
	Mini:Update()
	local count=0
	for _,pin in ipairs(Mini.pins) do
		if pin:IsShown() and pin.rec.id==id then
			count=count+1
			assert(pin.catID=="repair" and pin.rec.ephemeral,"temporary combined service uses repair priority")
		end
	end
	assert(count==1,"two foreign service pins become one Wayfinder marker")
	assert(not ns.Database:FindNearest(cont,wx-24,wy-30,3,function(rec) return rec.id==id end),"temporary locations are not imported")
	for _,pin in ipairs(Mini.pins) do
		if pin:IsShown() and pin.rec.id==id then
			mock.shift=true
			pin.scripts.OnClick(pin,"LeftButton")
			mock.shift=false
			break
		end
	end
	Mini:Update()
	for _,pin in ipairs(Mini.pins) do assert(not pin:IsShown() or pin.rec.id~=id,"temporary replacement can be hidden without importing it") end
	ns:SetSetting("showMinimapServices",false)
end)
test("golden native quests stay visible above overlapping minimap services", function()
	ns:SetSetting("showMinimapServices",true)
	local id=887790
	local x,y=ns.WorldToMapRect(ns.GetMapRect(1429),rec.x+3,rec.y)
	local previousPOIs=mock.questPOIs[1429]
	mock.questPOIs[1429]={{questID=id,x=x,y=y}}
	mock.questLog[id],mock.readyQuests[id]=true,true
	Mini:Update()
	assert(#Find(rec)==0,"service button yields to the native golden question mark")
	assert(active[3],"native quest tracking remains enabled")
	mock.questPOIs[1429]=previousPOIs
	mock.questLog[id],mock.readyQuests[id]=nil,nil
	Mini:Update()
	assert(#Find(rec)==1,"service returns once the quest is gone")
end)
test("available quest markers take precedence over the same NPC's minimap service", function()
	local id=887791
	rec.cats.quest=true
	ns.QuestAvailability:Observe(rec,{{questID=id}},true)
	Mini:Update()
	assert(#Find(rec)==0,"verified available quest wins over merchant/repair")
	ns.QuestAvailability:Observe(rec,{},true)
	local x,y=ns.WorldToMapRect(ns.GetMapRect(1429),rec.x,rec.y)
	local frame=CreateFrame("Frame",nil,Minimap)
	frame.data={Type="available",Id=id,Name=rec.n}
	frame.miniMapIcon,frame.UiMapID,frame.x,frame.y=true,1429,x*100,y*100
	function frame:ShouldBeHidden() return self.filtered==true end
	ns.MinimapTurnIns:ObserveFrame(frame)
	Mini:Update()
	assert(#Find(rec)==0,"visible third-party pickup also wins")
	frame.filtered=true
	Mini:Update()
	assert(#Find(rec)==1,"owner-filtered quest does not hide the service")
	frame:Hide()
end)
test("three distinct merchants remain visible across minimap zoom levels near a quest giver",function()
	local id=887792
	local others={rec}
	for i,offset in ipairs({{-30,-35},{-20,35}}) do
		others[#others+1]=ns.Database:RecordNPC({npcID=887800+i,name="Zoom regression merchant "..i,cats={vendor=true},cont=cont,wx=wx+offset[1],wy=wy+offset[2],mapID=1429,accuracy=1})
	end
	local x,y=ns.WorldToMapRect(ns.GetMapRect(1429),rec.x+22,rec.y)
	local previousPOIs,previousRadius=mock.questPOIs[1429],C_Minimap.GetViewRadius
	mock.questPOIs[1429]={{questID=id,x=x,y=y}}
	mock.questLog[id],mock.readyQuests[id]=true,true
	local counts={}
	for _,radius in ipairs({220,120,220,120}) do
		C_Minimap.GetViewRadius=function() return radius end
		Mini:Update()
		local count=0
		for _,merchant in ipairs(others) do count=count+#Find(merchant) end
		counts[#counts+1]=count
	end
	C_Minimap.GetViewRadius, mock.questPOIs[1429]=previousRadius,previousPOIs
	mock.questLog[id],mock.readyQuests[id]=nil,nil
	Mini:Update()
	for _,count in ipairs(counts) do assert(count==3,"a different merchant must not disappear when zooming out near a quest marker") end
end)
test("quest-giver identity preserves neighbouring NPCs and consistently replaces the giver's own service",function()
	local id=887793
	local previousPOIs,previousRadius=mock.questPOIs[1429],C_Minimap.GetViewRadius
	mock.questLog[id],mock.readyQuests[id]=true,true
	local frame=CreateFrame("Frame",nil,Minimap)
	frame.miniMapIcon,frame.UiMapID=true,1429
	frame.data={Type="complete",Id=id}
	function frame:ShouldBeHidden() return self.filtered==true end
	ns.MinimapTurnIns:ObserveFrame(frame)
	local results={}
	for _,case in ipairs({{name="A different quest giver",offset=1,visible=true},{name=rec.n,offset=18,visible=false}}) do
		local x,y=ns.WorldToMapRect(ns.GetMapRect(1429),rec.x+case.offset,rec.y)
		mock.questPOIs[1429]={{questID=id,x=x,y=y}}
		frame.x,frame.y,frame.data.Name=x*100,y*100,case.name
		for _,radius in ipairs({220,120}) do
			C_Minimap.GetViewRadius=function() return radius end
			Mini:Update()
			results[#results+1]={actual=#Find(rec)>0,expected=case.visible}
		end
	end
	frame:Hide()
	C_Minimap.GetViewRadius,mock.questPOIs[1429]=previousRadius,previousPOIs
	mock.questLog[id],mock.readyQuests[id]=nil,nil
	Mini:Update()
	for _,result in ipairs(results) do assert(result.actual==result.expected,"identity, rather than pixel overlap, decides which service the quest replaces") end
end)
local function ForeignService(id,name,x,y,typ)
	local frame=CreateFrame("Frame","WayfinderLocationSource"..id.."_"..tostring(x).."_"..typ,Minimap)
	frame.data={Type="manual",id=id,Name=name}
	frame.isManualIcon,frame.miniMapIcon,frame.UiMapID=true,true,1429
	frame.x,frame.y=x*100,y*100
	function frame:ShouldBeHidden() return self.filtered==true end
	function frame:FakeHide() self.hidden=true; self:Hide() end
	function frame:FakeShow() self.hidden=false; self:Show() end
	local map={manualFrames={[typ]={[id]={frame:GetName()}}}}
	ns.MinimapTurnIns:ObserveManualFrames(map,typ,id)
	return frame
end
test("temporary service locations are matched to recorded NPCs before nearby spawns are combined",function()
	local id=887810
	local anchor=ns.Database:RecordNPC({npcID=id,name="Multi-location merchant",cats={repair=true},cont=cont,wx=wx-15,wy=wy+10,mapID=1429,accuracy=1})
	local frames={}
	for _,offset in ipairs({22,26,60}) do
		local x,y=ns.WorldToMapRect(ns.GetMapRect(1429),anchor.x+offset,anchor.y)
		for _,typ in ipairs({"Repair","Vendor"}) do frames[#frames+1]=ForeignService(id,anchor.n,x,y,typ) end
	end
	local candidates={}
	ns.MinimapTurnIns:QueryServices(cont,wx-120,wx+120,wy-120,wy+120,function(item)
		if item.id==id then candidates[#candidates+1]=item end
	end)
	Mini:Update()
	local displayed={}
	for _,pin in ipairs(Mini.pins) do
		if pin:IsShown() and pin.rec.id==id then displayed[#displayed+1]=pin.rec end
	end
	for _,frame in ipairs(frames) do frame.filtered=true end
	for _,frame in ipairs(frames) do frame:Hide() end
	assert(#candidates==3,"preserve three distinct source locations while combining repair/vendor copies at each exact location")
	assert(#displayed==3,"recorded anchor plus two distinct service locations, independent of source iteration order")
end)
test("nearby merchants with different NPC IDs are never discarded as service duplicates",function()
	local anchor=ns.Database:RecordNPC({npcID=887811,name="Recorded nearby merchant",cats={repair=true},cont=cont,wx=wx-35,wy=wy-10,mapID=1429,accuracy=1})
	local x,y=ns.WorldToMapRect(ns.GetMapRect(1429),anchor.x+5,anchor.y)
	local frame=ForeignService(887812,"Different nearby merchant",x,y,"Repair")
	Mini:Update()
	local count=0
	for _,pin in ipairs(Mini.pins) do
		if pin:IsShown() and (pin.rec==anchor or pin.rec.id==887812) then count=count+1 end
	end
	frame.filtered=true; frame:Hide()
	assert(count==2,"different NPC IDs five yards apart are two merchants, not duplicate copies")
end)
ns.db.settings.showMinimapServices=old.setting
Minimap=old.minimap
Mini:Update()
C_Minimap.GetNumTrackingTypes,C_Minimap.GetTrackingFilter,C_Minimap.GetTrackingInfo,C_Minimap.SetTracking=old.count,old.filter,old.info,old.set
GetCVarBool,mock.facing=old.cvar,old.facing
mock.playerMap,mock.playerX,mock.playerY=old.map,old.x,old.y
io.write("\n",passed," minimap service checks passed, ",failed," failed\n")
return failed
