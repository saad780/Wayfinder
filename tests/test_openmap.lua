-- OpenMap 0.5's public API and clipped pin hierarchy, with synthetic geometry.
local ns, Nav = Wayfinder, Wayfinder.Navigation
local failed, passed = 0, 0
local function check(value, message) assert(value, message) end
local function near(a, b) assert(math.abs(a - b) < 0.00001, tostring(a) .. " != " .. tostring(b)) end
local function fixture()
	local sc = WorldMapFrame.ScrollContainer
	local old = { api = OpenMapAPI, up = sc:GetScript("OnMouseUp"), rect = sc.viewRect,
		cursor = rawget(sc, "GetCursorPosition"), normalized = rawget(sc, "GetNormalizedCursorPosition"),
		map = WorldMapFrame:GetMapID(), continent = ns:GetSetting("showOnContinent"),
		shown = ns:GetSetting("showOnWorldMap") }
	local state = { active = true, zoom = 6, callbacks = {}, originalClicks = 0 }
	local rects = { [1415] = { 0.55, 0.95, 0.1, 0.9 }, [1414] = { 0.05, 0.45, 0.1, 0.9 } }
	local function Rect(id)
		if id == 947 then return 0, 1, 0, 1 end
		if rects[id] then return unpack(rects[id]) end
		local r = ns.GetMapRect(id)
		if not r then return end
		local parent = ns.GetMapRect(r.cont == 0 and 1415 or 1414)
		local world = rects[r.cont == 0 and 1415 or 1414]
		local x, y = ns.WorldToMapRect(parent, r.top, r.left)
		local w, h = world[2] - world[1], world[4] - world[3]
		return world[1] + x * w, world[1] + (x + r.width / parent.width) * w,
			world[3] + y * h, world[3] + (y + r.height / parent.height) * h
	end
	local api = { major = 1, version = 2 }
	function api.IsStitched() return state.active end
	function api.WorldFromMap(id, x, y)
		local l, r, t, b = Rect(id)
		if l then return l + x * (r - l), t + y * (b - t) end
	end
	function api.MapFromWorld(id, u, v)
		local l, r, t, b = Rect(id)
		if l then return (u - l) / (r - l), (v - t) / (b - t) end
	end
	function api.MapAt(u, v)
		for _, id in ipairs({ 1429, 1415, 1414 }) do
			local l, r, t, b = Rect(id)
			if u >= l and u <= r and v >= t and v <= b then return id end
		end
		return 947
	end
	function api.GetView() return state.u, state.v, state.zoom end
	function api.ShowWorld(u, v) state.shownAt = { u, v }; return true end
	function api.ArtTopLevel() return 4200 end
	function api.CanvasFromWorldPos(c, wx, wy)
		local id = c == 0 and 1415 or 1414
		local x, y = ns.WorldToMapRect(ns.GetMapRect(id), wx, wy)
		return api.MapFromWorld(WorldMapFrame:GetMapID(), api.WorldFromMap(id, x, y))
	end
	function api.RegisterCallback(_, event, fn) state.callbacks[event] = fn end
	function state:View(l, r, t, b, host)
		WorldMapFrame:SetMapID(host or 947)
		self.u, self.v = (l + r) / 2, (t + b) / 2
		local x0, y0 = api.MapFromWorld(WorldMapFrame:GetMapID(), l, t)
		local x1, y1 = api.MapFromWorld(WorldMapFrame:GetMapID(), r, b)
		sc.viewRect = { left = x0, right = x1, top = y0, bottom = y1 }
	end
	OpenMapAPI = api
	function sc:GetCursorPosition()
		return (self.Child:GetLeft() + (mock.mapCursorX or 0.5) * self.Child:GetWidth()) * self:GetCanvasScale(),
			(self.Child:GetTop() - (mock.mapCursorY or 0.5) * self.Child:GetHeight()) * self:GetCanvasScale()
	end
	function sc:GetNormalizedCursorPosition()
		return math.max(0, math.min(1, mock.mapCursorX or 0.5)), math.max(0, math.min(1, mock.mapCursorY or 0.5))
	end
	WorldMapFrame:Show()
	ns.db.settings.showOnWorldMap, ns.db.settings.showOnContinent = true, true
	sc:SetScript("OnMouseUp", function() state.originalClicks = state.originalClicks + 1 end)
	ns.OpenMapCompat.installed = nil
	ns.OpenMapCompat:Install()
	state:View(0, 1, 0, 1)
	function state:Close()
		ns.DetailView:Exit(true)
		Nav:ClearWaypoint()
		OpenMapAPI = old.api
		sc:SetScript("OnMouseUp", old.up)
		sc.GetCursorPosition, sc.GetNormalizedCursorPosition = old.cursor, old.normalized
		sc.viewRect = old.rect
		WorldMapFrame:SetMapID(old.map)
		ns.db.settings.showOnWorldMap, ns.db.settings.showOnContinent = old.shown, old.continent
		ns.OpenMapCompat.installed = nil
		mock.mouseOver, mock.mapCursorX, mock.mapCursorY = nil, nil, nil
	end
	return state, api, sc
