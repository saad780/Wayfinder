local ns, map, sc = Wayfinder, WorldMapFrame, WorldMapFrame.ScrollContainer
local C, S = ns.ContinuousMap, ns.ContinuousEngine.MapStitch
local controller = ns.ContinuousEngine:GetModule("worldmap")
local passed, failed = 0, 0
local function check(v, m) assert(v, m) end
local function near(a, b, epsilon) assert(math.abs(a-b) < (epsilon or 0.00001), tostring(a) .. " != " .. tostring(b)) end
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then passed = passed + 1; io.write("  ok    ", name, "\n")
	else failed = failed + 1; io.write("  FAIL  ", name, "\n        ", tostring(err), "\n") end
end
local function Show(id, x, y, zoom)
	map:Show()
	local u, v = C.API.WorldFromMap(id, x, y)
	controller.ShowNow(u, v, zoom)
	mock.Advance(0.2)
	return u, v
end
local function Descendants(frame, fn)
	for _, child in ipairs(frame.children) do fn(child); Descendants(child, fn) end
end
local function ArtFrame(id)
	local file = C_Map.GetMapArtLayerTextures(id, 1)[1]
	for _, frame in ipairs(S.root.children) do
		for _, texture in ipairs(frame.textures or {}) do
			if texture.texture == file then return frame end
		end
	end
end

