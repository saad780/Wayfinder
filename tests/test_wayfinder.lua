-- Behavioural tests for Wayfinder, run against tests/wowmock.lua by tests/run_tests.py.
local ns = Wayfinder
local tests = {}
local function test(name, fn) table.insert(tests, { name = name, fn = fn }) end

local function near(a, b, eps, what)
	if math.abs(a - b) > (eps or 1e-6) then
		error(("%s: expected %s, got %s"):format(what or "value", tostring(b), tostring(a)), 2)
	end
end
local function eq(a, b, what)
	if a ~= b then
		error(("%s: expected %s, got %s"):format(what or "value", tostring(b), tostring(a)), 2)
	end
end
local function ok(v, what)
	if not v then error((what or "assertion") .. " failed", 2) end
end

local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

local function setPlayer(mapID, x, y)
	mock.playerMap, mock.playerX, mock.playerY = mapID, x, y
end

local function playerWorld()
	local cont, wx, wy = ns.GetPlayerWorld()
	return cont, wx, wy
end

local function findRecord(predicate)
	for _, rec in pairs(ns.db.pois) do
		if predicate(rec) then return rec end
	end
end

---------------------------------------------------------------------------
-- Geometry
---------------------------------------------------------------------------
test("map rectangles come out of GetWorldPosFromMapPos exactly", function()
	local r = ns.GetMapRect(1429)
	local m = mock.maps[1429]
	eq(r.cont, 0, "continent")
	near(r.top, m.top, 1e-6, "top")
	near(r.left, m.left, 1e-6, "left")
	near(r.width, m.width, 1e-6, "width")
	near(r.height, m.height, 1e-6, "height")
	eq(ns.GetMapRect(947), nil, "world map has no rect")
end)

test("map <-> world round trip", function()
	local cont, wx, wy = ns.MapToWorld(1429, 0.42, 0.65)
	local x, y = ns.WorldToMapRect(ns.GetMapRect(1429), wx, wy)
	near(x, 0.42, 1e-9, "x")
	near(y, 0.65, 1e-9, "y")
end)

test("Northshire Abbey lands on minimap tile azeroth 32_48 (FileDataID 204493)", function()
	-- Northshire Abbey, Classic world coordinates (north, west)
	local col, row = ns.WorldToTile(-8914, -133)
	eq(col, 32, "column")
	eq(row, 48, "row")
	eq(ns.TileData[0][ns.TileKey(col, row)], 204493, "file id")
end)

test("tile origin and cell lookup agree", function()
	local px, py = ns.TileOrigin(32, 48)
	near(px, 0, 1e-9, "origin x")
	near(py, 16 * ns.TILE, 1e-9, "origin y")
	for i = 1, 500 do
		local wx = math.random() * 20000 - 10000
		local wy = math.random() * 20000 - 10000
		local ppx, ppy = ns.WorldToPlane(wx, wy)
		local col, row, cx, cy = ns.PlaneToCell(ppx, ppy)
		local ox, oy = ns.TileOrigin(col, row)
		ok(ppx >= ox + cx * ns.CELL - 1e-6 and ppx <= ox + (cx + 1) * ns.CELL + 1e-6, "x within cell")
		ok(ppy >= oy + cy * ns.CELL - 1e-6 and ppy <= oy + (cy + 1) * ns.CELL + 1e-6, "y within cell")
		local tcol, trow = ns.WorldToTile(wx, wy)
		eq(tcol, col, "tile column agrees")
		eq(trow, row, "tile row agrees")
	end
end)

