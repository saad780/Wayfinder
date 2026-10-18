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
test("Blizzard checkboxes show Wayfinder service selections while duplicate blips stay disabled",function()
	assert(repair.selected(repair.data)==true,"checked service reflects visible Wayfinder icons")
	assert(active[2]==false,"native duplicate remains suppressed")
	assert(repair.responder(repair.data)==MenuResponse.Refresh)
	assert(not ns:IsCategoryEnabled("repair") and not repair.selected(repair.data),"native uncheck changes Wayfinder too")
	repair.responder(repair.data)
	assert(ns:IsCategoryEnabled("repair") and repair.selected(repair.data),"native check persists")
	assert(active[2]==false,"checking does not reintroduce duplicate native icons")
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
