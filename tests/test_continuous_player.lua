-- Exercise the real controller with no native player renderer, a native unit
-- pin, and host-map positions that disagree with the player's actual floor.
local ns, map, sc = Wayfinder, WorldMapFrame, WorldMapFrame.ScrollContainer
local C, S = ns.ContinuousMap, ns.ContinuousEngine.MapStitch
local controller = ns.ContinuousEngine:GetModule("worldmap")
local passed, failed = 0, 0
local getPosition, getFacing = C_Map.GetPlayerMapPosition, GetPlayerFacing
local function check(value, message) assert(value, message) end
local function near(a, b) assert(math.abs(a - b) < .00001, tostring(a) .. " != " .. tostring(b)) end
local function Arrow()
	for _, frame in ipairs(S.root.children) do
		if frame.texture and (frame.texture:GetTexture() == ns.Categories:GetMediaPath("PlayerArrow")
			or frame.texture:GetAtlas() == ns.Categories.playerArrowAtlas and ns.Categories.playerArrowAtlas) then return frame end
	end
	error("continuous player arrow was never created")
end
local function Show(id, x, y, zoom)
	map:Show()
	local u, v = C.API.WorldFromMap(id, x, y)
	controller.ShowNow(u, v, zoom)
	mock.Advance(.2)
	return u, v
end
local function CheckPosition(id, x, y)
	local u, v = C.API.WorldFromMap(id, x, y)
	local w, h = S.Size()
	local anchor = Arrow().points.CENTER
	check(anchor and anchor[1] == S.root and anchor[2] == "TOPLEFT", "arrow stays on the stitched coordinate plane")
	near(anchor[3], u * w); near(anchor[4], -v * h)
end
local function test(name, fn)
	C_Map.GetPlayerMapPosition, GetPlayerFacing = getPosition, getFacing
	mock.playerMap, mock.playerX, mock.playerY, mock.facing, mock.inCombat = 1421, .4, .5, .7, false
	controller.db.playerArrow = true
	local ok, err = pcall(fn)
	C_Map.GetPlayerMapPosition, GetPlayerFacing = getPosition, getFacing
	mock.inCombat = false
	if ok then passed = passed + 1; io.write("  ok    ", name, "\n")
	else failed = failed + 1; io.write("  FAIL  ", name, "\n        ", tostring(err), "\n") end
end

test("Silverpine player arrow exists on a fresh load with readable native coordinates", function()
	map:SetMapID(1421)
	Show(1421, .4, .5, 50)
	check(Arrow():IsVisible(), "a valid host position cannot disable the player arrow")
	CheckPosition(1421, .4, .5)
	near(Arrow().texture:GetRotation(), .7)
	check(Arrow():GetFrameLevel() > S.artTop, "player draws above all map artwork")
end)

test("player arrow survives every terrain zoom and updates its position and facing", function()
	local u, v = C.API.WorldFromMap(1421, .4, .5)
	for _, zoom in ipairs({1, 50, 100, C:GetMaxZoom(u, v)}) do
		Show(1421, .4, .5, zoom)
		check(Arrow():IsVisible(), "player remains visible at zoom " .. zoom)
		CheckPosition(1421, .4, .5)
	end
	mock.playerX, mock.playerY, mock.facing = .401, .502, 1.9
	mock.Advance(.2)
	CheckPosition(1421, .401, .502)
	near(Arrow().texture:GetRotation(), 1.9)
	local rootScale, scrollScale = S.root.GetEffectiveScale, sc.GetEffectiveScale
	S.root.GetEffectiveScale, sc.GetEffectiveScale = function() return 3 end, function() return 1.5 end
	mock.Advance(.2)
	local width = Arrow():GetWidth()
	S.root.GetEffectiveScale, sc.GetEffectiveScale = rootScale, scrollScale
	near(width * 3 / 1.5, 24)
end)

