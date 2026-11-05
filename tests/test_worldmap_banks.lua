local ns,map,sc=Wayfinder,WorldMapFrame,WorldMapFrame.ScrollContainer
local C,S=ns.ContinuousMap,ns.ContinuousEngine.MapStitch
local controller=ns.ContinuousEngine:GetModule("worldmap")
local passed,failed=0,0
local function test(name,fn)
	local ok,err=pcall(fn)
	if ok then passed=passed+1;io.write("  ok    ",name,"\n")
	else failed=failed+1;io.write("  FAIL  ",name,"\n        ",tostring(err),"\n") end
end
ns:SetSetting("importExploration",false)
mock.playerMap,mock.playerX,mock.playerY=1429,.8,.8
local c,x,y=ns.GetPlayerWorld()
local bank=ns.Database:RecordNPC({npcID=897301,name="Banker at the player",cats={bank=true},cont=c,wx=x,wy=y,mapID=1429,accuracy=1})
local auction=ns.Database:RecordNPC({npcID=897302,name="Auctioneer at the player",cats={auction=true},cont=c,wx=x,wy=y,mapID=1429,accuracy=1})
local u,v=C.API.WorldFromMap(1429,.8,.8)
local cap=C:GetMaxZoom(u,v)
local function Show(zoom)
	map:Show();controller.ShowNow(u,v,zoom);mock.Advance(.2);ns.MapPins:RefreshNow()
end
test("ordinary world-map bank and auction pins stay beside the player instead of underneath it",function()
	Show(cap*140/5500)
	assert(not ns.DetailView:IsFollowingMap())
	local found={}
	for _,pin in ipairs(map.pins) do if pin.rec==bank or pin.rec==auction then found[pin.catID]=pin end end
	assert(found.bank and found.auction,"both service categories remain present")
	local px,py=C.API.CanvasFromWorldPos(c,x,y)
	local rect=sc:GetViewRect()
	local bx=select(1,found.bank:GetPosition())
	local ax=select(1,found.auction:GetPosition())
	assert((bx-px)/(rect.right-rect.left)*sc:GetWidth()<=-25)
	assert((ax-px)/(rect.right-rect.left)*sc:GetWidth()>=25)
	assert(found.bank:GetFrameLevel()>ns.WorldFog.frame:GetFrameLevel())
end)
test("terrain detail keeps both services clear of the maximum-zoom player arrow",function()
	Show(cap)
	assert(ns.DetailView:IsFollowingMap())
	local found={}
	local function Walk(frame)
		for _,child in ipairs(frame.children) do
			if child:IsVisible() and (child.rec==bank or child.rec==auction) then found[child.catID]=child end
			Walk(child)
		end
	end
	Walk(WayfinderDetailView)
	assert(found.bank and found.auction)
	assert(found.bank.points.CENTER[3]<=sc:GetWidth()/2-25)
	assert(found.auction.points.CENTER[3]>=sc:GetWidth()/2+25)
	assert(bank.x==x and bank.y==y and auction.x==x and auction.y==y,"visual offsets never move saved locations")
end)
test("zooming back out restores both overview markers",function()
	Show(cap*140/5500)
	local count=0
	for _,pin in ipairs(map.pins) do if pin.rec==bank or pin.rec==auction then count=count+1 end end
	assert(count==2,"the detail handoff does not lose or duplicate either service")
end)
assert(#mock.errors==0,"no asynchronous errors")
io.write("\n",passed," bank and auction world-map checks passed, ",failed," failed\n")
return failed
