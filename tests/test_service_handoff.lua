-- Questie's manual services do not use its generic quest-ID predicate. Model
-- its real FakeHide/FakeShow lifecycle, including closing/reopening the map.
local ns,Sources=Wayfinder,Wayfinder.MinimapTurnIns
local passed,failed=0,0
local function test(name,fn)
	local ok,err=pcall(fn)
	if ok then passed=passed+1;io.write("  ok    ",name,"\n")
	else failed=failed+1;io.write("  FAIL  ",name,"\n        ",tostring(err),"\n") end
end
ns:SetSetting("importExploration",false)
WorldMapFrame:SetMapID(1429);WorldMapFrame:Show()
Minimap=CreateFrame("Frame",nil,UIParent);Minimap:SetSize(200,200)
mock.playerMap,mock.playerX,mock.playerY=1429,.8,.8
local c,x,y=ns.GetPlayerWorld()
local predicateCalls=0
local function QuestPredicate() predicateCalls=predicateCalls+1;return true end
Sources.installed={private={ShouldBeHidden=QuestPredicate}}
Questie={db={profile={enabled=true,enableMapIcons=true,enableMiniMapIcons=true,hideUntrackedQuestsMapIcons=true}}}
local frames={}
for i,typ in ipairs({"Banker","Auctioneer","Vendor","Repair","Innkeeper","Stable Master","Profession Trainer"}) do
	local frame=CreateFrame("Frame",nil,WorldMapFrame:GetCanvasContainer())
	frame.data={Type="manual",id=897000+i,Name="Handoff service "..i}
	frame.isManualIcon,frame.miniMapIcon,frame.UiMapID=true,false,1429
	frame.x,frame.y=80+i*.05,80
	frame.ShouldBeHidden=QuestPredicate
	function frame:FakeHide()
		if not self.hidden then
			self.shouldBeShowing=self:IsShown()
			self._show,self._hide=self.Show,self.Hide
			self.Show=function(owner) owner.shouldBeShowing=true end
			self:Hide()
			self.Hide=function(owner) owner.shouldBeShowing=false end
			self.hidden=true
		end
	end
	function frame:FakeShow()
		if self.hidden then
			self.hidden=false;self.Show,self.Hide=self._show,self._hide
			if self.shouldBeShowing then self:Show() end
		end
	end
	Sources:TagFrame(frame,typ,frame.data.id)
	frames[#frames+1]=frame
end
local function Count()
	local count=0
	Sources:QueryServices(c,x-100,x+100,y-100,y+100,function(rec) if rec.id>=897001 and rec.id<=897007 then count=count+1 end end)
	return count
end
test("hidden manual sources continue supplying all seven service categories",function()
	Sources:Refresh()
	assert(Count()==7,"all indexed service types have a replacement location")
end)
test("closing the map restores services without testing NPC IDs as quests",function()
	WorldMapFrame:Hide();Sources:Refresh()
	for _,frame in ipairs(frames) do assert(not frame.hidden and frame:IsShown(),"map closing must restore the owner's service") end
	assert(predicateCalls==0,"manual service restoration never invokes quest-ID filters")
end)
test("reopening the map retains every banker, auctioneer and other service",function()
	WorldMapFrame:Show();Sources:Refresh();ns.MapPins:RefreshNow()
	assert(Count()==7,"no permanently hidden service after reopening")
	local visible={}
	for _,pin in ipairs(WorldMapFrame.pins) do
		if pin.rec and pin.rec.id then visible[pin.rec.id]=true end
	end
	for _,frame in ipairs(frames) do assert(visible[frame.data.id],"each service still has a visible map pin") end
end)
test("generic visibility checks use the manual-service policy",function()
	for _,frame in ipairs(frames) do
		frame:ShouldBeHidden()
	end
	assert(predicateCalls==0,"manual frames cannot go through generic quest filtering")
end)
test("turning off Wayfinder restores owners and turning it on recovers replacements",function()
	ns:SetSetting("showOnWorldMap",false);Sources:Refresh()
	for _,frame in ipairs(frames) do assert(frame:IsShown() and not frame.hidden) end
	ns:SetSetting("showOnWorldMap",true);Sources:Refresh();ns.MapPins:RefreshNow()
	assert(Count()==7)
end)
io.write("\n",passed," service ownership checks passed, ",failed," failed\n")
return failed