test("continuous map starts without OpenMap and preserves the other addon's saved preference", function()
	check(C.started and C:IsActive(), "controller must start")
	check(S.IsBuilt(), "own art renderer is built")
	check(ns.OpenMapCompat:GetAPI() == C.API, "internal coordinate API selected")
	if mock.openMapModule then
		check(not mock.openMapModule.enabled, "one runtime controller owns the wheel")
		check(mock.openMapModule.db.enabled, "OpenMap saved preference unchanged")
	end
end)
test("whole-world view, cities and neighbouring zones share one coordinate plane", function()
	map:SetMapID(947)
	Show(947, 0.5, 0.5, 1)
	check(not ns.DetailView:IsFollowingMap(), "world view should not allocate deep terrain")
	for _, id in ipairs({ 1429, 1454, 1458 }) do
		local u, v = C.API.WorldFromMap(id, 0.5, 0.5)
		check(C.API.MapAt(u, v) == id, "city/zone chosen at location " .. id)
		local x, y = C.API.MapFromWorld(id, u, v)
		near(x, 0.5); near(y, 0.5)
	end
end)
test("deep zoom reaches Wayfinder's 140-yard terrain window and reverses continuously", function()
	local u, v = C.API.WorldFromMap(1429, 0.8, 0.8)
	Show(1429, 0.8, 0.8, C:GetMaxZoom(u, v))
	check(ns.DetailView:IsFollowingMap() and not ns.DetailView:IsActive(), "terrain follows native input")
	check(not WayfinderDetailView.mouse, "terrain does not intercept native mouse input")
	local plane = WayfinderDetailView.children[1]
	near(sc:GetWidth() / plane:GetScale(), 140)
	check(WayfinderDetailView.background.shown == false, "no opaque terrain backdrop")
	check(sc.mouseWheelZoomMode == MAP_CANVAS_MOUSE_WHEEL_ZOOM_BEHAVIOR_NONE, "native double zoom disabled")
	controller.ShowNow(u, v, 3)
	mock.Advance(0.2)
	check(not ns.DetailView:IsFollowingMap(), "scrolling back leaves terrain")
end)
test("wheel zoom stays under the cursor while crossing native host-map boundaries", function()
	map:SetMapID(947)
	Show(1429, 0.8, 0.8, 40)
	mock.cursorX, mock.cursorY = sc:GetWidth() * 0.7, sc:GetHeight() * 0.6
	local u, v = controller.CursorWorld()
	sc.scripts.OnMouseWheel(sc, 1)
	mock.Advance(0.55)
	local nu, nv = controller.CursorWorld()
	near(u, nu); near(v, nv)
	local cu, cv, zoom = C.API.GetView()
	mock.Advance(0.8)
	local au, av, az = C.API.GetView()
	check(map:GetMapID() == 1429, "settled host follows zone")
	near(cu, au); near(cv, av); near(zoom, az)
	mock.cursorX, mock.cursorY = nil, nil
end)
test("capital artwork remains above terrain, including underground city maps", function()
	for _, id in ipairs({ 1454, 1458 }) do
		Show(id, 0.5, 0.5, 500)
		check(ns.DetailView:IsFollowingMap(), "every capital retains its marker overlay")
		check(ns.DetailView:IsTerrainVisible() == (id ~= 1458), "Undercity defaults to its interior, outdoor cities keep terrain")
		local found = ArtFrame(id)
		check(found and found:IsShown(), "capital artwork visible " .. id)
		check(found:GetFrameLevel() > WayfinderDetailView.children[1]:GetFrameLevel(), "city is above terrain")
		check(found:GetFrameLevel() < S.artTop, "native pins remain above city art")
	end
end)
test("Undercity defaults underground and its swap button changes floors without moving the view", function()
	Show(1458, 0.65, 0.5, 500)
	local id, surface = S.GetUndergroundView()
	check(id == 1458 and surface == false, "interior is the default")
	check(ns.DetailView:IsFollowingMap() and not ns.DetailView:IsTerrainVisible(), "markers remain while surface terrain cannot cover the default interior")
	local city = ArtFrame(1458)
	for _, texture in ipairs(city.textures or {}) do
		check(texture.kind ~= "MaskTexture", "interior does not depend on an external mask loading")
	end
	local button = C.layerButton
	check(button and button:IsShown() and button.label:GetText() == "Undercity", "swap control names the current layer")
	button.scripts.OnEnter(button)
	check(GameTooltip.lines[1] == "Show overworld", "tooltip explains the next layer")
	local u, v, zoom = C.API.GetView()
	button.scripts.OnClick(button)
	local _, overworld = S.GetUndergroundView()
	check(overworld and not city:IsShown(), "surface switch hides the city plan")
	check(ns.DetailView:IsFollowingMap(), "surface shows its minimap terrain")
	check(map:GetMapID() == 1420 and C.API.MapAt(u, v) == 1420, "native markers and navigation use Tirisfal")
	check(button.label:GetText() == "Overworld", "button identifies the surface view")
	local nu, nv, nz = C.API.GetView()
	near(u, nu); near(v, nv); near(zoom, nz)
	button.scripts.OnClick(button)
	check(map:GetMapID() == 1458 and city:IsShown(), "swap back restores the city and its native pins")
	check(ns.DetailView:IsFollowingMap() and not ns.DetailView:IsTerrainVisible(), "city interior hides surface terrain while retaining markers")
	check(select(2, S.GetUndergroundView()) == false, "returned underground")
end)
test("Undercity returns to its default after leaving or closing the map", function()
	Show(1458, 0.65, 0.5, 500)
	C.layerButton.scripts.OnClick(C.layerButton)
	Show(947, 0.5, 0.5, 1)
	check(not C.layerButton:IsShown() and not S.GetUndergroundView(), "swap button only appears near Undercity")
	Show(1458, 0.65, 0.5, 500)
	check(select(2, S.GetUndergroundView()) == false, "revisiting defaults underground")
	C.layerButton.scripts.OnClick(C.layerButton)
	map.scripts.OnHide(map)
	check(not C.layerButton:IsShown() and not S.GetUndergroundView(), "closing clears the temporary surface choice")
	controller.RefreshView()
	mock.Advance(0.2)
	check(select(2, S.GetUndergroundView()) == false, "reopening defaults underground")
end)
test("minimap terrain fades in later, after the ordinary zone view", function()
	local u, v = C.API.WorldFromMap(1429, 0.8, 0.8)
	local cap = C:GetMaxZoom(u, v)
	Show(1429, 0.8, 0.8, cap * 140 / 5500)
	check(not ns.DetailView:IsFollowingMap(), "the earlier 6000-yard transition stays map art")
	Show(1429, 0.8, 0.8, cap * 140 / 2800)
	check(not ns.DetailView:IsFollowingMap(), "normal zone view keeps its painted map")
	Show(1429, 0.8, 0.8, cap * 140 / 2350)
	check(ns.DetailView:IsFollowingMap() and WayfinderDetailView:GetAlpha() < 0.2, "terrain begins with a gentle fade at close zoom")
	Show(1429, 0.8, 0.8, cap * 140 / 1400)
	check(ns.DetailView:IsFollowingMap(), "terrain stays available up close")
	near(WayfinderDetailView:GetAlpha(), 1)
end)
test("completed quests keep golden markers and precise navigation at continuous terrain zoom", function()
	mock.questLog[876543], mock.readyQuests[876543] = true, true
	mock.questPOIs[1429] = { { questID = 876543, x = 0.801, y = 0.802 } }
	mock.questTitles[876543] = "Continuous turn-in"
	ns:Fire("QUEST_TURN_INS_CHANGED")
	Show(1429, 0.8, 0.8, 500)
	local found
	Descendants(WayfinderDetailView, function(pin)
		if pin.quest and pin.quest.questID == 876543 and pin:IsShown() then found = pin end
	end)
	check(found and found.quest.turnIn, "golden turn-in retained")
	check(found:GetFrameLevel() > S.artTop, "quest is above terrain/city/service layers")
	-- A map rectangle may stretch its axes differently. Both terrain and its
	-- markers must follow the art's geometry, including points off the centre.
	local u, v = C.API.GetView()
	local qu, qv = C.API.WorldFromMap(1429, 0.801, 0.802)
	local hu, hv = controller.ViewHalfExtents(500)
	near(found.points.CENTER[3], sc:GetWidth()/2 + (qu-u)/hu * sc:GetWidth()/2)
	near(found.points.CENTER[4], -(sc:GetHeight()/2 + (qv-v)/hv * sc:GetHeight()/2))
	local cr = ns.GetMapRect(1415)
	local l, r, t, b = S.Rect(1415)
	local expectedRatio = (b-t)*select(2, S.Size())/cr.height / ((r-l)*S.Size()/cr.width)
	for _, textures in pairs(ns.DetailView.activeTiles) do
		if textures[1] then near(textures[1]:GetHeight()/textures[1]:GetWidth(), expectedRatio); break end
	end
	mock.mouseOver = found
	found.scripts.OnMouseUp(found, "MiddleButton")
	local c, x, y = ns.MapToWorld(1429, 0.801, 0.802)
	local wp = ns.Navigation:GetWaypoint()
	check(wp.c == c, "correct continent")
	near(wp.x, x); near(wp.y, y)
	mock.mouseOver = nil
end)
test("middle-clicks cross continent boundaries and an idle map does not recreate service pins", function()
	local u, v = C.API.WorldFromMap(1414, 0.8, 0.8)
	local x, y = C.API.MapFromWorld(map:GetMapID(), u, v)
	mock.mapCursorX, mock.mapCursorY = x, y
	sc.scripts.OnMouseUp(sc, "MiddleButton")
	local wp = ns.Navigation:GetWaypoint()
	local c, wx, wy = ns.MapToWorld(1414, 0.8, 0.8)
	check(wp.c == c, "cursor can select a different continent from the host")
	near(wp.x, wx); near(wp.y, wy)
	mock.mapCursorX, mock.mapCursorY = nil, nil
	mock.Advance(1)
	local count = 0
	C.API.RegisterCallback({}, "OpenMap_ViewChanged", function() count = count + 1 end)
	mock.Advance(0.8)
	check(count == 0, "idle terrain/quest updates do not recreate native service pins")
end)
test("services, waypoints and addon icons survive the full transition into minimap terrain", function()
	local c,wx,wy=ns.MapToWorld(1429,0.8,0.8)
	local rec=ns.Database:RecordNPC({npcID=887760,name="Persistent repairer",cats={vendor=true,repair=true},cont=c,wx=wx,wy=wy,mapID=1429,accuracy=1})
	ns.Navigation:SetWaypoint(c,wx+2,wy+2,"Persistent waypoint",1429)
	local icon=CreateFrame("Frame",nil,sc.Child)
	icon:SetSize(16,16)
	icon.data={Name="Persistent addon objective"}
	icon.texture=icon:CreateTexture(nil,"ARTWORK")
	icon.texture:SetTexture("PersistentAddonArtwork")
	icon.texture:SetSize(16,16)
	local iu,iv=C.API.WorldFromMap(1429,0.8001,0.8001)
	function icon:GetPosition() return C.API.MapFromWorld(map:GetMapID(),iu,iv) end
	function icon:GetMap() return map end
	local u,v=C.API.WorldFromMap(1429,0.8,0.8)
	local cap=C:GetMaxZoom(u,v)
	for _,span in ipairs({2350,1400,140}) do
		Show(1429,0.8,0.8,cap*140/span)
		mock.Advance(0.6)
		local found={}
		Descendants(WayfinderDetailView,function(pin)
			if pin:IsVisible() then
				if pin.rec==rec then found.service=pin end
				if pin.rec and pin.rec.waypoint then found.waypoint=pin end
				if pin.external and pin.external.frame==icon then found.addon=pin end
			end
		end)
		check(found.service and found.waypoint and found.addon,"all marker types survive at "..span.." yards")
		check(found.service:GetFrameLevel()>S.artTop,"service marker stays above terrain")
	end
	icon:SetAlpha(0)
	ns.AddonPins:Refresh()
	mock.Advance(0.2)
	local retained
	Descendants(WayfinderDetailView,function(pin)
		if pin:IsVisible() and pin.external and pin.external.frame==icon then retained=pin end
	end)
	check(retained,"native zoom fading does not hide the persistent copy")
	icon:Hide()
	ns.AddonPins:Refresh()
	mock.Advance(0.2)
	local stale
	Descendants(WayfinderDetailView,function(pin)
		if pin:IsVisible() and pin.external and pin.external.frame==icon then stale=true end
	end)
	check(not stale,"explicit owner visibility filters still remove the copied icon")
end)
local function ForeignPin(data, x, y, service)
	local frame = CreateFrame("Frame", nil, sc.Child)
	local source = CreateFrame("Button", nil, frame)
	frame.icon = source
	source:SetSize(18, 18)
	source.data = data
	if service then source.wayfinderServiceTag = { data = data, cat = service } end
	local texture = source:CreateTexture(nil, "ARTWORK")
	texture:SetAllPoints(); texture:SetTexture("ForeignMarkerArt")
	local u, v = C.API.WorldFromMap(1429, x, y)
	function frame:GetPosition() return C.API.MapFromWorld(map:GetMapID(), u, v) end
	function frame:GetMap() return map end
	return frame, source