end
local function test(name, fn)
	local state, api, sc = fixture()
	local ok, err = pcall(fn, state, api, sc)
	state:Close()
	if ok then passed = passed + 1; io.write("  ok    ", name, "\n")
	else failed = failed + 1; io.write("  FAIL  ", name, "\n        ", tostring(err), "\n") end
end

test("OpenMap markers span continents and remain visible outside the host map", function(state, api)
	local records = {}
	for i, mapID in ipairs({ 1429, 1414 }) do
		local c, wx, wy = ns.MapToWorld(mapID, 0.43, 0.64)
		records[i] = ns.Database:RecordNPC({ npcID = 987600 + i, name = "OpenMap service " .. i,
			cats = { vendor = true }, cont = c, wx = wx, wy = wy, mapID = mapID, accuracy = 1 })
	end
	Nav:SetWaypointTo(records[2], "vendor")
	local function AssertPins()
		WorldMapFrame:RefreshProviders()
		local found = {}
		for _, pin in ipairs(WorldMapFrame.pins) do
			found[pin.rec] = pin
			check(pin:GetFrameLevel() > api.ArtTopLevel(), "marker is above stitched artwork")
		end
		for _, rec in ipairs(records) do
			check(found[rec], "service on each continent is drawn")
			local x, y = api.CanvasFromWorldPos(rec.c, rec.x, rec.y)
			near(found[rec].normalizedX, x); near(found[rec].normalizedY, y)
		end
		check(found[Nav:GetWaypoint()], "waypoint on the other continent is drawn")
	end
	AssertPins()
	state:View(0, 1, 0, 1, 1429)
	AssertPins()
	state:View(0.05, 0.45, 0.1, 0.9)
	state.callbacks.OpenMap_ViewChanged()
	mock.Advance(0.3)
	for _, pin in ipairs(WorldMapFrame.pins) do check(pin.rec ~= records[1], "panning culls offscreen services") end
	ns.db.settings.showOnWorldMap = false
	WorldMapFrame:RefreshProviders()
	check(#WorldMapFrame.pins == 0, "world-map visibility option respected")
end)

test("OpenMap middle-click uses the actual zone while other mouse handlers remain intact", function(state, api, sc)
	state:View(0, 1, 0, 1, 1429)
	local u, v = api.WorldFromMap(1414, 0.4, 0.6)
	mock.mapCursorX, mock.mapCursorY = api.MapFromWorld(1429, u, v)
	sc.scripts.OnMouseUp(sc, "MiddleButton")
	local wp = Nav:GetWaypoint()
	local c, wx, wy = ns.MapToWorld(1414, 0.4, 0.6)
	check(wp and wp.c == c, "click across continents selects Kalimdor")
	near(wp.x, wx); near(wp.y, wy)
	check(state.originalClicks == 0, "middle-click does not also trigger OpenMap recenter")
	sc.scripts.OnMouseUp(sc, "LeftButton"); sc.scripts.OnMouseUp(sc, "RightButton")
	check(state.originalClicks == 2, "left and right scripts are forwarded")
	state.active = false
	sc.scripts.OnMouseUp(sc, "MiddleButton")
	check(state.originalClicks == 3, "non-stitched maps use their original handler")
end)

test("OpenMap's cell-based icons retain tooltips and support middle-click waypoints", function(state, api)
	local root = CreateFrame("Frame", nil, WorldMapFrame.ScrollContainer)
	local set = CreateFrame("Frame", nil, root)
	local cell = CreateFrame("Frame", nil, set)
	local pin = CreateFrame("Button", nil, cell)
	pin.u, pin.v = api.WorldFromMap(1429, 0.43, 0.64)
	pin.anchor, pin.look, pin.data = {}, {}, { name = "OpenMap town service" }
	pin:SetSize(18, 18)
	pin.Icon = pin:CreateTexture(nil, "ARTWORK")
	pin.Icon:SetAllPoints(); pin.Icon:SetTexture("OpenMapServiceIcon")
	pin:SetScript("OnEnter", function(self) GameTooltip:SetText(self.data.name); GameTooltip:Show() end)
	pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
	mock.mouseOver = pin
	mock.Fire("GLOBAL_MOUSE_DOWN", "MiddleButton"); mock.Fire("GLOBAL_MOUSE_UP", "MiddleButton")
	local _, wx, wy = ns.MapToWorld(1429, 0.43, 0.64)
	check(Nav:GetWaypoint(), "OpenMap icon sets a waypoint")
	near(Nav:GetWaypoint().x, wx); near(Nav:GetWaypoint().y, wy)
	local u, v = pin.u, pin.v
	state:View(u - 0.001, u + 0.001, v - 0.001, v + 0.001)
	check(ns.DetailView:EnterFromMap(), "detail opens at the stitched view's zone even on Azeroth")
	mock.Advance(0.8)
	local mirror
	for _, frame in ipairs(mock.frames) do
		if frame.external and frame.external.frame == pin and frame:IsVisible() then mirror = frame end
	end
	check(mirror, "cell-based OpenMap icon is mirrored")
	mirror.scripts.OnEnter(mirror)
	check(GameTooltip.lines[1] == pin.data.name, "original tooltip retained")
	check(WayfinderDetailView:GetFrameLevel() > 8500, "detail view covers OpenMap's player and icons")
	root:Hide()
end)

test("OpenMap owns scroll zoom and Wayfinder locate uses the stitched view", function(state, api, sc)
	local u, v = api.WorldFromMap(1429, 0.43, 0.64)
	state:View(u - 0.001, u + 0.001, v - 0.001, v + 0.001)
	sc.scripts.OnMouseWheel(sc, 1)
	check(not ns.DetailView:IsActive(), "wheel does not open a competing detail overlay")
	mock.playerMap, mock.playerX, mock.playerY = 1429, 0.42, 0.65
	Nav:ShowPlayerOnMap()
	check(state.shownAt, "locate calls OpenMap's public ShowWorld API")
	local pu, pv = api.WorldFromMap(1429, 0.42, 0.65)
	near(state.shownAt[1], pu); near(state.shownAt[2], pv)
	check(ns.DetailView:EnterFromMap(), "manual detail view remains available")
	state.callbacks.OpenMap_ViewChanged()
	check(ns.DetailView:IsActive(), "an in-flight view callback does not close manual detail")
	state.active = false
	state.callbacks.OpenMap_StitchedChanged()
	check(not ns.DetailView:IsActive(), "switching to Blizzard's map closes the stitched detail")
end)

io.write(("\n%d OpenMap checks passed, %d failed\n"):format(passed, failed))
return failed
