local ns, map = Wayfinder, WorldMapFrame
local S, Fog = ns.ContinuousEngine.MapStitch, ns.WorldFog
local controller = ns.ContinuousEngine:GetModule("worldmap")
local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then passed=passed+1; io.write("  ok    ",name,"\n")
	else failed=failed+1; io.write("  FAIL  ",name,"\n        ",tostring(err),"\n") end
end
ns:SetSetting("importExploration",false)
ns.Exploration:Reset()
local cont, wx, wy = ns.MapToWorld(1429,.8,.8)
local col,row = ns.WorldToTile(wx,wy)
local ox,oy = ns.TileOrigin(col,row)
wx,wy = ns.PlaneToWorld(ox+8.5*ns.CELL,oy+8.5*ns.CELL)
local u,v = S.FromYards(cont,wx,wy)
local function Show(zoom)
	map:Show(); controller.ShowNow(u,v,zoom); mock.Advance(.2)
end
local function Covering()
	local W,H = S.Size()
	local result = {}
	for _,tex in ipairs(Fog.frame.textures) do
		local point = tex.points.TOPLEFT
		if tex:IsShown() and point and u*W >= point[3] and u*W < point[3]+tex:GetWidth()
			and v*H >= -point[4] and v*H < -point[4]+tex:GetHeight() then result[#result+1]=tex end
	end
	return result
end
test("unexplored painted maps are dark before terrain zoom",function()
	Show(10)
	assert(not ns.DetailView:IsFollowingMap())
	assert(Fog.frame:IsShown() and Fog.frame:GetFrameLevel()>S.terrainLevel)
	local fog = Covering()
	assert(#fog==1,"exactly one fog piece covers unseen map art")
	assert(math.abs(fog[1]:GetAlpha()-.6)<.00001,"uses the configured brightness")
end)
test("world and continent zoom keep unexplored map art dark",function()
	for _,zoom in ipairs({1,3,20}) do Show(zoom); assert(#Covering()==1) end
end)
test("walking reveals map art without requiring a zoom or pan",function()
	Show(10)
	ns.Exploration:MarkCircle(cont,wx,wy,120);mock.Advance(.1)
	assert(#Covering()==0,"explored centre is clear on the painted map")
end)
test("the terrain transition uses the same fog layer exactly once",function()
	ns.Exploration:Reset();mock.Advance(.1)
	Show(ns.ContinuousMap:GetMaxZoom(u,v))
	assert(ns.DetailView:IsFollowingMap() and #Covering()==1)
	for _,list in pairs(ns.DetailView.activeTiles) do
		for _,tex in ipairs(list) do assert(tex.sublevel~=2,"terrain must not add a second fog layer") end
	end
end)
test("brightness and shown mode update the entire map immediately",function()
	Show(10);ns:SetSetting("unexploredBrightness",.25);mock.Advance(.1)
	assert(math.abs(Covering()[1]:GetAlpha()-.75)<.00001)
	ns:SetSetting("unexploredTerrain",ns.UNEXPLORED_SHOWN);mock.Advance(.1)
	assert(not Fog.frame:IsShown())
	ns:SetSetting("unexploredTerrain",ns.UNEXPLORED_DARKENED);mock.Advance(.1)
	assert(Fog.frame:IsShown() and #Covering()==1)
end)
test("repeated fog refreshes reuse textures and merge empty continents",function()
	Show(1)
	local count = #Fog.frame.textures
	local visible=0
	for _,tex in ipairs(Fog.frame.textures) do if tex:IsShown() then visible=visible+1 end end
	assert(visible<=2,"unexplored continents need one rectangle each")
	for i=1,8 do Fog:Invalidate();mock.Advance(.1) end
	assert(#Fog.frame.textures==count,"refreshes cannot grow the texture pool")
end)
test("taxi nodes and generic built-in flight locations match their NPC",function()
	local npc={id=2995,n="Tal",kind="npc",cat="flight",x=0,y=0,c=1}
	assert(ns.ServiceLocations:Same(npc,{kind="taxi",cat="flight",n="Thunder Bluff, Mulgore",x=1,y=1,c=1}))
	assert(ns.ServiceLocations:Same(npc,{seed=true,cat="flight",n="Flight master",x=15,y=0,c=1}))
	assert(not ns.ServiceLocations:Same(npc,{id=2996,cat="flight",x=1,y=1,c=1}),"different NPC identities remain distinct")
end)
test("overlapping bank and auction counters collapse only while zoomed out",function()
	for _,cat in ipairs({"bank","auction"}) do
		local a={id=1,cat=cat,x=0,y=0,c=1}
		local b={id=2,cat=cat,x=12,y=0,c=1}
		assert(ns.ServiceLocations:Overlaps(a,b,5))
		assert(not ns.ServiceLocations:Overlaps(a,b,20),"separate readable NPCs return up close")
		b.cat="vendor";assert(not ns.ServiceLocations:Overlaps(a,b,5))
	end
end)
test("overview replaces duplicate Questie service sources and restores ownership when disabled",function()
	Show(10)
	local x,y = ns.WorldToMapRect(ns.GetMapRect(1429),wx,wy)
	local rec=ns.Database:RecordNPC({npcID=890001,name="Overview banker",cats={bank=true},cont=cont,wx=wx,wy=wy,mapID=1429,accuracy=1})
	local frame=CreateFrame("Frame",nil,map:GetCanvasContainer())
	frame.data={Type="manual",id=rec.id,Name=rec.n}
	frame.isManualIcon,frame.miniMapIcon,frame.UiMapID=true,false,1429
	frame.x,frame.y=x*100,y*100
	function frame:ShouldBeHidden() return false end
	function frame:FakeHide() self.hidden=true;self:Hide() end
	function frame:FakeShow() self.hidden=false;self:Show() end
	ns.MinimapTurnIns:TagFrame(frame,"Banker",rec.id)
	ns.MinimapTurnIns:Refresh();ns.MapPins:RefreshNow()
	assert(not frame:IsShown(),"Questie's source is handed off")
	local count=0
	for pin in map:EnumeratePinsByTemplate("WayfinderMapPinTemplate") do if pin.rec.id==rec.id then count=count+1 end end
	assert(count==1,"recorded and addon copies become exactly one overview marker")
	ns:SetSetting("showOnWorldMap",false);ns.MinimapTurnIns:Refresh()
	assert(frame:IsShown(),"disabling Wayfinder restores the owner's original frame")
end)
assert(#mock.errors==0,"no asynchronous errors")
io.write("\n",passed," exploration overview checks passed, ",failed," failed\n")
return failed
