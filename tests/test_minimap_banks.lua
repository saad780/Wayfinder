local ns,Mini=Wayfinder,Wayfinder.MinimapServices
local passed,failed=0,0
local function test(name,fn)
	local ok,err=pcall(fn)
	if ok then passed=passed+1;io.write("  ok    ",name,"\n")
	else failed=failed+1;io.write("  FAIL  ",name,"\n        ",tostring(err),"\n") end
end
ns:SetSetting("importExploration",false)
WorldMapFrame:Hide()
Minimap=CreateFrame("Frame",nil,UIParent);Minimap:SetSize(200,200)
mock.playerMap,mock.playerX,mock.playerY=1429,.8,.8
local c,x,y=ns.GetPlayerWorld()
local active={true,true,true,true,true}
local filters={Enum.MinimapTrackingFilter.Banker,Enum.MinimapTrackingFilter.Auctioneer,Enum.MinimapTrackingFilter.Repair,900001,900002}
C_Minimap.GetNumTrackingTypes=function() return #filters end
C_Minimap.GetTrackingFilter=function(i) return {filterID=filters[i]} end
C_Minimap.GetTrackingInfo=function(i) return {name=({"Bankers","Auctioneers","Repair","Quests","Minerals"})[i],active=active[i]} end
C_Minimap.SetTracking=function(i,value) active[i]=value end
for _,cat in ipairs({"bank","auction","repair"}) do ns:SetCategoryEnabled(cat,true) end
local bank=ns.Database:RecordNPC({npcID=897201,name="Bank counter",cats={bank=true},cont=c,wx=x,wy=y,mapID=1429,accuracy=1})
local another=ns.Database:RecordNPC({npcID=897202,name="Second banker at counter",cats={bank=true},cont=c,wx=x+1,wy=y,mapID=1429,accuracy=1})
local auction=ns.Database:RecordNPC({npcID=897203,name="Auction counter",cats={auction=true},cont=c,wx=x,wy=y,mapID=1429,accuracy=1})
local function Pins(cat)
	local found={}
	for _,pin in ipairs(Mini.pins or {}) do if pin:IsShown() and pin.catID==cat then found[#found+1]=pin end end
	return found
end
test("active native bank and auction filters cannot make known minimap services vanish",function()
	Mini:Update()
	assert(#Pins("bank")==1 and #Pins("auction")==1,"each counter has exactly one projected marker")
	assert(not active[1] and not active[2],"no duplicate native bank or auction copies")
	assert(active[3] and active[4] and active[5],"repair, quests and gathering remain native")
	assert(ns:IsCategoryEnabled("bank") and ns:IsCategoryEnabled("auction"),"both menu selections remain enabled")
end)
test("bank and auction buttons remain readable beside the character arrow",function()
	local b,a=Pins("bank")[1],Pins("auction")[1]
	assert(b.px<=-23 and a.px>=23,"bank and auction markers use separate sides of the player")
	assert(ns.Distance(b.px,b.py,a.px,a.py)>=46)
	ns:SetSetting("clearOnArrival",false)
	b.scripts.OnClick(b,"MiddleButton")
	local wp=ns.Navigation:GetWaypoint()
	assert(wp.x==bank.x and wp.y==bank.y,"offset marker still navigates to the original world position")
	ns.Navigation:ClearWaypoint();ns:SetSetting("clearOnArrival",true)
end)
test("category toggles remove and restore the intended minimap markers",function()
	ns:SetCategoryEnabled("bank",false);Mini:Update()
	assert(#Pins("bank")==0 and #Pins("auction")==1)
	ns:SetCategoryEnabled("bank",true);Mini:Update()
	assert(#Pins("bank")==1 and #Pins("auction")==1)
end)
test("disabling Wayfinder's minimap renderer restores native bank and auction choices",function()
	ns:SetSetting("showMinimapServices",false);Mini:Update()
	assert(#Pins("bank")==0 and #Pins("auction")==0)
	assert(active[1] and active[2],"native tracking is restored when Wayfinder relinquishes these services")
end)
test("anonymous service types at the same location do not swallow each other",function()
	assert(not ns.ServiceLocations:Same({x=0,y=0,cats={bank=true}},{x=0,y=0,cats={auction=true}}))
	assert(not ns.ServiceLocations:Same({x=0,y=0,cat="bank"},{x=0,y=0,cat="auction"}))
end)
io.write("\n",passed," bank and auction minimap checks passed, ",failed," failed\n")
return failed
