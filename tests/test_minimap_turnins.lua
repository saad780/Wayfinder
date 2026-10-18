local ns, Mini = Wayfinder, Wayfinder.MinimapTurnIns
local passed, failed = 0, 0
local oldMinimap, oldLoader = Minimap, QuestieLoader
local originalSetting = ns:GetSetting("nativeMinimapTurnIns")
local check = assert
local id = 765432
Minimap = CreateFrame("Frame", "Minimap", UIParent)
local native = CreateFrame("Frame", nil, Minimap)
native:SetPoint("CENTER", 25, 30)
local module = {}
function module.CreateIconFrame(frameID)
	local frame = CreateFrame("Button", "QuestieFrame" .. frameID, Minimap)
	frame.originalHidden = false
	function frame:ShouldBeHidden() return self.originalHidden end
	function frame:FakeHide()
		self.hidden = true
		self:Hide()
		self.originalShow = self.originalShow or self.Show
		self.Show = function(owner) owner.shouldBeShowing = true end
	end
	function frame:FakeShow()
		self.hidden = false
		if self.originalShow then self.Show = self.originalShow end
		self:Show()
	end
	return frame
end
local mapModule = { questIdFrames = {} }
QuestieLoader = { ImportModule = function(_, name)
	if name == "QuestieFrame" then return module end
	if name == "QuestieMap" then return mapModule end
end }
local function Pin(frameID, kind, mini)
	local frame = module.CreateIconFrame(frameID)
	frame.data, frame.miniMapIcon, frame.UiMapID = { Type = kind, Id = id }, mini, 1429
	return frame
end
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then passed = passed + 1; io.write("  ok    ", name, "\n")
	else failed = failed + 1; io.write("  FAIL  ", name, "\n        ", tostring(err), "\n") end
end
mock.questLog[id], mock.readyQuests[id] = true, true
mock.questPOIs[1429] = { { questID = id, x = 0.5, y = 0.5 } }
local existing = Pin(991, "complete", true)
local olderPool = Pin(990, "complete", true)
function mapModule:DrawWorldIcon(data)
	olderPool.data = data
	self.questIdFrames[data.Id] = { olderPool:GetName(), existing:GetName() }
	return olderPool
end
mapModule.questIdFrames[id] = { existing:GetName() }
Mini:Install()
mock.Advance(0.2) -- pre-existing pools are discovered within the frame budget

test("minimap handoff hides fixed turn-ins while native moving and world-map markers remain intact", function()
	Mini:Refresh()
	check(existing.hidden and not existing:IsShown(), "existing minimap duplicate hidden")
	local world = Pin(992, "complete", false)
	check(not world:ShouldBeHidden(), "world-map turn-in unchanged")
	check(world:IsShown() and native:IsShown(), "native and world-map markers remain visible")
	-- The client may move the live marker arbitrarily; Wayfinder never resets
	-- it to the database spawn or projects a second icon on top of it.
	native:SetPoint("CENTER", 40, 45)
	Mini:Refresh()
	check(native.points.CENTER[1] == 40 and native.points.CENTER[2] == 45, "native live position preserved")
end)
test("new and recycled Questie frames retain pickups, objectives and other filters", function()
	local frame = Pin(993, "complete", true)
	assert(frame:ShouldBeHidden(), "new turn-in suppressed through owner's visibility check")
	frame:FakeHide()
	frame.data.Type, frame.miniMapIcon = "available", true
	Mini:Refresh()
	assert(not frame.hidden and frame:IsShown(), "recycled pickup restored")
	assert(not frame:ShouldBeHidden(), "pickup filter unchanged")
	frame.data.Type = "monster"
	assert(not frame:ShouldBeHidden(), "quest objective unchanged")
	frame.originalHidden = true
	assert(frame:ShouldBeHidden(), "owner's original filters still win")
	frame.data.Type, frame.miniMapIcon = "complete", false
	frame.originalHidden = false
	assert(not frame:ShouldBeHidden(), "a recycled world-map frame is never suppressed")
end)
test("pre-existing unused pool frames are suppressed when Questie draws them later", function()
	local result = mapModule:DrawWorldIcon({ Type = "complete", Id = id })
	assert(result == olderPool, "owner's returned frame is unchanged")
	assert(result.hidden and not result:IsShown(), "older pooled duplicate is caught after drawing")
end)
test("missing native expected locations and unreadable APIs preserve addon fallbacks", function()
	local frame = Pin(994, "complete", true)
	mock.questPOIs[1429] = {}
	assert(not frame:ShouldBeHidden(), "no native location keeps fixed addon fallback")
	local old = C_QuestLog.GetQuestsOnMap
	C_QuestLog.GetQuestsOnMap = function() error("not available") end
	assert(not frame:ShouldBeHidden(), "failed native API leaves marker alone")
	C_QuestLog.GetQuestsOnMap = old
	mock.questPOIs[1429] = { { questID = id, x = 0.5, y = 0.5 } }
	frame.data.Id = mock.SECRET
	assert(not frame:ShouldBeHidden(), "unreadable quest identity leaves marker alone")
end)
test("disabling minimap handoff restores only Wayfinder-hidden pins and respects Questie filters", function()
	local allowed, filtered = Pin(995, "complete", true), Pin(996, "complete", true)
	Mini:Refresh()
	assert(allowed.hidden and filtered.hidden)
	filtered.originalHidden = true
	ns:SetSetting("nativeMinimapTurnIns", false)
	Mini:Refresh()
	assert(allowed:IsShown() and not allowed.hidden, "owned marker restored")
	assert(filtered.hidden and not filtered:IsShown(), "original owner still hides filtered quest")
	assert(native:IsShown(), "native tracking unaffected when toggling")
	ns:SetSetting("nativeMinimapTurnIns", true)
end)
test("movement and native fallback changes never reposition the live minimap marker", function()
	local original = { native:GetPoint() }
	mock.questPOIs[1429] = { { questID = id, x = 0.52, y = 0.54 } }
	Mini:Refresh()
	assert(existing.hidden, "native supplied expected position remains authoritative")
	local point = { native:GetPoint() }
	for i, v in ipairs(original) do assert(v == point[i], "live NPC position unchanged") end
	existing:Show()
	assert(not existing:IsShown(), "owner's pool hide resists HBD movement showing the duplicate")
end)
test("a growing Questie frame list is observed once per new icon rather than rescanned per draw",function()
	local frames,map={}, {questIdFrames={}}
	map.questIdFrames[887799]=frames
	local previous,calls=Mini.ObserveFrame,0
	Mini.ObserveFrame=function(self,frame) calls=calls+1; return previous(self,frame) end
	for i=1,500 do
		local frame={miniMapIcon=false,data={Type="monster"},ShouldBeHidden=function() return false end}
		_G["WayfinderGrowingQueue"..i]=frame
		frames[#frames+1]="WayfinderGrowingQueue"..i
		Mini:ObserveQuestFrames(map,887799)
	end
	Mini.ObserveFrame=previous
	assert(calls==500,"500 appended frames require 500 observations, not 125,250")
	for i=1,500 do _G["WayfinderGrowingQueue"..i]=nil end
end)
ns:SetSetting("nativeMinimapTurnIns", originalSetting)
Minimap, QuestieLoader = oldMinimap, oldLoader
mock.questLog[id], mock.readyQuests[id], mock.questPOIs[1429] = nil, nil, nil
io.write("\n", passed, " live minimap checks passed, ", failed, " failed\n")
return failed