local unitPin = CreateFrame("Frame", nil, map:GetCanvas())
unitPin.pinTemplate, unitPin.template = "GroupMembersPinTemplate", "GroupMembersPinTemplate"
unitPin:SetSize(24, 24)
unitPin.sizes = {player = 24, party = 18}
unitPin.dataProvider = {GetUnitPinSizesTable = function() return {player = 24, party = 18} end}
function unitPin:SetPinSize(unit, size)
	check(not (self.protected and InCombatLockdown()), "protected unit pin changed during combat")
	self.sizes[unit] = size
end
function unitPin:SynchronizePinSizes() self:SetPinSize("player", 24 / sc:GetCanvasScale()) end
function unitPin:IsProtected() return self.protected == true end
function unitPin:GetPosition() return .4, .5 end
function unitPin:GetMap() return map end
local unitTexture = unitPin:CreateTexture(nil, "OVERLAY")
unitTexture:SetAllPoints(); unitTexture:SetTexture("test-unit-markers")
local unitChild = CreateFrame("Frame", nil, unitPin)
unitChild:SetSize(18, 18)
unitChild.GetMap, unitChild.GetPosition = unitPin.GetMap, unitPin.GetPosition
local partyTexture = unitChild:CreateTexture(nil, "OVERLAY")
partyTexture:SetAllPoints(); partyTexture:SetTexture("test-party-marker")
table.insert(map.pins, unitPin)

test("only the native player blip is suppressed and pooled pin resizing cannot restore a duplicate", function()
	map:SetMapID(1421)
	Show(1421, .4, .5, 500)
	check(Arrow():IsVisible() and unitPin.sizes.player < 1, "custom arrow replaces native self blip")
	near(unitPin.sizes.party, 18)
	unitPin:SynchronizePinSizes()
	check(unitPin.sizes.player < 1, "native pin reuse does not create a duplicate")
	ns.AddonPins:Refresh(); mock.Advance(.2)
	near(unitPin:GetAlpha(), 1)
	check(unitPin:IsVisible(), "party frame remains visible and unmasked")
	local copied = false
	ns.AddonPins:Query(0, -50000, 50000, -50000, 50000, function(entry)
		if entry.frame == unitPin or entry.source == unitPin or entry.frame == unitChild then copied = true end
	end)
	check(not copied, "native unit markers are never treated as fixed addon objects")
end)

test("Undercity layer switching keeps the player at its true position immediately", function()
	mock.playerMap, mock.playerX, mock.playerY = 1458, .65, .5
	C_Map.GetPlayerMapPosition = function(id, unit)
		if id == 1420 then return CreateVector2D(.1, .1) end -- readable but wrong floor/position
		return getPosition(id, unit)
	end
	map:SetMapID(1458)
	Show(1458, .65, .5, 500)
	check(Arrow():IsVisible(), "underground player visible")
	C.layerButton.scripts.OnClick(C.layerButton)
	check(Arrow():IsVisible(), "switching to surface cannot leave a gap until the next tick")
	CheckPosition(1458, .65, .5)
	check(unitPin.sizes.player < 1, "one arrow on the surface")
	C.layerButton.scripts.OnClick(C.layerButton)
	check(Arrow():IsVisible(), "switching back keeps the arrow")
	CheckPosition(1458, .65, .5)
end)

test("unavailable best-map coordinates fall back to valid host coordinates", function()
	map:SetMapID(1420)
	Show(1420, .3, .3, 100)
	C_Map.GetPlayerMapPosition = function(id)
		if id == map:GetMapID() then return CreateVector2D(.3, .3) end
	end
	mock.Advance(.2)
	check(Arrow():IsVisible(), "readable host coordinates retain a fallback")
	CheckPosition(map:GetMapID(), .3, .3)
end)