end
local function DetailPins(predicate)
	local result = {}
	Descendants(WayfinderDetailView, function(pin)
		if pin:IsVisible() and predicate(pin) then result[#result+1] = pin end
	end)
	return result
end
test("Undercity keeps the same marker overlay when one zoom step enters the city layer",function()
	local c,wx,wy=ns.MapToWorld(1458,.01,.5)
	local id,questID=898301,898302
	local rec=ns.Database:RecordNPC({npcID=id,name="Undercity recorded service",cats={repair=true},cont=c,wx=wx+30,wy=wy,mapID=1458,accuracy=1})
	local frame=CreateFrame("Frame",nil,sc.Child)
	local source=CreateFrame("Button",nil,frame)
	frame.icon=source;source:SetSize(18,18)
	source.data={Type="manual",id=898303,Name="Undercity temporary service"}
	source.isManualIcon,source.miniMapIcon,source.UiMapID=true,false,1458
	source.x,source.y=1,50
	function source:ShouldBeHidden() return self.filtered==true end
	local texture=source:CreateTexture(nil,"ARTWORK");texture:SetAllPoints();texture:SetTexture("CityServiceArt")
	local u,v=C.API.WorldFromMap(1458,.01,.5)
	function frame:GetPosition() return C.API.MapFromWorld(map:GetMapID(),u,v) end
	function frame:GetMap() return map end
	ns.MinimapTurnIns:TagFrame(source,"Vendor",source.data.id)
	local object=CreateFrame("Frame",nil,sc.Child)
	object:SetSize(18,18)
	object.data={Name="Undercity addon object"}
	local objectU,objectV=C.API.WorldFromMap(1458,.025,.49)
	function object:GetPosition() return C.API.MapFromWorld(map:GetMapID(),objectU,objectV) end
	function object:GetMap() return map end
	local objectTexture=object:CreateTexture(nil,"ARTWORK")
	objectTexture:SetAllPoints();objectTexture:SetTexture("CityObjectArt")
	object:SetScript("OnEnter",function() GameTooltip:SetText("Undercity object details");GameTooltip:Show() end)
	mock.questLog[questID],mock.readyQuests[questID]=true,true
	mock.questPOIs[1458]={{questID=questID,x=.02,y=.5}}
	local function CheckPins()
		check(#DetailPins(function(pin) return pin.rec==rec end)==1,"recorded service survives the city handoff")
		check(#DetailPins(function(pin) return pin.rec and pin.rec.id==898303 or pin.external and pin.external.npcID==898303 end)==1,"temporary service retains exactly one marker")
		check(#DetailPins(function(pin) return pin.quest and pin.quest.questID==questID end)==1,"golden turn-in survives the city handoff")
		check(#DetailPins(function(pin) return pin.external and pin.external.frame==object end)==1,"addon object retains its artwork through the city handoff")
	end
	Show(1458,-.005,.5,500)
	check(ns.DetailView:IsFollowingMap(),"terrain starts with a persistent overlay")
	CheckPins()
	-- Zoom toward a nearby point in the visible city. A single notch moves the
	-- view centre across the underground footprint while all three pins remain
	-- well inside the viewport, matching the screenshot's layer handoff.
	local cursorU,cursorV=C.API.WorldFromMap(1458,.045,.5)
	local centerU,centerV,zoom=C.API.GetView()
	local hu,hv=controller.ViewHalfExtents(zoom)
	mock.cursorX=(sc:GetLeft()+sc:GetWidth()/2+(cursorU-centerU)/hu*sc:GetWidth()/2)*sc:GetEffectiveScale()
	mock.cursorY=(sc:GetTop()-sc:GetHeight()/2-(cursorV-centerV)/hv*sc:GetHeight()/2)*sc:GetEffectiveScale()
	sc.scripts.OnMouseWheel(sc,1);mock.Advance(.6)
	mock.cursorX,mock.cursorY=nil,nil
	CheckPins()
	check(ns.DetailView:IsFollowingMap() and not ns.DetailView:IsTerrainVisible(),"underground retains pins without drawing surface tiles")
	check(next(ns.DetailView.activeTiles)==nil,"underground does not allocate hidden terrain")
	Show(1458,.01,.5,500)
	CheckPins()
	for _,pin in ipairs(DetailPins(function(pin) return pin.rec==rec end)) do check(pin:GetFrameLevel()>S.artTop,"service stays above city artwork") end
	C.layerButton.scripts.OnClick(C.layerButton);mock.Advance(.1)
	check(ns.DetailView:IsTerrainVisible(),"switching to the surface restores actual terrain")
	check(#DetailPins(function(pin) return pin.rec==rec end)==1,"surface switch retains the recorded service")
	C.layerButton.scripts.OnClick(C.layerButton);mock.Advance(.1)
	CheckPins()
	local objectPin=DetailPins(function(pin) return pin.external and pin.external.frame==object end)[1]
	objectPin.scripts.OnEnter(objectPin)
	check(GameTooltip.lines[1]=="Undercity object details","underground object retains its source tooltip")
	objectPin.scripts.OnLeave(objectPin)
	source.filtered=true;frame:Hide()
	object:Hide()
	mock.questLog[questID],mock.readyQuests[questID],mock.questPOIs[1458]=nil,nil,nil
	ns:Fire("QUEST_TURN_INS_CHANGED")
end)
test("continuous copies exclusively own drawing and restore owner alpha after zooming out", function()
	local c, wx, wy = ns.MapToWorld(1429, 0.55, 0.55)
	local rec = ns.Database:RecordNPC({npcID=887781,name="Single service copy",cats={repair=true},cont=c,wx=wx,wy=wy,mapID=1429,accuracy=1})
	local frame, source = ForeignPin({Name="Exclusive addon marker"}, 0.552, 0.552)
	source:SetAlpha(0.7)
	local u, v = C.API.WorldFromMap(1429, 0.55, 0.55)
	local cap = C:GetMaxZoom(u,v)
	Show(1429, 0.55, 0.55, cap*140/2350)
	mock.Advance(0.7)
	near(source:GetAlpha(), 0)
	check(#DetailPins(function(pin) return pin.external and pin.external.frame==frame end)==1, "one persistent copy")
	for _, pin in ipairs(map.pins) do check(pin.rec~=rec, "native Wayfinder copy released during terrain fade") end
	source:SetAlpha(0.4)
	near(source:GetAlpha(), 0)
	ns.AddonPins:Refresh(); mock.Advance(0.2)
	local copy = DetailPins(function(pin) return pin.external and pin.external.frame==frame end)[1]
	check(copy, "alpha masking does not make the source unreadable")
	near(copy.externalTextures[1]:GetAlpha(), 0.4)
	source:Hide(); ns.AddonPins:Refresh(); mock.Advance(0.2)
	check(#DetailPins(function(pin) return pin.external and pin.external.frame==frame end)==0, "owner hide removes persistent copy")
	check(not source:IsShown(), "ownership release does not undo owner visibility")
	source:Show(); ns.AddonPins:Refresh(); mock.Advance(0.2)
	near(source:GetAlpha(), 0)
	Show(1429, 0.55, 0.55, cap*140/2800)
	near(source:GetAlpha(), 0.4)
	local restored
	for _, pin in ipairs(map.pins) do if pin.rec==rec then restored=true end end
	check(restored, "native Wayfinder marker returns on zoom out")
	frame:Hide()
end)
test("native, Questie and fallback turn-ins combine per NPC above service icons", function()
	local first, second = 887782, 887783
	mock.questLog[first], mock.readyQuests[first] = true, true
	mock.questLog[second], mock.readyQuests[second] = true, true
	local oldPOIs = mock.questPOIs[1429]
	mock.questPOIs[1429] = {{questID=first,x=0.55,y=0.55},{questID=second,x=0.55,y=0.55}}
	local c, wx, wy = ns.MapToWorld(1429,0.55,0.55)
	local rec = ns.Database:RecordNPC({npcID=887784,name="Quest merchant",cats={vendor=true},cont=c,wx=wx,wy=wy,mapID=1429,accuracy=1})
	local other = ns.Database:RecordNPC({npcID=887785,name="Nearby repairer",cats={repair=true},cont=c,wx=wx+1,wy=wy,mapID=1429,accuracy=1})
	local x,y=ns.WorldToMapRect(ns.GetMapRect(1429),other.x,other.y)
	local frames, sources = {}, {}
	for _,data in ipairs({{Type="complete",Id=first,Name="Quest merchant"},{Type="complete",Id=second,Name="Quest merchant"}}) do
		local frame, source = ForeignPin(data,0.55,0.55)
		frames[#frames+1],sources[#sources+1]=frame,source
	end
	local native, nativeSource=ForeignPin({questName="Native quest title"},0.55,0.55)
	native.questID=first
	frames[#frames+1],sources[#sources+1]=native,nativeSource
	for _,cat in ipairs({"repair","vendor"}) do
		local frame,source=ForeignPin({Type="manual",id=other.id,Name=other.n},x,y,cat)
		frames[#frames+1],sources[#sources+1]=frame,source
	end
	ns:Fire("QUEST_TURN_INS_CHANGED")
	Show(1429,0.55,0.55,500); mock.Advance(0.7)
	local quests=DetailPins(function(pin) return pin.external and (pin.external.questID==first or pin.external.questID==second) end)
	check(#quests==1,"one golden marker for one NPC with two quests and multiple source addons")
	check(#DetailPins(function(pin) return pin.rec==rec end)==0,"quest takes precedence over this NPC's merchant marker")
	local services=DetailPins(function(pin) return pin.rec==other end)
	check(#services==1,"different nearby NPC retains exactly one service marker")
	check(quests[1]:GetFrameLevel()>services[1]:GetFrameLevel(),"quest draws above nearby service art")
	check(#DetailPins(function(pin) return pin.external and pin.external.npcID==other.id end)==0,"foreign merchant and repair duplicates suppressed")
	for _,source in ipairs(sources) do near(source:GetAlpha(),0) end
	for _,frame in ipairs(frames) do frame:Hide() end
	mock.questPOIs[1429]=oldPOIs
	mock.questLog[first],mock.readyQuests[first],mock.questLog[second],mock.readyQuests[second]=nil,nil,nil,nil
	ns.AddonPins:Refresh(); ns:Fire("QUEST_TURN_INS_CHANGED")
end)
test("available quests take precedence over the same NPC's other services", function()
	local id=887786
	local c,wx,wy=ns.MapToWorld(1429,0.6,0.6)
	local rec=ns.Database:RecordNPC({npcID=887787,name="Quest innkeeper",cats={inn=true,vendor=true,quest=true},cont=c,wx=wx,wy=wy,mapID=1429,accuracy=1})
	ns.QuestAvailability:Observe(rec,{{questID=id}},true)
	check(ns.Categories:GetVisibleCategory(rec)=="quest","available quest beats inn and vendor priority")
	check(ns.Categories:GetVisibleCategory(rec,true)=="inn","service-only classification remains available")
	local frame,source=ForeignPin({Type="available",Id=id,Name=rec.n},0.6,0.6)
	Show(1429,0.6,0.6,500); mock.Advance(0.7)
	local pins=DetailPins(function(pin) return pin.rec==rec or pin.external and pin.external.questID==id end)
	check(#pins==1 and pins[1].external,"one available quest marker retains its owner's tooltip")
	check(pins[1]:GetFrameLevel()>pins[1]:GetParent():GetFrameLevel()+1,"pickup above other icons")
	near(source:GetAlpha(),0)
	frame:Hide(); ns.QuestAvailability:Observe(rec,{},true); ns.AddonPins:Refresh()
end)
test("different objective spawns for the same quest remain separate", function()
	local id=887788
	mock.questLog[id]=true
	local c,wx,wy=ns.MapToWorld(1429,0.6,0.6)
	local x,y=ns.WorldToMapRect(ns.GetMapRect(1429),wx+8,wy)
	local first=ForeignPin({Name="First objective"},0.6,0.6)
	local second=ForeignPin({Name="Second objective"},x,y)
	first.questID,second.questID=id,id
	Show(1429,0.6,0.6,500); mock.Advance(0.7)
	check(#DetailPins(function(pin) return pin.external and pin.external.questID==id end)==2,"nearby objectives are not duplicate quest givers")
	first:Hide(); second:Hide(); mock.questLog[id]=nil; ns.AddonPins:Refresh()
end)
test("recorded and foreign repair markers use identical sizes and Blizzard artwork",function()
	local c,wx,wy=ns.MapToWorld(1429,0.65,0.65)
	local rec=ns.Database:RecordNPC({npcID=888101,name="Uniform own repairer",cats={repair=true},cont=c,wx=wx,wy=wy,mapID=1429,accuracy=1})
	local a,sa=ForeignPin({Type="manual",id=888102,Name="Small foreign repairer"},0.652,0.65,"repair")
	local b,sb=ForeignPin({Type="manual",id=888103,Name="Large foreign repairer"},0.654,0.65,"repair")
	sa:SetSize(8,8); sb:SetSize(32,32)
	sa:SetScript("OnEnter",function() GameTooltip:SetText("Original repair tooltip"); GameTooltip:Show() end)
	Show(1429,0.65,0.65,500); mock.Advance(0.6)
	local pins=DetailPins(function(pin) return pin.rec==rec or pin.external and (pin.external.frame==a or pin.external.frame==b) end)
	check(#pins==3,"three distinct repair NPCs retained")
	local mirror
	for _,pin in ipairs(pins) do
		near(pin:GetWidth(),20*(ns:GetSetting("detailIconScale") or 1))
		near(pin:GetHeight(),pin:GetWidth())
		check(pin.icon.texture==ns.CategoryByID.repair.icon.texture,"one Blizzard repair artwork")
		if pin.external and pin.external.frame==a then mirror=pin end
	end
	mirror.scripts.OnEnter(mirror)
	check(GameTooltip.lines[1]=="Original repair tooltip","canonical art retains the owner's tooltip")
	a:Hide(); b:Hide(); ns.AddonPins:Refresh()
end)
test("idle maps reuse marker artwork and cull distant pins before zone lookups",function()
	local frames={}
	for i=1,600 do
		local x=i<=12 and 0.8+(i-6)*0.0001 or 0.2+i*0.0001
		frames[#frames+1]=ForeignPin({Name="Idle benchmark "..i},x,0.8)
	end
	local u,v=C.API.WorldFromMap(1429,0.8,0.8)
	Show(1429,0.8,0.8,C:GetMaxZoom(u,v)*140/1400); mock.Advance(0.8)
	local appearance,quests,culls,lookups=0,0,0,0
	local oldArt,oldQuest,oldCull,oldLookup=ns.AddonPins.ApplyAppearance,C_QuestLine.GetAvailableQuestLines,S.Recull,C_Map.GetMapInfoAtPosition
	ns.AddonPins.ApplyAppearance=function(...) appearance=appearance+1; return oldArt(...) end
	C_QuestLine.GetAvailableQuestLines=function(...) quests=quests+1; return oldQuest(...) end
	S.Recull=function(...) culls=culls+1; return oldCull(...) end
	C_Map.GetMapInfoAtPosition=function(...) lookups=lookups+1; return oldLookup(...) end
	mock.Advance(2)
	ns.AddonPins.ApplyAppearance,C_QuestLine.GetAvailableQuestLines,S.Recull,C_Map.GetMapInfoAtPosition=oldArt,oldQuest,oldCull,oldLookup
	check(appearance==0 and quests==0 and culls==0,"no repeated icon copies, quest queries or art culls on a still map")
	check(lookups<600,"588 distant icons skipped before expensive map lookups")
	check(#DetailPins(function(pin) return pin.external and pin.external.n:find("Idle benchmark",1,true) end)==12,"all visible icons retained")
	for _,frame in ipairs(frames) do frame:Hide() end
	ns.AddonPins:Refresh(); mock.Advance(0.1)
end)
test("new native pins reach terrain detail on the next update instead of waiting for polling",function()
	local u,v=C.API.WorldFromMap(1429,0.8,0.8)
	Show(1429,0.8,0.8,500); mock.Advance(0.6)
	WayfinderPerfForeignPinMixin=CreateFromMixins(MapCanvasPinMixin)
	function WayfinderPerfForeignPinMixin:OnLoad() end
	function WayfinderPerfForeignPinMixin:OnAcquired(x,y)
		self:SetPosition(x,y); self:SetSize(18,18)
		self.Icon:SetAllPoints(); self.Icon:SetTexture("Newly acquired icon")
	end
	local x,y=C.API.MapFromWorld(map:GetMapID(),u,v)
	local source=map:AcquirePin("WayfinderPerfForeignPinTemplate",x,y)
	mock.Advance(0.06,0.01)
	check(#DetailPins(function(pin) return pin.external and pin.external.frame==source end)==1,"new native pin appears within 60ms in the mock")
	source:Hide(); map:RemoveAllPinsByTemplate("WayfinderPerfForeignPinTemplate")
	mock.Advance(0.06,0.01)
	check(#DetailPins(function(pin) return pin.external and pin.external.frame==source end)==0,"released pin also disappears promptly")
end)
test("Questie draws visible quest and service requests first without dropping distant or minimap requests",function()
	local loading=ns.MapLoading
	local oldLoader,oldModule,oldPrioritize=QuestieLoader,loading.questie,loading.Prioritize
	local q={_mapDrawQueue={},_minimapDrawQueue={},ICON_MAP_TYPE="world",ICON_MINIMAP_TYPE="mini"}
	function q:QueueDraw(typ,...) local queue=typ=="world" and self._mapDrawQueue or self._minimapDrawQueue; queue[#queue+1]={...} end
	QuestieLoader={ImportModule=function(_,name) if name=="QuestieMap" then return q end end}
	loading:Install(); mock.Advance(0.05)
	local passes=0
	loading.Prioritize=function(...) passes=passes+1; return oldPrioritize(...) end
	local original={}
	for i=1,100 do
		q:QueueDraw("world","Questie",{data={Type="manual"}},1429,0.2,0.2)
		original[#original+1]=q._mapDrawQueue[#q._mapDrawQueue]
		q:QueueDraw("mini","Questie",{data={Type="manual"}},1429,0.2,0.2)
	end
	q:QueueDraw("world","Questie",{data={Type="manual"}},1429,0.8,0.8)
	local service=q._mapDrawQueue[#q._mapDrawQueue]
	q:QueueDraw("world","Questie",{data={Type="complete"}},1429,0.8,0.8)
	local quest=q._mapDrawQueue[#q._mapDrawQueue]
	mock.Advance(0.06,0.01)
	check(passes==1,"hundreds of draw callbacks share one visibility pass")
	check(#q._mapDrawQueue==102 and q._mapDrawQueue[1]==quest and q._mapDrawQueue[2]==service,"visible quest and service do not wait behind distant requests")
	for i,request in ipairs(original) do check(q._mapDrawQueue[i+2]==request,"distant requests retain stable order and identity") end
	check(#q._minimapDrawQueue==100,"minimap queue is untouched")
	loading.Prioritize,loading.questie,QuestieLoader=oldPrioritize,oldModule,oldLoader
end)
test("large spatial queries visit occupied buckets instead of an enormous empty grid",function()
	local expected,found={},{}
	for _,rec in pairs(ns.db.pois) do if rec.c==0 then expected[rec]=true end end
	debug.sethook(function() error("spatial query instruction budget exceeded") end,"",1000000)
	local ok,err=pcall(function()
		ns.Database:Query(0,-100000000,100000000,-100000000,100000000,function(rec) found[rec]=true end)
		ns.Seeds:Query(0,-100000000,100000000,-100000000,100000000,function() end)
	end)
	debug.sethook()
	check(ok,err)
	for rec in pairs(expected) do check(found[rec],"wide query retains every recorded location") end
	for rec in pairs(found) do check(expected[rec],"wide query keeps continent filtering") end
end)
test("world map and minimap select the same three service locations from overlapping addon sources",function()
	local oldMini,oldMap,oldX,oldY=Minimap,mock.playerMap,mock.playerX,mock.playerY
	Minimap=CreateFrame("Frame",nil,UIParent); Minimap:SetSize(200,200)
	mock.playerMap,mock.playerX,mock.playerY=1429,0.66,0.66
	local id=888110
	local c,wx,wy=ns.MapToWorld(1429,0.66,0.66)
	local own=ns.Database:RecordNPC({npcID=id,name="Shared service locations",cats={repair=true},cont=c,wx=wx,wy=wy,mapID=1429,accuracy=1})
	local worldFrames,miniFrames={},{}
	-- Two source points are close to each other but straddle the recorded
	-- anchor's merge radius. Pre-grouping them would lose the outer point.
	for _,offset in ipairs({60,26,22}) do
		local x,y=ns.WorldToMapRect(ns.GetMapRect(1429),wx+offset,wy)
		for _,typ in ipairs({"Vendor","Repair"}) do
			local cat=typ:lower()
			local data={Type="manual",id=id,Name=own.n}
			worldFrames[#worldFrames+1]=ForeignPin(data,x,y,cat)
			local frame=CreateFrame("Frame","WayfinderSharedService"..offset..typ,Minimap)
			frame.data,frame.isManualIcon,frame.miniMapIcon,frame.UiMapID=data,true,true,1429
			frame.x,frame.y=x*100,y*100
			function frame:ShouldBeHidden() return self.filtered==true end
			function frame:FakeHide() self.hidden=true; self:Hide() end
			function frame:FakeShow() self.hidden=false; self:Show() end
			local source={manualFrames={[typ]={[id]={frame:GetName()}}}}
			ns.MinimapTurnIns:ObserveManualFrames(source,typ,id)
			miniFrames[#miniFrames+1]=frame
		end
	end
	local u,v=C.API.WorldFromMap(1429,0.66,0.66)
	Show(1429,0.66,0.66,C:GetMaxZoom(u,v)*140/300); mock.Advance(0.6)
	ns.MinimapServices:Update()
	local world,mini={},{}
	for _,pin in ipairs(DetailPins(function(pin) return pin.rec==own or pin.external and pin.external.npcID==id end)) do
		local x,y=ns.PlaneToWorld(pin.px,pin.py)
		world[("%.6f:%.6f"):format(x,y)]=true
	end
	for _,pin in ipairs(ns.MinimapServices.pins) do
		if pin:IsShown() and pin.rec.id==id then mini[("%.6f:%.6f"):format(pin.rec.x,pin.rec.y)]=true end
	end
	for _,frame in ipairs(worldFrames) do frame:Hide() end
	for _,frame in ipairs(miniFrames) do frame.filtered=true; frame:Hide() end
	Minimap,mock.playerMap,mock.playerX,mock.playerY=oldMini,oldMap,oldX,oldY
	ns.MinimapServices:Update(); ns.AddonPins:Refresh()
	local wc,mc=0,0
	for key in pairs(world) do wc=wc+1; check(mini[key],"world-map service location must also be on minimap") end
	for key in pairs(mini) do mc=mc+1; check(world[key],"minimap uses the same canonical location as world map") end
	check(wc==3 and mc==3,"both views display all three locations")
end)
test("world-only service icons persist through terrain zoom and respect both category menus",function()
	local id=898201
	local data={Type="manual",id=id,Name="Persistent world-only merchant"}
	local frame,source=ForeignPin(data,.74,.74,"vendor")
	source.isManualIcon,source.miniMapIcon,source.UiMapID=true,false,1429
	source.x,source.y=74,74
	function source:ShouldBeHidden() return self.filtered==true end
	ns.MinimapTurnIns:TagFrame(source,"Vendor",id)
	local u,v=C.API.WorldFromMap(1429,.74,.74)
	local function Count()
		return #DetailPins(function(pin) return pin.rec and pin.rec.id==id or pin.external and pin.external.npcID==id end)
	end
	for _,span in ipairs({2200,1400,500,140}) do
		Show(1429,.74,.74,C:GetMaxZoom(u,v)*140/span)
		frame:Hide() -- HBD no longer draws the canvas wrapper at this zoom.
		ns.AddonPins:Refresh();mock.Advance(.03,.01)
		check(Count()==1,"one marker remains after its world wrapper disappears at "..span.." yards")
	end
	ns:SetCategoryEnabled("vendor",false);mock.Advance(.03,.01)
	check(Count()==0,"the same category setting applies after the terrain handoff")
	ns:SetCategoryEnabled("vendor",true);mock.Advance(.03,.01)
	check(Count()==1,"reenabling restores the indexed marker immediately")
	source.filtered=true;ns.MinimapTurnIns:SourcesChanged();mock.Advance(.03,.01)
	check(Count()==0,"explicit owner filtering removes the persistent fallback")
end)
test("dungeons retain native map behavior and exploration overlays reuse their textures", function()
	Show(1454, 0.5, 0.5, 500)
	local before = 0
	for _, f in ipairs(S.root.children) do before = before + #(f.textures or {}) end
	for i = 1, 10 do S.RefreshExplored() end
	local after = 0
	for _, f in ipairs(S.root.children) do after = after + #(f.textures or {}) end
	check(before == after, "exploration refresh does not leak texture objects")
	map:SetMapID(9999)
	check(not C:IsActive() and not ns.DetailView:IsFollowingMap(), "unsupported maps use native canvas")
	check(not S.root:IsShown(), "stitched map hidden in dungeon")
	map:SetMapID(1429)
	check(C:IsActive(), "returning outdoors restores continuous map")
end)
io.write("\n", passed, " continuous map checks passed, ", failed, " failed\n")
return failed
