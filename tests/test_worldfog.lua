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
	ns.Exploration:MarkCircle(cont,wx,wy,600);mock.Advance(.1)
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
test("rectangular discoveries have intermediate coverage and rounded fade corners",function()
	local tiles = ns.db.explored[ns:GetCharacterKey()][cont] or {}
	ns.db.explored[ns:GetCharacterKey()][cont]=tiles
	for y=row,row+3 do for x=col,col+3 do
		local rows={};for j=1,ns.CELLS do rows[j]=65535 end
		tiles[ns.TileKey(x,y)]=rows
	end end
	Fog:Invalidate()
	for _,stride in ipairs({1,4,16}) do
		local pieces=Fog.GetPieces(cont,col,row,stride)
		local intermediate,corner=false,false
		for _,piece in ipairs(pieces) do
			local code=piece[1]
			local levels={}
			for i=1,4 do
				levels[i]=code%5;code=math.floor(code/5)
				if levels[i]>0 and levels[i]<4 then intermediate=true end
			end
			if levels[1]<levels[2] and levels[1]<levels[3] then corner=true end
		end
		assert(intermediate,"the boundary contains partial exploration coverage at stride "..stride)
		assert(corner,"the two-axis corner is feathered at stride "..stride)
	end
end)
test("blurred boundaries join continuously across tile seams",function()
	local function Sample(c,r,stride,x,y)
		local pieces=Fog.GetPieces(cont,c,r,stride)
		if not pieces then return 0 end
		for _,p in ipairs(pieces) do
			if x>=p[2] and x<p[3] and y>=p[4] and y<p[5] then
				local code=p[1]
				local tl=code%5;code=math.floor(code/5)
				local tr=code%5;code=math.floor(code/5)
				local bl=code%5;local br=math.floor(code/5)%5
				local u,v=(x-p[2])/(p[3]-p[2]),(y-p[4])/(p[5]-p[4])
				return (tl*(1-u)*(1-v)+tr*u*(1-v)+bl*(1-u)*v+br*u*v)/4
			end
		end
		return 1
	end
	for _,stride in ipairs({1,4,16}) do
		for y=stride/2,ns.CELLS,stride/3 do
			local left=Sample(col-1,row,stride,ns.CELLS+stride/2-.000001,y)
			local right=Sample(col,row,stride,stride/2,y)
			assert(math.abs(left-right)<.00001,"no hard seam between neighbouring patches")
		end
	end
end)
test("exploration changes invalidate blurred neighbours beyond the old single-tile edge",function()
	local original=Fog.GetPieces(cont,col-1,row,16)
	local tiles=ns.db.explored[ns:GetCharacterKey()][cont]
	tiles[ns.TileKey(col,row)]=nil
	Fog:Invalidate(cont,{ns.TileKey(col,row)})
	local updated=Fog.GetPieces(cont,col-1,row,16)
	assert(original~=updated,"a live discovery updates neighbouring filtered coverage")
	ns.Exploration:Reset();mock.Advance(.1)
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
