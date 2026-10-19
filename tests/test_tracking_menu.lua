local ns, Mini = Wayfinder, Wayfinder.MinimapServices
local passed, failed = 0, 0
local old = {menu=Menu,response=MenuResponse,minimap=Minimap,enabled=ns:GetSetting("showMinimapServices"),
	count=C_Minimap.GetNumTrackingTypes,filter=C_Minimap.GetTrackingFilter,info=C_Minimap.GetTrackingInfo,
	set=C_Minimap.SetTracking,clear=C_Minimap.ClearAllTracking,menuInstalled=Mini.menuInstalled}
local oldCats={}
for _,id in ipairs({"bank","repair"}) do oldCats[id]=ns:IsCategoryEnabled(id); ns:SetCategoryEnabled(id,true) end
Minimap=CreateFrame("Frame",nil,UIParent); Minimap:SetSize(200,200)
local active={true,true,true,true}
local filters={Enum.MinimapTrackingFilter.Banker,Enum.MinimapTrackingFilter.Repair,90000001,90000002}
C_Minimap.GetNumTrackingTypes=function() return 4 end
C_Minimap.GetTrackingFilter=function(i) return {filterID=filters[i]} end
C_Minimap.GetTrackingInfo=function(i) return {active=active[i],name=({"Bankers","Repair","Quests","Find Minerals"})[i]} end
C_Minimap.SetTracking=function(i,value) active[i]=value end
C_Minimap.ClearAllTracking=function() for i=1,4 do active[i]=false end end
local modify
Menu={ModifyMenu=function(tag,callback) assert(tag=="MENU_MINIMAP_TRACKING"); modify=callback end}
MenuResponse={Refresh="refresh"}
Mini.menuInstalled=nil
Mini:InstallTrackingMenu()
ns:SetSetting("showMinimapServices",true); Mini:Update()
local function Description(index)
	local desc={data=index and {index=index},children={}}
	function desc:GetData() return self.data end
	function desc:EnumerateElementDescriptions() return ipairs(self.children) end
	function desc:SetIsSelected(fn) self.selected=fn end
	function desc:SetResponder(fn) self.responder=fn end
	if index then
		desc.selected=function(data) return C_Minimap.GetTrackingInfo(data.index).active end
		desc.responder=function(data) C_Minimap.SetTracking(data.index,not desc.selected(data)) end
	end
	return desc
end
local root,repair,minerals=Description(),Description(2),Description(4)
root.children={repair,minerals}
modify(nil,root)
local function test(name,fn)
	local ok,err=pcall(fn)
	if ok then passed=passed+1; io.write("  ok    ",name,"\n")
	else failed=failed+1; io.write("  FAIL  ",name,"\n        ",tostring(err),"\n") end
