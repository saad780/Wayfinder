-- One Wayfinder marker per nearby service location on the live minimap.
local _, ns = ...
local Mini = ns:NewModule("MinimapServices")
local pins, tracking = {}, {}
local function Number(v) return ns.Readable(v) and type(v) == "number" and v == v and math.abs(v) < math.huge end
local function Selected(cats)
	for _,cat in ipairs(cats) do if ns:IsCategoryEnabled(cat) then return true end end
	return false
end
function Mini:IsActive() return self.active == true end

function Mini:GetTrackingCategories(index)
	local filter = C_Minimap.GetTrackingFilter(index)
	if not filter or not filter.filterID or not Enum.MinimapTrackingFilter then return {} end
	self.filterCategories = self.filterCategories or {}
	if self.filterCategories[filter.filterID] then return self.filterCategories[filter.filterID], filter.filterID end
	local result = {}
	for _, cat in ipairs(ns.CategoryList) do
		if cat.filter and Enum.MinimapTrackingFilter[cat.filter] == filter.filterID then result[#result+1] = cat.id end
	end
	for key,cat in pairs({Vendor="vendor",Vender="vendor",Merchant="vendor",WeaponMaster="weaponmaster",SpiritHealer="spirit"}) do
		if Enum.MinimapTrackingFilter[key] == filter.filterID then result[#result+1] = cat end
	end
	if #result == 0 then
		local info = C_Minimap.GetTrackingInfo(index)
		local name = info and info.name
		if ns.Readable(name) and type(name)=="string" and (name:lower():find("vendor",1,true) or name:lower():find("merchant",1,true)) then result[1]="vendor" end
	end
	self.filterCategories[filter.filterID] = result
	return result, filter.filterID
end
function Mini:IsTrackingSelected(index)
	return Selected(self:GetTrackingCategories(index))
end
function Mini:SetTrackingSelected(index, enabled)
	local cats = self:GetTrackingCategories(index)
	self.settingSelection = true
	for _,cat in ipairs(cats) do ns:SetCategoryEnabled(cat,enabled) end
	self.settingSelection = nil
	self.trackingDirty = true
	self:RequestUpdate()
	if MiniMapTrackingButton and MiniMapTrackingButton.GenerateMenu then MiniMapTrackingButton:GenerateMenu() end
end
function Mini:InstallTrackingMenu()
	if not self.menuInstalled and Menu and Menu.ModifyMenu then
		self.menuInstalled = true
		Menu.ModifyMenu("MENU_MINIMAP_TRACKING",function(_,root)
			if not self.active then return end
			local function Visit(parent)
				for _,desc in parent:EnumerateElementDescriptions() do
					local data = desc:GetData()
					if type(data)=="table" and Number(data.index) and #self:GetTrackingCategories(data.index)>0 then
						desc:SetIsSelected(function(info)
							if self.active then return self:IsTrackingSelected(info.index) end
							local native = C_Minimap.GetTrackingInfo(info.index)
							return native and native.active
						end)
						desc:SetResponder(function(info)
							if self.active then self:SetTrackingSelected(info.index,not self:IsTrackingSelected(info.index))
							else local native=C_Minimap.GetTrackingInfo(info.index); C_Minimap.SetTracking(info.index,not (native and native.active)) end
							return MenuResponse.Refresh
						end)
					end
					Visit(desc)
				end
			end
			Visit(root)
		end)
	end
	if C_Minimap.SetTracking and self.trackingHook ~= C_Minimap.SetTracking then
		hooksecurefunc(C_Minimap,"SetTracking",function(index,enabled)
			if not self.syncing and self.active and #self:GetTrackingCategories(index)>0 then self:SetTrackingSelected(index,enabled) end
		end)
		self.trackingHook = C_Minimap.SetTracking
	end
	if C_Minimap.ClearAllTracking and self.clearHook ~= C_Minimap.ClearAllTracking then
		hooksecurefunc(C_Minimap,"ClearAllTracking",function()
			if not self.active then return end
			self.settingSelection = true
			for i=1,C_Minimap.GetNumTrackingTypes() do
				for _,cat in ipairs(self:GetTrackingCategories(i)) do ns:SetCategoryEnabled(cat,false) end
			end
			self.settingSelection = nil
			self.trackingDirty = true
			self:RequestUpdate()
		end)
		self.clearHook = C_Minimap.ClearAllTracking
	end
end
function Mini:SyncTracking()
	if self.syncing or not C_Minimap or not C_Minimap.SetTracking or not C_Minimap.GetNumTrackingTypes
		or not C_Minimap.GetTrackingFilter or not C_Minimap.GetTrackingInfo then return end
	local now = GetTime()
	if not self.trackingDirty and self.trackingActive == self.active and self.trackingAPI == C_Minimap.GetTrackingInfo
		and self.trackingFilterAPI == C_Minimap.GetTrackingFilter and now < (self.trackingCheckAt or 0) then return end
	self.syncing = true
	for i = 1, C_Minimap.GetNumTrackingTypes() do
		local cats, key = self:GetTrackingCategories(i)
		local info = C_Minimap.GetTrackingInfo(i)
		if #cats > 0 and info and type(info.active) == "boolean" then
			if self.active and not self.leaving then
				tracking[key] = Selected(cats)
				if info.active then pcall(C_Minimap.SetTracking, i, false) end
			elseif tracking[key] ~= nil then
				local selected = Selected(cats)
				if info.active ~= selected then pcall(C_Minimap.SetTracking, i, selected) end
				tracking[key] = nil
			end
		end
	end
	self.syncing = false
	self.trackingDirty, self.trackingActive = nil, self.active
	self.trackingAPI, self.trackingFilterAPI = C_Minimap.GetTrackingInfo, C_Minimap.GetTrackingFilter
	self.trackingCheckAt = now + 2 -- events/hooks handle edits immediately; fallback catches other owners
end
local function Acquire(index)
	local pin = pins[index]
	if not pin then
		pin = CreateFrame("Button", nil, Minimap)
		pin:SetSize(16, 16)
		pin:SetFrameLevel(Minimap:GetFrameLevel() + 12)
		pin:RegisterForClicks("LeftButtonUp", "MiddleButtonUp")
		pin.Icon = pin:CreateTexture(nil, "OVERLAY")
		pin.Icon:SetAllPoints()
		pin:SetScript("OnEnter", function(owner) ns.Tooltip:Show(owner, owner.rec, owner.catID) end)
		pin:SetScript("OnLeave", GameTooltip_Hide)
		pin:SetScript("OnClick", function(owner, button)
			if button == "MiddleButton" then ns.Navigation:ToggleWaypointAt(owner.rec, owner.catID)
			elseif button == "LeftButton" and IsShiftKeyDown() then ns:RemoveLocation(owner.rec) end
		end)
		pins[index] = pin
	end
	if pin:GetParent() ~= Minimap then pin:SetParent(Minimap) end
	return pin
end
function Mini:RequestUpdate()
	if self.pending then return end
	self.pending = true
	C_Timer.After(0, function()
		self.pending = nil
		if self.lastUpdate ~= GetTime() then self:Update() end
	end)
end
function Mini:Update()
	if self.updating then self:RequestUpdate(); return end
	self.updating = true
	self.lastUpdate = GetTime()
	local started, wasActive = ns.Background:Begin(), self.active
	self:Rebuild()
	self.updating = nil
	if wasActive ~= self.active then ns.MinimapTurnIns:RequestRefresh(true) end
	ns.Background:Finish("minimap refresh", started)
end
function Mini:Rebuild()
	self.active = false
	local function Inactive()
		for _,pin in ipairs(pins) do
			if pin.drawn then pin:Hide(); pin.drawn = nil end
		end
		self:SyncTracking()
	end
	if self.leaving or not Minimap or not ns:GetSetting("showMinimapServices") then Inactive(); return end
	local cont, wx, wy = ns.GetPlayerWorld()
	local radius = C_Minimap and C_Minimap.GetViewRadius and C_Minimap.GetViewRadius()
	if not cont or not Number(radius) or radius <= 0 then Inactive(); return end
	local halfW, halfH = Minimap:GetWidth()/2, Minimap:GetHeight()/2
	if halfW < 16 or halfH < 16 then Inactive(); return end
	self.active = true
	local rotate = GetCVarBool and GetCVarBool("rotateMinimap")
	if C_Minimap.IsRotateMinimapIgnored and C_Minimap.IsRotateMinimapIgnored() then rotate = false end
	local facing = rotate and GetPlayerFacing() or 0
	if not Number(facing) then facing = 0 end
	local cosine, sine = math.cos(facing), math.sin(facing)
	local square = GetMinimapShape and GetMinimapShape() == "SQUARE"
	local quests, maps = {}, {}
	local function AddQuest(mapID, info)
		local c, x, y = ns.MapToWorld(mapID, info.x, info.y)
		if c == cont then quests[#quests+1] = { x = x, y = y, questID = info.questID } end
	end
	local mapID = C_Map.GetBestMapForUnit("player")
	while mapID and not maps[mapID] do
		maps[mapID] = true
		for _, info in ipairs(ns.QuestTurnIns:GetForMap(mapID, true)) do AddQuest(mapID, info) end
		if C_QuestLine and C_QuestLine.GetAvailableQuestLines then
			local ok, lines = pcall(C_QuestLine.GetAvailableQuestLines, mapID)
			for _, info in ipairs(ok and type(lines) == "table" and lines or {}) do
				if ns.QuestAvailability:IsLiveQuestAvailable(info) and Number(info.x) and Number(info.y) then
					AddQuest(mapID, info)
				end
			end
		end
		local info = C_Map.GetMapInfo(mapID)
		mapID = info and info.mapType > Enum.UIMapType.Zone and info.parentMapID or nil
	end
	local nativeCount, known = #quests, {}
	ns.MinimapTurnIns:QueryQuestGivers(cont, wx-radius-25, wx+radius+25, wy-radius-25, wy+radius+25, function(info)
		quests[#quests+1] = info
		if info.questID and info.n then
			known[info.questID] = known[info.questID] or {}
			known[info.questID][#known[info.questID]+1] = info
		end
	end)
	-- Give native POIs the identity exposed by a matching addon frame. Its
	-- position alone must not hide a different NPC standing next to the giver.
	for i=1,nativeCount do
		local quest, nearest = quests[i], 25
		for _,giver in ipairs(known[quest.questID] or {}) do
			local distance = ns.Distance(quest.x,quest.y,giver.x,giver.y)
			if distance < nearest then quest.n,nearest=giver.n,distance end
		end
	end
	local used, locations, candidates = 0, {}, {}
	local function Collect(rec)
		local cat=ns.Categories:GetVisibleCategory(rec,true)
		if cat then candidates[#candidates+1]={rec=rec,cat=cat,id=rec.id,n=rec.n,x=rec.x,y=rec.y,quality=rec.ephemeral and 1 or 3} end
	end
	local function Add(candidate)
		local rec,cat=candidate.rec,candidate.cat
		if rec.cats.quest and ns.QuestAvailability:HasAvailableQuest(rec) then return end
		-- A quest replaces services at the same NPC. Use identities, or a tight
		-- four-yard fallback when identity is unknown, never a screen-pixel radius
		-- that grows in world space as the minimap zooms out.
		for _, quest in ipairs(quests) do
			local distance = ns.Distance(rec.x, rec.y, quest.x, quest.y)
			if quest.n and rec.n then
				if quest.n == rec.n and distance < 25 then return end
			elseif distance < 4 then return end
		end
		local east, north = wy - rec.y, rec.x - wx
		local x, y = east*cosine + north*sine, north*cosine - east*sine
		local safeRadius = radius * (1 - 8/math.max(halfW, 16))
		if square then
			if math.abs(x) > safeRadius or math.abs(y) > safeRadius then return end
		elseif x*x + y*y > safeRadius*safeRadius then return end
		for _, prior in ipairs(locations) do
			if prior == rec or ns.ServiceLocations:Same(rec,prior) then return end
		end
		locations[#locations+1] = rec
		used = used + 1
		local pin = Acquire(used)
		pin.rec, pin.catID = rec, cat
		local kind, icon = ns.Categories:GetIconSource(cat, rec)
		if pin.iconKind ~= kind or pin.iconSource ~= icon then
			ns.Categories:ApplyIcon(pin.Icon, cat, rec)
			pin.iconKind, pin.iconSource = kind, icon
		end
		local px, py = x/radius*halfW, y/radius*halfH
		if pin.anchor ~= Minimap or pin.px ~= px or pin.py ~= py then
			pin:ClearAllPoints()
			pin:SetPoint("CENTER", Minimap, "CENTER", px, py)
			pin.anchor, pin.px, pin.py = Minimap, px, py
		end
		if not pin.drawn then pin:Show(); pin.drawn = true end
	end
	ns.Database:Query(cont, wx-radius, wx+radius, wy-radius, wy+radius, Collect)
	ns.Seeds:Query(cont, wx-radius, wx+radius, wy-radius, wy+radius, Collect)
	ns.MinimapTurnIns:QueryServices(cont, wx-radius, wx+radius, wy-radius, wy+radius, Collect)
	table.sort(candidates,function(a,b)
		if a.quality~=b.quality then return a.quality>b.quality end
		return ns.ServiceLocations:Less(a,b)
	end)
	for _,candidate in ipairs(candidates) do Add(candidate) end
	for index=used+1,#pins do
		if pins[index].drawn then pins[index]:Hide(); pins[index].drawn = nil end
	end
	self.pins = pins
	self:SyncTracking()
end
function Mini:OnLogin()
	self:InstallTrackingMenu()
	local function Update()
		if self.settingSelection then return end
		self:RequestUpdate()
	end
	C_Timer.After(0, Update)
	C_Timer.NewTicker(0.2, Update)
	for _, message in ipairs({ "POI_UPDATED", "POI_REMOVED", "EXPLORED", "DATA_CHANGED" }) do ns:On(message, Update) end
	ns:On("SETTING_CHANGED",function()
		self.trackingDirty = true
		if self.settingSelection then return end
		Update()
		if MiniMapTrackingButton and MiniMapTrackingButton.GenerateMenu then MiniMapTrackingButton:GenerateMenu() end
	end)
	ns:RegisterEvent("MINIMAP_UPDATE_TRACKING", function() self.trackingDirty = true; self:SyncTracking() end)
	ns:RegisterEvent("PLAYER_LOGOUT", function() self.leaving = true; self.active = false; self:SyncTracking() end)
end
