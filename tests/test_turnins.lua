local ns, Nav = Wayfinder, Wayfinder.Navigation
local passed, failed = 0, 0
local function check(value, message) assert(value, message) end
local function near(a, b) assert(math.abs(a - b) < 0.00001) end
local function pins(id)
	local found = {}
	for _, frame in ipairs(mock.frames) do
		if frame.quest and frame.quest.turnIn and frame.quest.questID == id and frame:IsVisible() then found[#found + 1] = frame end
	end
	return found
end
local function setup(id)
	ns.DetailView:Exit(true)
	WorldMapFrame:Show(); WorldMapFrame:SetMapID(1429)
	mock.playerMap, mock.playerX, mock.playerY = 1429, 0.42, 0.65
	mock.questLines = {}
	mock.questLog[id], mock.readyQuests[id], mock.questTitles[id] = true, true, "Return to the quest giver"
	mock.questPOIs[1429] = { { questID = id, x = 0.45, y = 0.65, isMapIndicatorQuest = false } }
	ns:SetSetting("showLiveQuests", true); ns:SetCategoryEnabled("quest", true)
	check(ns.DetailView:EnterFromMap(), "detail view opens")
	mock.Advance(0.8)
end
local function test(name, fn)
	local ok, err = pcall(fn)
	ns.DetailView:Exit(true); Nav:ClearWaypoint()
	mock.questPOIs, mock.readyQuests, mock.questTitles = {}, {}, {}
	ns:SetSetting("showLiveQuests", true); ns:SetCategoryEnabled("quest", true)
	mock.mouseOver = nil
	if ok then passed = passed + 1; io.write("  ok    ", name, "\n")
	else failed = failed + 1; io.write("  FAIL  ", name, "\n        ", tostring(err), "\n") end
end

test("completed quest POIs retain question marks, tooltip and navigation in terrain detail", function()
	local id = 987701
	setup(id)
	local found = pins(id)
	check(#found == 1, "turn-in is drawn without relying on a readable original map button")
	local pin = found[1]
	check(pin.icon.texture == "Interface\\GossipFrame\\ActiveQuestIcon" or pin.icon.atlas == ns.Categories.questTurnInAtlas,
		"turn-in uses Blizzard question-mark artwork")
	for _, frame in ipairs(mock.frames) do
		if frame.rec and not frame.rec.waypoint and frame:IsVisible() and frame:GetParent() == pin:GetParent() then
			check(pin:GetFrameLevel() > frame:GetFrameLevel(), "turn-in stays above overlapping service markers")
		end
	end
	pin.scripts.OnEnter(pin)
	check(GameTooltip.lines[1] == mock.questTitles[id], "quest name retained")
	check(GameTooltip.lines[2] == "Ready to turn in", "turn-in distinguished from a pickup")
	mock.mouseOver = pin
	pin.scripts.OnMouseUp(pin, "MiddleButton")
	local _, wx, wy = ns.MapToWorld(1429, 0.45, 0.65)
	check(Nav:GetWaypoint(), "middle-click navigates to the turn-in")
	near(Nav:GetWaypoint().x, wx); near(Nav:GetWaypoint().y, wy)
end)

test("completion and turn-in events refresh markers without stale or completed-history quests", function()
	local id = 987702
	setup(id)
	mock.readyQuests[id] = false
	mock.Fire("QUEST_LOG_UPDATE"); mock.Advance(0.3)
	check(#pins(id) == 0, "incomplete quest has no golden question mark")
	mock.readyQuests[id] = true
	mock.Fire("QUEST_POI_UPDATE"); mock.Advance(0.3)
	check(#pins(id) == 1, "finishing objectives immediately shows the turn-in")
	ns:SetSetting("showLiveQuests", false); mock.Advance(0.3)
	check(#pins(id) == 0, "live-marker setting respected")
	ns:SetSetting("showLiveQuests", true); mock.Advance(0.3)
	ns:SetCategoryEnabled("quest", false); mock.Advance(0.3)
	check(#pins(id) == 0, "quest category setting respected")
	ns:SetCategoryEnabled("quest", true); mock.Advance(0.3)
	mock.Fire("QUEST_TURNED_IN", id); mock.Advance(0.3)
	check(#pins(id) == 0, "handing in hides the marker even while old POI data remains cached")
	mock.Fire("QUEST_ACCEPTED", id); mock.Advance(0.3)
	check(#pins(id) == 1, "a repeatable quest can become ready again")
	mock.questLog[id] = false; mock.completedQuests[id] = true
	mock.Fire("QUEST_LOG_UPDATE"); mock.Advance(0.3)
	check(#pins(id) == 0, "historically completed quest is not a pending turn-in")
end)

test("mirrored turn-ins keep their owner tooltip and suppress duplicate fallback markers", function()
	local id = 987703
	WorldMapFrame:SetMapID(1429)
	local source = Mixin(CreateFrame("Frame", nil, WorldMapFrame:GetCanvas()), MapCanvasPinMixin)
	source.GetMap = function() return WorldMapFrame end
	source:SetPosition(0.45, 0.65)
	source.icon = CreateFrame("Button", nil, source)
	source.icon:SetSize(18, 18)
	source.icon.data = { Type = "complete", Id = id, Name = "Questie turn-in" }
	local texture = source.icon:CreateTexture(nil, "ARTWORK")
	texture:SetAllPoints(); texture:SetTexture("QuestieGoldenQuestionMark")
	source.icon:SetScript("OnEnter", function() GameTooltip:SetText("Original quest completion details"); GameTooltip:Show() end)
	setup(id)
	local mirror
	for _, frame in ipairs(mock.frames) do
		if frame.external and frame.external.frame == source and frame:IsVisible() then mirror = frame end
	end
	check(mirror, "original quest-completion artwork is mirrored")
	check(mirror.external.turnIn, "Questie completion metadata recognized")
	check(#pins(id) == 0, "native fallback does not duplicate a working mirror")
	mirror.scripts.OnEnter(mirror)
	check(GameTooltip.lines[1] == "Original quest completion details", "owner's complete tooltip retained")
	check(mirror:GetFrameLevel() > mirror:GetParent():GetFrameLevel() + 1, "mirrored completion stays above ordinary icons")
	source:Hide(); mock.Advance(0.7)
	check(#pins(id) == 1, "fallback covers a released original map button")
end)

test("turn-in reads reject malformed and restricted state and tolerate missing quest APIs", function()
	local id = 987704
	mock.questLog[id], mock.readyQuests[id] = true, true
	mock.questPOIs[1429] = {
		{ questID = id, x = 0.45, y = 0.65 }, { questID = id, x = 0.45, y = 0.65 },
		{ questID = { secret = true }, x = 0.45, y = 0.65 },
		{ questID = id, x = math.huge, y = 0.65 }, { questID = id, x = -1, y = 0.65 },
	}
	check(#ns.QuestTurnIns:GetForMap(1429) == 1, "duplicates and invalid coordinates rejected")
	mock.readyQuests[id] = { secret = true }
	check(#ns.QuestTurnIns:GetForMap(1429) == 0, "restricted completion state is not assumed ready")
	local original = C_QuestLog.GetQuestsOnMap
	C_QuestLog.GetQuestsOnMap = function() error("unavailable quest POIs") end
	local ok, result = pcall(ns.QuestTurnIns.GetForMap, ns.QuestTurnIns, 1429)
	C_QuestLog.GetQuestsOnMap = original
	check(ok and #result == 0, "an API failure does not break terrain rendering")
end)

test("merchant and other service icons use Blizzard artwork in both map views", function()
	ns.Categories:ResolveIcons()
	check(ns.CategoryByID.vendor.icon.texture == "Interface\\GossipFrame\\VendorGossipIcon", "merchant uses Blizzard's vendor icon")
	for _, id in ipairs({ "vendor", "repair", "inn", "bank", "auction", "mailbox", "stable", "battlemaster",
		"trainer_class", "trainer_prof", "weaponmaster", "poison", "reagent", "ammo", "food", "spirit", "quest" }) do
		local icon = ns.CategoryByID[id].icon
		check(icon.atlas or type(icon.texture) == "number"
			or (type(icon.texture) == "string" and not icon.texture:find("AddOns\\Wayfinder", 1, true)), id .. " uses Blizzard artwork")
		local texture = UIParent:CreateTexture()
		ns.Categories:ApplyIcon(texture, id)
		check(texture.texture == icon.texture and texture.atlas == icon.atlas, "shared icon resolver matches the category")
	end
	WorldMapFrame:RefreshProviders()
	for _, pin in ipairs(WorldMapFrame.pins) do
		if pin.catID == "vendor" then check(pin.Icon.texture == ns.CategoryByID.vendor.icon.texture, "world map uses the resolved vendor icon") end
	end
end)

io.write(("\n%d turn-in and service-icon checks passed, %d failed\n"):format(passed, failed))
return failed