---------------------------------------------------------------------------
-- Exploration
---------------------------------------------------------------------------
test("explored-cell rectangles cover exactly the explored cells", function()
	for trial = 1, 300 do
		local rows = {}
		for r = 1, 16 do
			local v = 0
			for b = 0, 15 do
				if math.random() < (trial % 3 == 0 and 0.9 or 0.4) then v = v + 2 ^ b end
			end
			rows[r] = v
		end
		local covered = {}
		for _, rect in ipairs(ns.ExploredRectangles(rows)) do
			for y = rect[3], rect[4] - 1 do
				for x = rect[1], rect[2] - 1 do
					local key = y * 16 + x
					ok(not covered[key], "rectangles overlap")
					covered[key] = true
				end
			end
		end
		for y = 0, 15 do
			for x = 0, 15 do
				eq(not not covered[y * 16 + x], ns.HasBit(rows[y + 1], x), ("cell %d,%d"):format(x, y))
			end
		end
	end
	local full = {}
	for r = 1, 16 do full[r] = 65535 end
	eq(#ns.ExploredRectangles(full), 1, "full tile is a single rectangle")
end)

test("walking reveals the minimap radius around the player", function()
	setPlayer(1429, 0.42, 0.65)
	mock.Advance(1)
	local cont, wx, wy = playerWorld()
	ok(ns.Exploration:IsExplored(cont, wx, wy), "player's spot explored")
	ok(ns.Exploration:IsExplored(cont, wx + 90, wy), "90 yards away explored (radius 120)")
	ok(not ns.Exploration:IsExplored(cont, wx + 400, wy + 400), "far away not explored")
end)

test("world map exploration is imported in the background", function()
	mock.Advance(30, 0.1)
	local imported = ns.db.imported[ns:GetCharacterKey()]
	ok(imported[1429], "Elwynn imported")
	local inside = { ns.MapToWorld(1429, 0.45, 0.55) }
	local outside = { ns.MapToWorld(1429, 0.85, 0.2) }
	ok(ns.Exploration:IsExplored(inside[1], inside[2], inside[3]), "discovered area explored")
	ok(not ns.Exploration:IsExplored(outside[1], outside[2], outside[3]), "undiscovered area not explored")
end)

test("sharing exploration combines characters", function()
	local cont, wx, wy = ns.MapToWorld(1429, 0.9, 0.9)
	ok(not ns.Exploration:IsExplored(cont, wx, wy), "not explored by this character")
	local px, py = ns.WorldToPlane(wx, wy)
	local col, row, cx, cy = ns.PlaneToCell(px, py)
	local rows = {}
	for r = 1, 16 do rows[r] = 0 end
	rows[cy + 1] = 2 ^ cx
	ns.db.explored["Alt-TestRealm"] = { [cont] = { [ns.TileKey(col, row)] = rows } }
	ns:SetSetting("shareExploration", true)
	ok(ns.Exploration:IsExplored(cont, wx, wy), "explored by the alt")
	ns:SetSetting("shareExploration", false)
	ok(not ns.Exploration:IsExplored(cont, wx, wy), "back to this character only")
end)

---------------------------------------------------------------------------
-- Classification
---------------------------------------------------------------------------
test("NPC titles map to the right categories", function()
	local C = ns.Categories
	local function cats(title)
		local set, class = C:ClassifyTitle(title)
		local list = {}
		for k in pairs(set or {}) do list[#list + 1] = k end
		table.sort(list)
		return table.concat(list, ","), class
	end
	eq(cats("Banker"), "bank", "Banker")
	eq(cats("Innkeeper"), "food,inn", "Innkeeper")
	eq(cats("Gryphon Master"), "flight", "Gryphon Master")
	eq(cats("Wind Rider Master"), "flight", "Wind Rider Master")
	local c, class = cats("Warrior Trainer")
	eq(c, "trainer_class", "Warrior Trainer")
	eq(class, "WARRIOR", "warrior token")
	eq(cats("Alchemy Trainer"), "trainer_prof", "Alchemy Trainer")
	eq(cats("Riding Instructor"), "trainer_prof", "Riding Instructor")
	c, class = cats("Pet Trainer")
	eq(class, "HUNTER", "pet trainer is a hunter trainer")
	eq(cats("Weapon Master"), "weaponmaster", "Weapon Master")
	eq(cats("Wine & Spirits Merchant"), "food,vendor", "Wine & Spirits")
	eq(cats("Reagents"), "reagent,vendor", "Reagents")
	eq(cats("Bowyer"), "ammo,vendor", "Bowyer")
	eq(cats("Tailoring Supplies"), "vendor", "Tailoring Supplies")
	eq(cats("Zeppelin Master"), "transport", "Zeppelin Master")
	eq(cats("Stable Master"), "stable", "Stable Master")
	eq(cats("Spirit Healer"), "spirit", "Spirit Healer")
	eq(cats("Cloth Armor Merchant"), "vendor", "Cloth Armor Merchant")
	eq(cats("Salesman of Scales"), "", "no whole-word 'ale' match")
	eq(C:ClassifyTitle(nil), nil, "no title")
	eq(C:ClassifyTitle("Stormwind City Guard"), nil, "guards are not services")
end)

---------------------------------------------------------------------------
-- Recording
---------------------------------------------------------------------------
local function setUnit(unit, info)
	mock.units[unit] = info
end

test("mouseover sightings record approximately and converge", function()
	setPlayer(1429, 0.42, 0.65)
	setUnit("mouseover", { name = "Remy", title = "Banker", npcID = 4321, distance = 20, faction = "Alliance",
		guid = "Creature-0-1-0-1-4321-0001" })
	mock.Fire("UPDATE_MOUSEOVER_UNIT")
	local rec = findRecord(function(r) return r.id == 4321 end)
	ok(rec, "recorded")
	eq(rec.a, 28, "accuracy band")
	ok(rec.cats.bank, "bank category")
	eq(rec.f, 1, "faction")
	-- closer sighting from a different spot replaces the estimate
	mock.time = mock.time + 10
	setPlayer(1429, 0.4205, 0.6505)
	mock.units.mouseover.distance = 5
	mock.Fire("UPDATE_MOUSEOVER_UNIT")
	eq(rec.a, 10, "refined accuracy")
	local _, wx, wy = playerWorld()
	near(rec.x, wx, 1e-6, "moved to closer sighting x")
	eq(count(ns.db.pois) > 0, true, "has records")
	-- far away sightings are ignored
	setUnit("mouseover", { name = "Far Banker", title = "Banker", npcID = 9999, distance = 80,
		guid = "Creature-0-1-0-1-9999-0001" })
	mock.Fire("UPDATE_MOUSEOVER_UNIT")
	ok(not findRecord(function(r) return r.id == 9999 end), "too far to place")
end)

test("secret identities are never recorded", function()
	setUnit("mouseover", { name = mock.SECRET, title = "Banker", npcID = mock.SECRET, distance = 5, guid = mock.SECRET })
	mock.time = mock.time + 10
	mock.Fire("UPDATE_MOUSEOVER_UNIT")
	for _, rec in pairs(ns.db.pois) do
		ok(not issecretvalue(rec.id) and not issecretvalue(rec.n), "no secret stored")
	end
end)

test("talking to a merchant records vendor, repair and what they sell", function()
	setPlayer(1429, 0.43, 0.66)
	setUnit("npc", { name = "Brog", title = "Food & Drink", npcID = 555, faction = "Alliance",
		guid = "Creature-0-1-0-1-555-0001" })
	mock.canRepair = true
	mock.merchantItems = {
		{ link = "|cffffffff|Hitem:1|h[Bread]|h|r", classID = 0, subClassID = 0, spell = "Food" },
		{ link = "|cffffffff|Hitem:2|h[Water]|h|r", classID = 0, subClassID = 5, spell = "Drink" },
		{ link = "|cffffffff|Hitem:3|h[Arrow]|h|r", classID = 6, subClassID = 2 },
	}
	mock.Fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", Enum.PlayerInteractionType.Merchant)
	mock.Advance(1)
	local rec = findRecord(function(r) return r.id == 555 end)
	ok(rec, "recorded")
	eq(rec.a, 4, "exact")
	ok(rec.cats.vendor and rec.cats.repair and rec.cats.food and rec.cats.ammo, "vendor, repair, food, ammo")
	ok(rec.talked, "marked as talked to")
	mock.canRepair = false
end)

test("mailboxes are recorded where you open them and deduplicated", function()
	setPlayer(1429, 0.44, 0.67)
	mock.Fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", Enum.PlayerInteractionType.MailInfo)
	setPlayer(1429, 0.4401, 0.6701)
	mock.Fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", Enum.PlayerInteractionType.MailInfo)
	local n = 0
	for _, rec in pairs(ns.db.pois) do
		if rec.kind == "obj" and rec.cats.mailbox then n = n + 1 end
	end
	eq(n, 1, "one mailbox")
end)

test("class trainer windows record a trainer for your class", function()
	setUnit("npc", { name = "Elsharin", title = "Mage Trainer", npcID = 198, guid = "Creature-0-1-0-1-198-0001" })
	mock.tradeskillTrainer = false
	mock.Fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", Enum.PlayerInteractionType.Trainer)
	local rec = findRecord(function(r) return r.id == 198 end)
	ok(rec and rec.cats.trainer_class, "class trainer")
	eq(rec.cls, "MAGE", "class")
	mock.tradeskillTrainer = true
	setUnit("npc", { name = "Lien", title = "Alchemy Trainer", npcID = 1215, guid = "Creature-0-1-0-1-1215-0001" })
	mock.Fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", Enum.PlayerInteractionType.Trainer)
	ok(findRecord(function(r) return r.id == 1215 end).cats.trainer_prof, "profession trainer")
	mock.tradeskillTrainer = false
end)

test("quest givers are recorded from gossip with quests", function()
	setUnit("npc", { name = "Marshal", npcID = 197, guid = "Creature-0-1-0-1-197-0001" })
	mock.gossipQuests = 1
	mock.Fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", Enum.PlayerInteractionType.Gossip)
	ok(findRecord(function(r) return r.id == 197 end).cats.quest, "quest giver")
	mock.gossipQuests = 0
	setUnit("npc", { name = "Chatty", npcID = 777, guid = "Creature-0-1-0-1-777-0001" })
	mock.Fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", Enum.PlayerInteractionType.Gossip)
	ok(not findRecord(function(r) return r.id == 777 end), "plain gossip NPC not recorded")
end)

test("guard directions record the marked place, then merge with the NPC", function()
	C_GossipInfo.options = { { gossipOptionID = 10, name = "Class Trainer" } }
	C_GossipInfo.SelectOption(10)
	C_GossipInfo.options = { { gossipOptionID = 11, name = "Warrior" } }
	C_GossipInfo.SelectOption(11)
	mock.playerMap = 1453
	mock.gossipPoi = { name = "Wu Shen", position = CreateVector2D(0.80, 0.60), textureIndex = 7 }
	mock.Fire("DYNAMIC_GOSSIP_POI_UPDATED")
	local rec = findRecord(function(r) return r.guard end)
	ok(rec and rec.cats.trainer_class, "guard spot recorded")
	eq(rec.cls, "WARRIOR", "warrior trainer")
	-- walk there and talk to the trainer
	setPlayer(1453, 0.8003, 0.6002)
	setUnit("npc", { name = "Wu Shen", title = "Warrior Trainer", npcID = 5479, guid = "Creature-0-1-0-1-5479-0001" })
	mock.Fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", Enum.PlayerInteractionType.Gossip)
	local n = 0
	for _, r in pairs(ns.db.pois) do if r.cats.trainer_class and r.cls == "WARRIOR" then n = n + 1 end end
	eq(n, 1, "one record for the trainer")
	eq(rec.id, 5479, "npc id filled in")
	mock.gossipPoi = nil
end)

test("known flight paths are imported", function()
	mock.Advance(10)
	local rec = ns.db.pois.t2
	ok(rec, "flight path record")
	eq(rec.f, 1, "Alliance")
	ok(rec.cats.flight, "flight category")
end)

---------------------------------------------------------------------------
-- Built-in locations
---------------------------------------------------------------------------
test("built-in locations appear only once explored", function()
	-- pick a mailbox nobody has explored yet
	local cont, wx, wy
	local function visibleAt(x, y)
		local found = false
		ns.Seeds:Query(cont, x - 5, x + 5, y - 5, y + 5, function(s) if s.cats.mailbox then found = true end end)
		return found
	end
	for _, entry in ipairs(ns.SeedData) do
		if entry.cat == "mailbox" then
			for i = 1, #entry.pts, 4 do
				local c, x, y = ns.MapToWorld(entry.pts[i], entry.pts[i + 1] / 100, entry.pts[i + 2] / 100)
				if c == 0 and not ns.Exploration:IsExplored(c, x, y) then
					cont, wx, wy = c, x, y
					break
				end
			end
		end
		if cont then break end
	end
	ok(cont, "an unexplored mailbox in Stormwind or Elwynn")
	ok(not visibleAt(wx, wy), "hidden before exploring")
	ns.Exploration:MarkCircle(cont, wx, wy, 40)
	ok(visibleAt(wx, wy), "revealed after exploring")
	-- a recorded mailbox right there replaces the built-in one
	ns.Database:RecordObject({ cat = "mailbox", cont = cont, wx = wx + 3, wy = wy, accuracy = 4 })
	ok(not visibleAt(wx, wy), "superseded by recorded mailbox")
end)

test("transports are part of the built-in set", function()
	local n = 0
	ns.Seeds:Query(0, -20000, 20000, -20000, 20000, function() end)
	for _, t in ipairs(ns.TransportData) do n = n + 1 end
	ok(n >= 20, "transport entries")
end)

---------------------------------------------------------------------------
-- World map icons
---------------------------------------------------------------------------
test("world map shows icons for the open zone only", function()
	WorldMapFrame.mapID = 1429
	WorldMapFrame:RefreshProviders()
	local elwynn = #WorldMapFrame.pins
	ok(elwynn > 0, "pins on Elwynn")
	for _, pin in ipairs(WorldMapFrame.pins) do
		ok(pin.normalizedX >= 0 and pin.normalizedX <= 1, "x on map")
		ok(pin.rec.id ~= 5479, "Stormwind trainer not on the Elwynn map")
		ok(pin.Icon.texture or pin.Icon.atlas, "icon set")
	end
	WorldMapFrame.mapID = 1453
	WorldMapFrame:RefreshProviders()
	local function onMap(predicate)
		for _, pin in ipairs(WorldMapFrame.pins) do if predicate(pin.rec) then return true end end
		return false
	end
	ok(onMap(function(r) return r.k == "t2" end), "Stormwind flight master on the Stormwind map")
	ok(not onMap(function(r) return r.id == 5479 end), "a mage does not see warrior trainers by default")
	ns:SetSetting("showAllClassTrainers", true)
	WorldMapFrame:RefreshProviders()
	ok(onMap(function(r) return r.id == 5479 end), "warrior trainer shown with all class trainers on")
	ns:SetSetting("showAllClassTrainers", false)
end)

test("icons still show if the game only names the continent for a spot", function()
	local original = C_Map.GetMapPosFromWorldPos
	C_Map.GetMapPosFromWorldPos = function(cont) return cont == 0 and 1415 or 1414, CreateVector2D(0.5, 0.5) end
	-- forget cached answers by touching every record
	for _, rec in pairs(ns.db.pois) do ns:Fire("POI_UPDATED", rec, false) end
	WorldMapFrame.mapID = 1429
	WorldMapFrame:RefreshProviders()
	ok(#WorldMapFrame.pins > 0, "pins still on Elwynn")
	C_Map.GetMapPosFromWorldPos = original
	for _, rec in pairs(ns.db.pois) do ns:Fire("POI_UPDATED", rec, false) end
end)

test("turning a category off hides its icons", function()
	WorldMapFrame.mapID = 1429
	ns:SetCategoryEnabled("bank", false)
	WorldMapFrame:RefreshProviders()
	for _, pin in ipairs(WorldMapFrame.pins) do ok(pin.catID ~= "bank", "no bank icons") end
	ns:SetCategoryEnabled("bank", true)
	eq(ns.db.settings.cats.bank, true, "saved")
end)

---------------------------------------------------------------------------
-- Detail view
---------------------------------------------------------------------------
test("scrolling past max zoom opens the detail view over the same area", function()
	WorldMapFrame.mapID = 1429
	local container = WorldMapFrame.ScrollContainer
	container.atMax = true
	mock.time = mock.time + 1
	container.scripts.OnMouseWheel(container, 1)
	ok(ns.DetailView:IsActive(), "active")
	local view = WayfinderDetailView
	ok(view.shown, "shown")
	ok(view.level > 3100, "above the map's pins")
	mock.Advance(1)
	local tiles = 0
	for _, f in ipairs(mock.frames) do
		for _, t in ipairs(f.textures or {}) do
			if t.shown and type(t.texture) == "number" and t.texture > 200000 and t.texture < 9000000 and t.texture ~= 136460 then
				tiles = tiles + 1
			end
		end
	end
	ok(tiles > 0, "terrain textures drawn")
end)

test("detail view zooms, pans and returns to the map", function()
	local view = WayfinderDetailView
	local s0 = ns.DetailView.entryX
	for i = 1, 4 do view.scripts.OnMouseWheel(view, 1) end
	mock.Advance(1)
	-- drag
	mock.cursorX, mock.cursorY = 500, 350
	view.scripts.OnMouseDown(view, "LeftButton")
	mock.mouseDown = "LeftButton"
	local before = { ns.DetailView.entryX }
	mock.cursorX = 300
	mock.Advance(0.2)
	mock.mouseDown = nil
	view.scripts.OnMouseUp(view, "LeftButton")
	-- a drag released outside the view must not stick
	view.scripts.OnMouseDown(view, "LeftButton")
	mock.Advance(0.1)
	mock.cursorX = 100
	mock.Advance(0.1)
	-- zoom all the way out: exits
	for i = 1, 30 do
		if not ns.DetailView:IsActive() then break end
		view.scripts.OnMouseWheel(view, -1)
		mock.Advance(0.3)
	end
	ok(not ns.DetailView:IsActive(), "closed by zooming out")
	ok(WorldMapFrame.pannedTo, "world map panned to where we looked")
end)

test("the detail view does not open below max zoom or when disabled", function()
	local container = WorldMapFrame.ScrollContainer
	container.atMax = false
	mock.time = mock.time + 1
	container.scripts.OnMouseWheel(container, 1)
	ok(not ns.DetailView:IsActive(), "not at max zoom")
	container.atMax = true
	ns:SetSetting("detailEnabled", false)
	mock.time = mock.time + 1
	container.scripts.OnMouseWheel(container, 1)
	ok(not ns.DetailView:IsActive(), "disabled")
	ns:SetSetting("detailEnabled", true)
	-- Blizzard zoomed during this very wheel event: not yet
	WorldMapFrame:OnCanvasScaleChanged()
	container.scripts.OnMouseWheel(container, 1)
	ok(not ns.DetailView:IsActive(), "map was still zooming")
end)

-- Splits one active tile's textures into the full-brightness base, fog pieces and
-- (Hidden mode) bright explored pieces.
local function TileTextures(key)
	local base, fog, pieces = {}, {}, {}
	for _, tex in ipairs(ns.DetailView.activeTiles[key] or {}) do
		if tex.shown then
			if tex.subLevel == 0 then
				table.insert(base, tex)
			elseif tex.subLevel == 2 then
				table.insert(fog, tex)
			elseif tex.subLevel == 1 then
				table.insert(pieces, tex)
			else
				error("unexpected terrain texture on tile " .. key)
			end
		end
	end
	return base, fog, pieces
end

local function IsCasePiece(tex)
	return type(tex.texture) == "string" and tex.texture:find("Fog%d+$") ~= nil
end

local function CountCasePieces()
	local n = 0
	for key in pairs(ns.DetailView.activeTiles) do
		local _, fog = TileTextures(key)
		for _, tex in ipairs(fog) do
			if IsCasePiece(tex) then n = n + 1 end
		end
	end
	return n
end

local function SomeActiveTile()
	for key in pairs(ns.DetailView.activeTiles) do
		if ns.TileData[0][key] then return key end
	end
end

---------------------------------------------------------------------------
-- Fog pieces (marching squares)
---------------------------------------------------------------------------
local function GridLookup(grid)
	return function(i, j) return grid[j * 100 + i] == true end
end

-- Every point of the area the tile is responsible for is covered by exactly one
-- piece (or none where all four surrounding cells are explored), and each soft
-- piece's case matches the cells at its corners.
local function CheckPieces(grid, missing)
	local pieces = ns.FogPieces(GridLookup(grid), missing)
	local x0 = missing.west and 0 or 0.5
	local y0 = missing.north and 0 or 0.5
	local x1 = missing.east and 16 or 16.5
	local y1 = missing.south and 16 or 16.5
	local function E(a, b) return grid[b * 100 + a] == true end
	for sy = y0 + 0.125, y1, 0.25 do
		for sx = x0 + 0.125, x1, 0.25 do
			local hits = 0
			for _, p in ipairs(pieces) do
				if sx > p[2] and sx < p[3] and sy > p[4] and sy < p[5] then hits = hits + 1 end
			end
			local i, j = math.floor(sx - 0.5), math.floor(sy - 0.5)
			local clear = E(i, j) and E(i + 1, j) and E(i, j + 1) and E(i + 1, j + 1)
			if hits ~= (clear and 0 or 1) then
				error(("point %.3f,%.3f covered %d times"):format(sx, sy, hits))
			end
		end
	end
	for _, p in ipairs(pieces) do
		ok(p[2] >= x0 - 1e-9 and p[3] <= x1 + 1e-9 and p[4] >= y0 - 1e-9 and p[5] <= y1 + 1e-9, "piece inside the tile's area")
		if p[1] ~= 0 then
			local i, j = p[2] - p[6] - 0.5, p[4] - p[8] - 0.5
			local function V(a, b) return E(a, b) and 1 or 0 end
			eq(p[1], V(i, j) + 2 * V(i + 1, j) + 4 * V(i, j + 1) + 8 * V(i + 1, j + 1), "case of piece")
			near(p[7] - p[6], p[3] - p[2], 1e-9, "texture width matches piece")
			near(p[9] - p[8], p[5] - p[4], 1e-9, "texture height matches piece")
		end
	end
	return pieces
end

local NONE = {}

test("fog pieces: nothing over fully explored ground", function()
	local grid = {}
	for j = -1, 16 do for i = -1, 16 do grid[j * 100 + i] = true end end
	eq(#CheckPieces(grid, NONE), 0, "no fog")
end)

test("fog pieces: unexplored ground is a single solid rectangle", function()
	local pieces = CheckPieces({}, NONE)
	eq(#pieces, 1, "one piece")
	eq(pieces[1][1], 0, "solid")
end)

test("fog pieces: an explored cell gets four soft corners", function()
	local pieces = CheckPieces({ [5 * 100 + 5] = true }, NONE)
	local cases = {}
	for _, p in ipairs(pieces) do
		if p[1] ~= 0 then cases[(p[4] - 0.5) * 100 + (p[2] - 0.5)] = p[1] end
	end
	eq(cases[4 * 100 + 4], 8, "top-left piece has the cell at its bottom-right")
	eq(cases[4 * 100 + 5], 4, "top-right piece")
	eq(cases[5 * 100 + 4], 2, "bottom-left piece")
	eq(cases[5 * 100 + 5], 1, "bottom-right piece")
end)

test("fog pieces tile the area exactly, coasts included", function()
	math.randomseed(7)
	for trial = 1, 150 do
		local grid = {}
		local density = ({ 0.2, 0.5, 0.85 })[trial % 3 + 1]
		for j = -1, 16 do
			for i = -1, 16 do
				if math.random() < density then grid[j * 100 + i] = true end
			end
		end
		local missing = {
			west = math.random() < 0.3, east = math.random() < 0.3,
			north = math.random() < 0.3, south = math.random() < 0.3,
		}
		CheckPieces(grid, missing)
	end
end)

---------------------------------------------------------------------------
-- Fog in the detail view
---------------------------------------------------------------------------
test("darkened mode: full terrain with soft fog over unexplored ground", function()
	eq(ns:GetSetting("unexploredTerrain"), ns.UNEXPLORED_DARKENED, "default mode")
	local container = WorldMapFrame.ScrollContainer
	mock.time = mock.time + 1
	container.scripts.OnMouseWheel(container, 1)
	ok(ns.DetailView:IsActive(), "active again")
	mock.Advance(0.5)
	local tiles = 0
	for key in pairs(ns.DetailView.activeTiles) do
		if ns.TileData[0][key] then
			tiles = tiles + 1
			local base, fog, pieces = TileTextures(key)
			eq(#base, 1, "one base texture for tile " .. key)
			eq(base[1].texture, ns.TileData[0][key], "terrain image")
			near(base[1].w, ns.TILE, 1e-9, "whole tile")
			ok(not base[1].vertex or base[1].vertex[1] == 1, "full brightness")
			eq(#pieces, 0, "no separate explored pieces")
			for _, tex in ipairs(fog) do
				near(tex.alpha, 0.6, 1e-9, "fog strength")
				ok(tex.texture == "color" or IsCasePiece(tex), "fog piece")
			end
		end
	end
	ok(tiles > 0, "tiles in view")
	ok(CountCasePieces() > 0, "soft edges where explored meets unexplored")

	ns:SetSetting("unexploredBrightness", 0.25)
	local _, fog = TileTextures(SomeActiveTile())
	if #fog > 0 then near(fog[1].alpha, 0.75, 1e-9, "brighter setting, thicker fog") end
	ns:SetSetting("unexploredBrightness", 0.4)
end)

test("exploring a tile's edge updates its neighbour's fog", function()
	local mine = ns.db.explored[ns:GetCharacterKey()][0]
	local key, west
	for k in pairs(ns.DetailView.activeTiles) do
		local col, row = ns.SplitTileKey(k)
		local w = (col - 1) * 100 + row
		if ns.TileData[0][k] and ns.TileData[0][w] and ns.DetailView.activeTiles[w] then
			key, west = k, w
			break
		end
	end
	ok(key, "two neighbouring tiles in view")
	local savedKey, savedWest = mine[key], mine[west]
	local function Empty()
		local rows = {}
		for r = 1, 16 do rows[r] = 0 end
		return rows
	end
	mine[key], mine[west] = Empty(), Empty()
	ns:Fire("EXPLORED", 0, { key, west })
	-- soft pieces along the west tile's east edge (not its bottom row, which reads
	-- the tile below)
	local wcol, wrow = ns.SplitTileKey(west)
	local ox, oy = ns.TileOrigin(wcol, wrow)
	local function westCasePieces()
		local n = 0
		local _, fog = TileTextures(west)
		for _, tex in ipairs(fog) do
			local at = tex.points.TOPLEFT
			if IsCasePiece(tex) and at[3] >= ox + 15.5 * ns.CELL - 1e-6 and -at[4] < oy + 15.5 * ns.CELL - 1e-6 then
				n = n + 1
			end
		end
		return n
	end
	eq(westCasePieces(), 0, "solid fog when both are unexplored")
	local edge = {}
	for r = 1, 16 do edge[r] = 1 end -- the east tile's westmost column
	mine[key] = edge
	ns:Fire("EXPLORED", 0, { key })
	ok(westCasePieces() > 0, "west neighbour's edge now fades into the explored column")
	mine[key], mine[west] = savedKey, savedWest
	ns:Fire("EXPLORED", 0, { key, west })
end)

test("shown and hidden modes", function()
	ns:SetSetting("unexploredTerrain", ns.UNEXPLORED_SHOWN)
	for k in pairs(ns.DetailView.activeTiles) do
		if ns.TileData[0][k] then
			local base, fog, pieces = TileTextures(k)
			eq(#base, 1, "base when shown")
			eq(#fog + #pieces, 0, "nothing else when shown")
		end
	end
	ns:SetSetting("unexploredTerrain", ns.UNEXPLORED_HIDDEN)
	for k in pairs(ns.DetailView.activeTiles) do
		local base, fog = TileTextures(k)
		eq(#base + #fog, 0, "only explored pieces when hidden")
	end
	ns:SetSetting("unexploredTerrain", ns.UNEXPLORED_DARKENED)
	setPlayer(1429, 0.5, 0.7)
	mock.Advance(1)
	ns.DetailView:Exit()
end)

test("zoomed far out the fog is drawn without soft edges", function()
	WorldMapFrame.mapID = 1415 -- the continent: the view starts zoomed out
	local container = WorldMapFrame.ScrollContainer
	mock.time = mock.time + 1
	container.scripts.OnMouseWheel(container, 1)
	ok(ns.DetailView:IsActive(), "opened from the continent map")
	-- the land tile closest to the middle of the view stays in view as it zooms in
	local land, best
	for key in pairs(ns.DetailView.activeTiles) do
		if ns.TileData[0][key] then
			local kc, kr = ns.SplitTileKey(key)
			local tx, ty = ns.TileOrigin(kc, kr)
			local d = math.abs(tx + ns.TILE / 2 - ns.DetailView.entryX) + math.abs(ty + ns.TILE / 2 - ns.DetailView.entryY)
			if not best or d < best then land, best = key, d end
		end
	end
	ok(land, "a land tile in view")
	local col, row = ns.SplitTileKey(land)
	local px, py = ns.TileOrigin(col, row)
	local wx, wy = ns.PlaneToWorld(px + ns.TILE / 2, py + ns.TILE / 2)
	ns.Exploration:MarkCircle(0, wx, wy, 150)
	eq(CountCasePieces(), 0, "no soft pieces while cells are tiny")
	mock.Advance(1) -- the entry zoom step crosses the threshold
	ok(CountCasePieces() > 0, "soft pieces once cells are big enough")
	local view = WayfinderDetailView
	view.scripts.OnMouseWheel(view, -1)
	mock.Advance(1)
	eq(CountCasePieces(), 0, "back to plain fog when zoomed out again")
	ns.DetailView:Exit()
	WorldMapFrame.mapID = 1429
end)

test("the old show-unexplored setting carries over", function()
	WayfinderDB.settings.revealAll = true
	WayfinderDB.settings.unexploredTerrain = nil
	mock.Fire("ADDON_LOADED", "Wayfinder")
	eq(ns.db.settings.unexploredTerrain, ns.UNEXPLORED_SHOWN, "shown")
	eq(ns.db.settings.revealAll, nil, "old setting removed")
	WayfinderDB.settings.revealAll = false
	WayfinderDB.settings.unexploredTerrain = nil
	mock.Fire("ADDON_LOADED", "Wayfinder")
	eq(ns.db.settings.unexploredTerrain, ns.UNEXPLORED_DARKENED, "off becomes the new default")
	eq(ns.db.settings.revealAll, nil, "old setting removed")
end)

---------------------------------------------------------------------------
-- Menu, options, slash commands
---------------------------------------------------------------------------
test("the world map menu toggles categories", function()
	local button = WayfinderMapButton
	button.scripts.OnClick(button)
	local menu = mock.lastMenu
	local checkboxes = 0
	for _, item in ipairs(menu.items) do
		if item.kind == "checkbox" then checkboxes = checkboxes + 1 end
	end
	ok(checkboxes >= #ns.CategoryList, "a checkbox per category")
	local first = menu.items[2]
	eq(first.text, ns.CategoryList[1].label, "first category")
	first.b() -- toggle
	eq(ns:IsCategoryEnabled(ns.CategoryList[1].id), false, "toggled off")
	first.b()
	eq(ns:IsCategoryEnabled(ns.CategoryList[1].id), true, "toggled on")
end)

test("the world map menu picks how unexplored terrain is drawn", function()
	local button = WayfinderMapButton
	button.scripts.OnClick(button)
	local radios = {}
	for _, item in ipairs(mock.lastMenu.items) do
		if item.kind == "radio" then table.insert(radios, item) end
	end
	eq(#radios, 3, "three choices")
	eq(radios[1].text, "Hidden", "first")
	eq(radios[3].text, "Shown", "last")
	ok(radios[2].a(), "Darkened selected")
	radios[3].b()
	eq(ns:GetSetting("unexploredTerrain"), ns.UNEXPLORED_SHOWN, "switched")
	ok(radios[3].a() and not radios[2].a(), "selection follows")
	eq(mock.settings.WAYFINDER_unexploredTerrain.tbl.unexploredTerrain, ns.UNEXPLORED_SHOWN, "panel setting sees it")
	radios[2].b()
	eq(#mock.dropdowns.unexploredTerrain, 3, "options panel dropdown has three choices")
end)

test("every setting is registered with the options panel", function()
	for key, default in pairs(ns.defaults) do
		if key ~= "cats" and key ~= "debug" then
			ok(ns.settingObjects[key], "setting object for " .. key)
		end
	end
	for _, cat in ipairs(ns.CategoryList) do
		ok(ns.settingObjects["cats." .. cat.id], "category setting " .. cat.id)
	end
end)

test("slash commands", function()
	mock.printed = ""
	SlashCmdList.WAYFINDER("stats")
	ok(mock.printed:find("recorded locations"), "stats printed")
	SlashCmdList.WAYFINDER("hide all")
	for _, cat in ipairs(ns.CategoryList) do eq(ns:IsCategoryEnabled(cat.id), false, cat.id) end
	SlashCmdList.WAYFINDER("show all")
	for _, cat in ipairs(ns.CategoryList) do eq(ns:IsCategoryEnabled(cat.id), true, cat.id) end
	SlashCmdList.WAYFINDER("reveal hide")
	eq(ns:GetSetting("unexploredTerrain"), ns.UNEXPLORED_HIDDEN, "reveal hide")
	SlashCmdList.WAYFINDER("reveal")
	eq(ns:GetSetting("unexploredTerrain"), ns.UNEXPLORED_DARKENED, "cycles to darkened")
	SlashCmdList.WAYFINDER("reveal")
	eq(ns:GetSetting("unexploredTerrain"), ns.UNEXPLORED_SHOWN, "cycles to shown")
	SlashCmdList.WAYFINDER("reveal")
	eq(ns:GetSetting("unexploredTerrain"), ns.UNEXPLORED_HIDDEN, "cycles back to hidden")
	SlashCmdList.WAYFINDER("reveal bogus")
	eq(ns:GetSetting("unexploredTerrain"), ns.UNEXPLORED_HIDDEN, "bad argument changes nothing")
	SlashCmdList.WAYFINDER("reveal dim")
	eq(ns:GetSetting("unexploredTerrain"), ns.UNEXPLORED_DARKENED, "reveal dim")
	SlashCmdList.WAYFINDER("here")
	ok(mock.printed:find("tile"), "position printed")
	SlashCmdList.WAYFINDER("reset nonsense")
	eq(mock.popup, nil, "no popup for bad target")
	SlashCmdList.WAYFINDER("reset pois")
	eq(mock.popup.data, "pois", "confirmation asked")
	StaticPopupDialogs.WAYFINDER_RESET.OnAccept(nil, "pois")
	eq(count(ns.db.pois), 0, "records erased")
	SlashCmdList.WAYFINDER("")
	eq(mock.openedSettings, 42, "options opened")
end)

test("removing an icon from the map", function()
	setPlayer(1429, 0.42, 0.65)
	setUnit("npc", { name = "Remy", title = "Banker", npcID = 4321, guid = "Creature-0-1-0-1-4321-0001" })
	mock.Fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", Enum.PlayerInteractionType.Banker)
	local rec = findRecord(function(r) return r.id == 4321 end)
	ok(rec, "recorded")
	ns:RemoveLocation(rec)
	ok(not findRecord(function(r) return r.id == 4321 end), "removed")
end)

---------------------------------------------------------------------------
-- Navigation: waypoints, the arrow, "show my location"
---------------------------------------------------------------------------
local Nav = ns.Navigation

-- Puts the waypoint at an offset in yards (north, west) from the player.
local function WaypointFromPlayer(north, west)
	local cont, wx, wy = ns.GetPlayerWorld()
	Nav:SetWaypoint(cont, wx + north, wy + west, "Test spot")
end

test("middle-clicking the world map sets a waypoint", function()
	Nav:ClearWaypoint()
	WorldMapFrame.mapID = 1429
	mock.mapCursorX, mock.mapCursorY = 0.5, 0.7
	local container = WorldMapFrame.ScrollContainer
	container.scripts.OnMouseUp(container, "MiddleButton")
	local wp = Nav:GetWaypoint()
	ok(wp, "waypoint set")
	local cont, wx, wy = ns.MapToWorld(1429, 0.5, 0.7)
	eq(wp.c, cont, "continent")
	near(wp.x, wx, 1e-6, "north")
	near(wp.y, wy, 1e-6, "west")
	eq(wp.n, "Elwynn Forest 50.0, 70.0", "named after the place")
	eq(ns.db.waypoints[ns:GetCharacterKey()], wp, "saved for this character")
	ok(WayfinderArrow.shown, "arrow shown")
	-- other mouse buttons don't
	Nav:ClearWaypoint()
	container.scripts.OnMouseUp(container, "LeftButton")
	eq(Nav:GetWaypoint(), nil, "left click places nothing")
	ok(not WayfinderArrow.shown, "arrow hidden without a waypoint")
end)

test("the arrow points at the waypoint relative to where you face", function()
	setPlayer(1429, 0.42, 0.65)
	mock.facing = 0 -- facing north
	WaypointFromPlayer(100, 0) -- 100 yards north
	mock.Advance(0.1)
	local arrow = WayfinderArrow
	near(arrow.head.rotation, 0, 1e-9, "straight ahead")
	eq(arrow.distance.text, "100 yd", "distance")
	WaypointFromPlayer(0, 100) -- due west: a quarter turn left
	mock.Advance(0.1)
	near(arrow.head.rotation, math.pi / 2, 1e-9, "points left")
	mock.facing = math.pi / 2 -- now facing west
	mock.Advance(0.1)
	near(arrow.head.rotation, 0, 1e-9, "ahead once you turn to face it")
	eq(arrow.head.vertex[2], 0.82, "gold while far")
	WaypointFromPlayer(30, 0)
	mock.Advance(0.1)
	eq(arrow.head.vertex[2], 0.92, "green when close")
	mock.printed = ""
	WaypointFromPlayer(5, 0)
	mock.Advance(0.1)
	eq(Nav:GetWaypoint(), nil, "cleared on arrival")
	ok(mock.printed:find("Arrived"), "arrival announced")
	ok(not arrow.shown, "arrow hidden")
	mock.facing = nil
end)

test("a waypoint on another continent", function()
	local cont, wx, wy = ns.MapToWorld(1414, 0.5, 0.5)
	Nav:SetWaypoint(cont, wx, wy, "Far shore")
	mock.Advance(0.1)
	ok(not WayfinderArrow.head.shown, "no direction")
	eq(WayfinderArrow.distance.text, "Far away", "says so")
	Nav:ClearWaypoint()
end)

test("waypoint pin on the world map; middle-click icons to set or remove", function()
	setPlayer(1429, 0.42, 0.65)
	WorldMapFrame.mapID = 1429
	local cont, wx, wy = ns.GetPlayerWorld()
	ns.Database:RecordNPC({ npcID = 9001, name = "Thomas", title = "Banker", cats = { bank = true },
		cont = cont, wx = wx - 150, wy = wy + 40, mapID = 1429, accuracy = 4, source = "talk" })
	WaypointFromPlayer(200, 50)
	WorldMapFrame:RefreshProviders()
	local waypointPin, poiPin
	for _, pin in ipairs(WorldMapFrame.pins) do
		if pin.rec.waypoint then waypointPin = pin elseif pin.rec.n and pin.rec.kind == "npc" then poiPin = pin end
	end
	ok(waypointPin, "waypoint pin on the map")
	eq(waypointPin.catID, "waypoint", "waypoint icon")
	eq(waypointPin.frameLevelType, "PIN_FRAME_LEVEL_WAYPOINT_LOCATION", "drawn above other icons")
	waypointPin:OnMouseClickAction("MiddleButton")
	eq(Nav:GetWaypoint(), nil, "middle-click removes it")
	ok(poiPin, "a recorded NPC on the map")
	poiPin:OnMouseClickAction("MiddleButton")
	local wp = Nav:GetWaypoint()
	ok(wp, "middle-click on an icon sets a waypoint")
	eq(wp.n, poiPin.rec.n, "named after the NPC")
	near(wp.x, poiPin.rec.x, 1e-9, "at the NPC")
	Nav:ClearWaypoint()
end)

test("show my location: switches to your map, then slides to you", function()
	local button = WayfinderLocateButton
	eq(button.points.LEFT[1], WorldMapFrame.WorldMapTrackingPinButton, "beside Blizzard's map pin button")
	setPlayer(1429, 0.42, 0.65)
	WorldMapFrame.mapID = 1453
	button.scripts.OnClick(button)
	eq(WorldMapFrame.mapID, 1429, "switched to your zone")
	WorldMapFrame.pannedTo = nil
	mock.atMinZoom = true
	button.scripts.OnClick(button)
	eq(WorldMapFrame.pannedTo, nil, "nothing to slide when fully zoomed out")
	mock.atMinZoom = false
	button.scripts.OnClick(button)
	near(WorldMapFrame.pannedTo[1], 0.42, 1e-9, "slid to you (x)")
	near(WorldMapFrame.pannedTo[2], 0.65, 1e-9, "slid to you (y)")
	mock.atMinZoom = nil
end)

test("detail view: show my location and middle-click waypoints", function()
	WorldMapFrame.mapID = 1429
	local container = WorldMapFrame.ScrollContainer
	mock.time = mock.time + 1
	container.scripts.OnMouseWheel(container, 1)
	ok(ns.DetailView:IsActive(), "detail view open")
	setPlayer(1429, 0.55, 0.75)
	WayfinderLocateButton.scripts.OnClick(WayfinderLocateButton)
	local _, px, py = ns.DetailView:GetCenter()
	local _, wx, wy = ns.GetPlayerWorld()
	local ex, ey = ns.WorldToPlane(wx, wy)
	near(px, ex, 1e-6, "centred on you (x)")
	near(py, ey, 1e-6, "centred on you (y)")
	ok(ns.DetailView:IsActive(), "still in the detail view")
	mock.Advance(1)
	local view = WayfinderDetailView
	Nav:ClearWaypoint()
	mock.cursorX, mock.cursorY = 501, 334 -- the middle of the view, where you are
	ns:SetSetting("clearOnArrival", false) -- or standing on it counts as arriving
	view.scripts.OnMouseUp(view, "MiddleButton")
	local wp = Nav:GetWaypoint()
	ok(wp, "middle-click sets a waypoint")
	local wpx, wpy = ns.WorldToPlane(wp.x, wp.y)
	near(wpx, ex, 1e-6, "under the cursor (x)")
	near(wpy, ey, 1e-6, "under the cursor (y)")
	mock.cursorX, mock.cursorY = nil, nil
	ns:SetSetting("clearOnArrival", true)
	ns.DetailView:Exit()
	Nav:ClearWaypoint()
end)

test("waypoint slash commands", function()
	setPlayer(1429, 0.42, 0.65)
	SlashCmdList.WAYFINDER("way 30.5 40 Goldshire")
	local wp = Nav:GetWaypoint()
	ok(wp, "set")
	eq(wp.n, "Goldshire", "label")
	local _, wx, wy = ns.MapToWorld(1429, 0.305, 0.40)
	near(wp.x, wx, 1e-6, "position")
	SlashCmdList.WAYFINDER("way 50,60")
	eq(Nav:GetWaypoint().n, "Elwynn Forest 50.0, 60.0", "comma separated, default label")
	mock.printed = ""
	SlashCmdList.WAYFINDER("way somewhere")
	ok(mock.printed:find("Usage"), "usage on bad input")
	SlashCmdList.WAYFINDER("clear")
	eq(Nav:GetWaypoint(), nil, "cleared")
	SlashCmdList.WAYFINDER("arrow")
	eq(ns:GetSetting("showArrow"), false, "arrow off")
	SlashCmdList.WAYFINDER("arrow")
	eq(ns:GetSetting("showArrow"), true, "arrow on")
end)

---------------------------------------------------------------------------
local passed, failed = 0, 0
for _, t in ipairs(tests) do
	local success, err = pcall(t.fn)
	if success then
		passed = passed + 1
		io.write("  ok    ", t.name, "\n")
	else
		failed = failed + 1
		io.write("  FAIL  ", t.name, "\n        ", tostring(err), "\n")
	end
end
io.write(("\n%d passed, %d failed\n"):format(passed, failed))
return failed
