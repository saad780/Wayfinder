-- Regression for Questie's distinct manual-icon visibility policy. Its generic
-- quest predicate rejects NPC IDs when untracked quests are hidden.
local ns,Mini,Sources=Wayfinder,Wayfinder.MinimapServices,Wayfinder.MinimapTurnIns
local passed,failed=0,0
local function test(name,fn)
	local ok,err=pcall(fn)
	if ok then passed=passed+1;io.write("  ok    ",name,"\n")
	else failed=failed+1;io.write("  FAIL  ",name,"\n        ",tostring(err),"\n") end
end
WorldMapFrame:Hide()
Minimap=CreateFrame("Frame",nil,UIParent);Minimap:SetSize(200,200)
mock.playerMap,mock.playerX,mock.playerY=1429,.8,.8
local c,x,y=ns.GetPlayerWorld()
local questPredicateCalls=0
local function QuestPredicate() questPredicateCalls=questPredicateCalls+1;return true end
Sources.installed={private={ShouldBeHidden=QuestPredicate}}
Questie={db={profile={enabled=true,enableMapIcons=true,enableMiniMapIcons=false,hideUntrackedQuestsMapIcons=true}}}
local frame=CreateFrame("Button",nil,WorldMapFrame:GetCanvasContainer())
frame.data={Type="manual",id=898101,Name="World-only service"}
frame.isManualIcon,frame.miniMapIcon,frame.UiMapID=true,false,1429
local mx,my=ns.WorldToMapRect(ns.GetMapRect(1429),x+15,y-10)
frame.x,frame.y=mx*100,my*100
frame.ShouldBeHidden=QuestPredicate
Sources:TagFrame(frame,"Vendor",frame.data.id)
local function Found()
	local result={}
	Sources:QueryServices(c,x-120,x+120,y-120,y+120,function(rec) if rec.id==frame.data.id then result[#result+1]=rec end end)
	return result
end
test("manual service locations never go through Questie's quest-ID filters",function()
	local found=Found()
	assert(#found==1 and found[1].cats.vendor and found[1].ephemeral)
	assert(questPredicateCalls==0,"manual NPC IDs must not be tested as quests")
end)
test("world-only services reach the corner minimap with no minimap copy",function()
	Mini:Update()
	local count=0
	for _,pin in ipairs(Mini.pins) do
		if pin:IsShown() and pin.rec.id==frame.data.id then count=count+1 end
	end
	assert(count==1,"visible map service supplies one temporary minimap marker")
	assert(not ns.Database:FindNearest(c,x+15,y-10,1,function(rec) return rec.id==frame.data.id end),"no third-party spawn is saved")
end)
test("canvas hiding during zoom does not discard indexed service locations",function()
	frame:GetParent():Hide()
	assert(#Found()==1,"world coordinates survive canvas visibility changes")
	frame:GetParent():Show()
end)
test("explicit owner service filters still remove indexed locations",function()
	Questie.db.profile.enableMapIcons=false
	assert(#Found()==0)
	Questie.db.profile.enableMapIcons=true;frame.hidden=true
	assert(#Found()==0,"owner FakeHide remains effective")
	frame.hidden=nil
	Questie.db.profile.enabled=false
	assert(#Found()==0,"disabled addons do not leave ghost services")
	Questie.db.profile.enabled=true
end)
test("repair-only addon sources can still appear under the selected vendor category",function()
	Sources:TagFrame(frame,"Repair",frame.data.id)
	ns:SetCategoryEnabled("repair",false);ns:SetCategoryEnabled("vendor",true)
	local found=Found()
	assert(#found==1 and ns.Categories:GetVisibleCategory(found[1])=="vendor","repair NPCs remain merchants when only vendors are selected")
	Mini:Update()
	local visible
	for _,pin in ipairs(Mini.pins) do if pin:IsShown() and pin.rec.id==frame.data.id then visible=pin end end
	assert(visible and visible.catID=="vendor")
end)
assert(#mock.errors==0,"no asynchronous Lua errors")
io.write("\n",passed," shared service visibility checks passed, ",failed," failed\n")
return failed