test("invalid, restricted and throwing positions hide the replacement and restore the native player", function()
	map:SetMapID(1421)
	Show(1421, .4, .5, 500)
	local bad = {
		function() return nil end,
		function() return CreateVector2D(0, 0) end,
		function() return CreateVector2D(0/0, .5) end,
		function() return CreateVector2D(math.huge, .5) end,
		function() return CreateVector2D(mock.SECRET, .5) end,
		function() return mock.SECRET end,
		function() error("position unavailable") end,
		function() return {GetXY = function() error("position released") end} end,
	}
	for _, position in ipairs(bad) do
		C_Map.GetPlayerMapPosition = position
		controller.RefreshPlayer()
		check(not Arrow():IsShown(), "invalid position must not leave a stale arrow")
		check(unitPin.sizes.player >= 1, "native self blip is restored when replacement is unavailable")
	end
	C_Map.GetPlayerMapPosition = getPosition
	GetPlayerFacing = function() return mock.SECRET end
	mock.Advance(.2)
	check(Arrow():IsVisible() and unitPin.sizes.player < 1, "readable coordinates recover despite unavailable facing")
end)

test("leaving stitched maps restores native unit sizes, including after protected combat", function()
	map:SetMapID(1421)
	Show(1421, .4, .5, 500)
	unitPin.protected, mock.inCombat = true, true
	mock.Advance(.2)
	map:SetMapID(9999)
	check(not S.root:IsShown(), "dungeon hides custom arrow with its canvas")
	mock.inCombat = false
	mock.Fire("PLAYER_REGEN_ENABLED")
	check(unitPin.sizes.player >= 1, "deferred native restoration completes even with the map ticker stopped")
	near(unitPin.sizes.party, 18)
	unitPin:SynchronizePinSizes()
	check(unitPin.sizes.player >= 1, "inactive controller must not rehide native player")
	unitPin.protected = false
	map:SetMapID(1421)
	Show(1421, .4, .5, 500)
	check(Arrow():IsVisible() and unitPin.sizes.player < 1, "returning outdoors restores one custom arrow")
end)

test("opening the map refreshes the player immediately and closing leaves no player polling", function()
	map:Hide()
	for _, dp in ipairs(map.providers) do if dp.OnHide then dp:OnHide() end end
	if map.scripts.OnHide then map.scripts.OnHide(map) end
	local reads, updates = 0, 0
	C_Map.GetPlayerMapPosition = function(...) reads = reads + 1; return getPosition(...) end
	local setPlayer = S.SetPlayer
	S.SetPlayer = function(...) updates = updates + 1; return setPlayer(...) end
	mock.Advance(.5)
	S.SetPlayer = setPlayer
	check(updates == 0, "closed continuous map does not poll or update its player arrow")
	reads = 0
	map:Show()
	for _, dp in ipairs(map.providers) do if dp.OnShow then dp:OnShow() end end
	check(reads > 0 and Arrow():IsVisible(), "first visible frame has a current player arrow")
	CheckPosition(1421, .4, .5)
end)

test("an idle player marker retains its artwork and geometry at the existing ten-hertz cadence", function()
	map:SetMapID(1421)
	Show(1421, .4, .5, 500)
	mock.Advance(.8)
	local arrow, writes, updates = Arrow(), 0, 0
	local point, size, rotation, setPlayer = arrow.SetPoint, arrow.SetSize, arrow.texture.SetRotation, S.SetPlayer
	arrow.SetPoint = function(self, ...) writes = writes + 1; return point(self, ...) end
	arrow.SetSize = function(self, ...) writes = writes + 1; return size(self, ...) end
	arrow.texture.SetRotation = function(self, ...) writes = writes + 1; return rotation(self, ...) end
	S.SetPlayer = function(...) updates = updates + 1; return setPlayer(...) end
	mock.Advance(2, 1/60)
	arrow.SetPoint, arrow.SetSize, arrow.texture.SetRotation, S.SetPlayer = point, size, rotation, setPlayer
	check(writes == 0, "stationary player does not rewrite anchors, size or rotation")
	check(updates >= 15 and updates <= 22, "player updates reuse the existing 0.1-second cadence")
end)

unitPin:Hide()
io.write("\n", passed, " continuous player checks passed, ", failed, " failed\n")
return failed
