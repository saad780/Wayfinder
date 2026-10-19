-- Moving terrain needs frame-synchronous projection, independent of data scans.
local ns,Mini=Wayfinder,Wayfinder.MinimapServices
local passed,failed=0,0
local function test(name,fn)
	local ok,err=pcall(fn)
	if ok then passed=passed+1;io.write("  ok    ",name,"\n")
	else failed=failed+1;io.write("  FAIL  ",name,"\n        ",tostring(err),"\n") end
end
local function near(a,b) assert(math.abs(a-b)<1e-7,tostring(a).." != "..tostring(b)) end
ns.db.settings.importExploration=false
WorldMapFrame:Hide()
Minimap=CreateFrame("Frame",nil,UIParent);Minimap:SetSize(200,200)
mock.playerMap,mock.playerX,mock.playerY=1429,.8,.8
local cont,wx,wy=ns.MapToWorld(1429,.8,.8)
local pose={c=cont,x=wx,y=wy}
local rotate,square,radius=false,false,120
UnitPosition=function() return pose.x,pose.y,0,pose.c end
GetCVarBool=function(key) return key=="rotateMinimap" and rotate end
GetMinimapShape=function() return square and "SQUARE" or "ROUND" end
C_Minimap.GetViewRadius=function() return radius end
local rec=ns.Database:RecordNPC({npcID=890001,name="Fixed world merchant",cats={vendor=true},cont=cont,wx=wx+30,wy=wy-10,mapID=1429,accuracy=1})
Mini:Update();mock.Advance(.05,.01)
local function Pin(record)
	for _,pin in ipairs(Mini.pins) do if pin.rec==record then return pin end end
end
local pin=assert(Pin(rec))
local counts={rebuild=0,query=0,quests=0,art=0,writes=0,positionReads=0}
local function Reset() for key in pairs(counts) do counts[key]=0 end end
local rebuild,query,quests,art,point,direct=Mini.Rebuild,ns.Database.Query,C_QuestLog.GetQuestsOnMap,ns.Categories.ApplyIcon,pin.SetPoint,UnitPosition
Mini.Rebuild=function(self,...) counts.rebuild=counts.rebuild+1;return rebuild(self,...) end
ns.Database.Query=function(self,...) counts.query=counts.query+1;return query(self,...) end
C_QuestLog.GetQuestsOnMap=function(...) counts.quests=counts.quests+1;return quests(...) end
ns.Categories.ApplyIcon=function(self,...) counts.art=counts.art+1;return art(self,...) end
pin.SetPoint=function(self,...) counts.writes=counts.writes+1;return point(self,...) end
UnitPosition=function(...) counts.positionReads=counts.positionReads+1;return direct(...) end
local function Frame()
	mock.time=mock.time+1/120
	Mini.motionFrame.scripts.OnUpdate(Mini.motionFrame,1/120)
end
local function Fresh()
	Mini:Update();Reset()
end

test("icons stay fixed to world locations on every movement frame between data scans",function()
	Fresh()
	local initialX,initialY=rec.x,rec.y
	for i=1,16 do
		-- The normalized map position deliberately stays stale while direct
		-- player position advances, matching a coarse map API update cadence.
		pose.x,pose.y=wx+i*.2,wy+i*.3
		Frame()
		near(pin.px,(pose.y-rec.y)/radius*100)
		near(pin.py,(rec.x-pose.x)/radius*100)
	end
	assert(rec.x==initialX and rec.y==initialY,"movement never changes the NPC's saved world position")
	assert(counts.writes==16,"each rendered movement frame has the right screen position")
	assert(counts.rebuild==0 and counts.query==0 and counts.quests==0 and counts.art==0,"motion does not refresh data or artwork")
end)

test("stationary cached icons perform no repeated anchor or artwork writes",function()
	Fresh()
	for _=1,30 do Frame() end
	assert(counts.writes==0 and counts.art==0 and counts.query==0 and counts.quests==0)
	assert(counts.positionReads==30,"only one direct player-position sample per rendered frame")
end)