end
test("Blizzard checkboxes control real native blips and Wayfinder selections together",function()
	assert(repair.selected(repair.data)==true,"checked service reflects visible Wayfinder icons")
	assert(active[2]==true,"native tracking stays enabled even for NPCs absent from Wayfinder")
	assert(repair.responder(repair.data)==MenuResponse.Refresh)
	mock.Advance(.03,.01)
	assert(not ns:IsCategoryEnabled("repair") and not repair.selected(repair.data),"native uncheck changes Wayfinder too")
	assert(not active[2],"unchecking disables the actual native blip")
	repair.responder(repair.data)
	mock.Advance(.03,.01)
	assert(ns:IsCategoryEnabled("repair") and repair.selected(repair.data),"native check persists")
	assert(active[2]==true,"checking restores native icons rather than an empty replacement")
end)
test("Wayfinder settings and external native tracking changes update the same selection",function()
	ns:SetCategoryEnabled("repair",false)
	assert(not repair.selected(repair.data),"Wayfinder menu change updates Blizzard checkbox")
	local setting=ns.settingObjects["cats.repair"]
	assert(setting.tbl[setting.key]==false,"settings panel also matches")
	C_Minimap.SetTracking(2,true)
	assert(ns:IsCategoryEnabled("repair") and repair.selected(repair.data))
	C_Minimap.SetTracking(2,false)
	assert(not ns:IsCategoryEnabled("repair") and not repair.selected(repair.data))
end)
test("gathering and quest filters keep native behavior and clear-all updates service selections",function()
	assert(minerals.selected(minerals.data)==true)
	minerals.responder(minerals.data)
	assert(active[4]==false,"resource tracking uses its original handler")
	assert(active[3]==true,"service changes never disable quest tracking")
	ns:SetCategoryEnabled("repair",true)
	C_Minimap.ClearAllTracking()
	assert(not ns:IsCategoryEnabled("repair") and not ns:IsCategoryEnabled("bank"),"clear-all includes Wayfinder services")
	assert(not repair.selected(repair.data))
end)
test("supported services use native rendering without a competing Wayfinder marker",function()
	ns:SetCategoryEnabled("repair",true); ns:SetCategoryEnabled("bank",true)
	mock.Advance(.03,.01)
	local c,x,y=ns.GetPlayerWorld()
	local rec=ns.Database:RecordNPC({npcID=898001,name="Native repair merchant",cats={repair=true,vendor=true},cont=c,wx=x+10,wy=y,mapID=mock.playerMap,accuracy=1})
	Mini:Update()
	assert(active[1] and active[2],"native blips remain available for every supported NPC, including unrecorded ones")
	for _,pin in ipairs(Mini.pins) do assert(not pin:IsShown() or pin.rec~=rec,"no duplicate Lua-projected repair marker") end
	ns:SetCategoryEnabled("repair",false);mock.Advance(.03,.01)
	assert(not active[2],"native repair checkbox controls its actual blips")
	local fallback
	for _,pin in ipairs(Mini.pins) do if pin:IsShown() and pin.rec==rec then fallback=pin end end
	assert(fallback and fallback.catID=="vendor","an independently selected generic vendor category still works")
end)
test("synchronous tracking events cannot undo clicks before the native post-hook runs",function()
	C_Minimap.SetTracking=function(i,value) active[i]=value;mock.Fire("MINIMAP_UPDATE_TRACKING") end
	Mini:InstallTrackingMenu()
	for _,value in ipairs({true,false,true,false,true}) do
		C_Minimap.SetTracking(2,value);mock.Advance(.03,.01)
		assert(active[2]==value and ns:IsCategoryEnabled("repair")==value,"the user's native choice persists past the next frame")
	end
	ns:SetCategoryEnabled("repair",false);mock.Advance(.03,.01)
	assert(not active[2] and not repair.selected(repair.data),"Wayfinder settings also update the native checkbox")
end)
test("a native repair source also covers the same NPC recorded only as a vendor",function()
	ns:SetCategoryEnabled("repair",true);ns:SetCategoryEnabled("vendor",true)
	local c,x,y=ns.GetPlayerWorld()
	local id=898002
	local rec=ns.Database:RecordNPC({npcID=id,name="Vendor with native repair",cats={vendor=true},cont=c,wx=x-20,wy=y+10,mapID=mock.playerMap,accuracy=1})
	local frame=CreateFrame("Button",nil,Minimap)
	frame.data={Type="manual",id=id,Name=rec.n}
	frame.isManualIcon,frame.miniMapIcon,frame.UiMapID=true,true,mock.playerMap
	local mx,my=ns.WorldToMapRect(ns.GetMapRect(mock.playerMap),rec.x,rec.y)
	frame.x,frame.y=mx*100,my*100
	function frame:ShouldBeHidden() return self.filtered==true end
	function frame:FakeHide() self.hidden=true;self:Hide() end
	ns.MinimapTurnIns:TagFrame(frame,"Repair",id)
	Mini:Update()
	assert(active[2])
	for _,pin in ipairs(Mini.pins) do assert(not pin:IsShown() or pin.rec.id~=id,"a vendor fallback cannot duplicate a known native repair NPC") end
	frame.filtered=true;frame:Hide()
end)
test("Classic tracking menus still synchronize when GetTrackingFilter is unavailable",function()
	local filter=C_Minimap.GetTrackingFilter
	C_Minimap.GetTrackingFilter=nil
	ns:SetCategoryEnabled("repair",true);mock.Advance(.03,.01)
	assert(active[2] and Mini.nativeCategories.repair,"recognized native menu label supplies the Classic fallback")
	C_Minimap.SetTracking(2,false);mock.Advance(.03,.01)
	assert(not active[2] and not ns:IsCategoryEnabled("repair"))
	C_Minimap.GetTrackingFilter=filter
end)
test("disabling Wayfinder restores the latest checkbox choices to native tracking",function()
	ns:SetCategoryEnabled("bank",true); ns:SetCategoryEnabled("repair",false)
	ns:SetSetting("showMinimapServices",false); Mini:Update()
	assert(active[1] and not active[2],"restore latest choices rather than startup state")
	assert(not repair.selected(repair.data),"an open native menu also falls back correctly")
end)
ns:SetSetting("showMinimapServices",false)
for id,value in pairs(oldCats) do ns:SetCategoryEnabled(id,value) end
Menu,MenuResponse,Minimap=old.menu,old.response,old.minimap
Mini.menuInstalled=old.menuInstalled
C_Minimap.GetNumTrackingTypes,C_Minimap.GetTrackingFilter,C_Minimap.GetTrackingInfo=old.count,old.filter,old.info
C_Minimap.SetTracking,C_Minimap.ClearAllTracking=old.set,old.clear
ns:SetSetting("showMinimapServices",old.enabled); Mini:Update()
io.write("\n",passed," tracking-menu checks passed, ",failed," failed\n")
return failed