test("rotating minimaps project every facing change without rescanning",function()
	rotate=true;mock.facing=0;Fresh()
	for i=1,10 do
		mock.facing=i*.1;Frame()
		local east,north=pose.y-rec.y,rec.x-pose.x
		near(pin.px,(east*math.cos(mock.facing)+north*math.sin(mock.facing))/radius*100)
		near(pin.py,(north*math.cos(mock.facing)-east*math.sin(mock.facing))/radius*100)
	end
	assert(counts.writes==10 and counts.query==0 and counts.art==0)
	rotate=false;mock.facing=0;Fresh()
end)

test("cached markers enter and leave the minimap edge without waiting for a data refresh",function()
	pose.x,pose.y=wx,wy
	local safe=radius*(1-8/100)
	local entering=ns.Database:RecordNPC({npcID=890002,name="Entering merchant",cats={vendor=true},cont=cont,wx=wx+safe+5,wy=wy,mapID=1429,accuracy=1})
	local leaving=ns.Database:RecordNPC({npcID=890003,name="Leaving merchant",cats={vendor=true},cont=cont,wx=wx-safe+2,wy=wy,mapID=1429,accuracy=1})
	Fresh()
	local a,b=assert(Pin(entering)),assert(Pin(leaving))
	assert(not a:IsShown() and b:IsShown(),"off-edge sources are cached without being drawn")
	pose.x=wx+8;Frame()
	assert(a:IsShown() and not b:IsShown(),"edge visibility follows the same movement frame")
	assert(counts.rebuild==0 and counts.query==0 and counts.quests==0)
end)

test("zoom and size changes reproject cached coordinates immediately",function()
	Fresh()
	radius=100;mock.Fire("MINIMAP_UPDATE_ZOOM");Frame()
	near(pin.px,(pose.y-rec.y)/radius*100)
	near(pin.py,(rec.x-pose.x)/radius*100)
	Minimap:SetSize(240,180)
	Minimap.scripts.OnSizeChanged(Minimap,240,180);Frame()
	near(pin.px,(pose.y-rec.y)/radius*120)
	near(pin.py,(rec.x-pose.x)/radius*90)
	assert(counts.query==0 and counts.quests==0 and counts.art==0)
	Minimap:SetSize(200,200);radius=120;Fresh()
end)

test("animated radius changes track terrain on every frame without a zoom event",function()
	Fresh()
	for i=1,12 do
		radius=120-i*.25;Frame()
		near(pin.px,(pose.y-rec.y)/radius*100)
		near(pin.py,(rec.x-pose.x)/radius*100)
	end
	assert(counts.query==0 and counts.art==0,"radius animation only reprojects cached pins")
	radius=120;Fresh()
end)

test("square minimap clipping and long-distance relocation keep the cache bounded",function()
	square=true;Fresh()
	local x,y=pin.px,pin.py
	assert(pin:IsShown())
	pose.x,pose.y=wx+10000,wy+10000;Frame()
	assert(not pin:IsShown() and Mini.pending,"relocation hides stale local pins and requests one new scan")
	pose.x,pose.y=wx,wy;square=false;Fresh()
end)

test("restricted or missing direct position APIs fall back to map coordinates",function()
	local original=UnitPosition
	UnitPosition=function() return mock.SECRET,mock.SECRET,0,mock.SECRET end
	mock.playerX,mock.playerY=.8,.8
	local _,x,y=ns.GetPlayerWorld()
	Fresh();Frame()
	near(pin.px,(y-rec.y)/radius*100);near(pin.py,(rec.x-x)/radius*100)
	UnitPosition=function() error("position unavailable") end
	Frame()
	assert(pin:IsShown(),"a failing direct API retains the working map-coordinate fallback")
	UnitPosition=original
end)

test("hidden or disabled minimaps stop movement work",function()
	Fresh()
	Minimap:Hide();Frame()
	assert(counts.positionReads==0 and counts.writes==0,"hidden map needs no position work")
	Minimap:Show()
	ns:SetSetting("showMinimapServices",false);Mini:Update();Reset()
	assert(not Mini.motionFrame:IsShown() and not pin:IsShown())
	Frame();assert(counts.positionReads==0,"disabled overlay has no movement updates")
end)
assert(#mock.errors==0,"no asynchronous Lua errors")
io.write("\n",passed," smooth minimap checks passed, ",failed," failed\n")
return failed
