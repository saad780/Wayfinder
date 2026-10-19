-- One Wayfinder marker per nearby service location on the live minimap.
local _, ns = ...
local Mini = ns:NewModule("MinimapServices")
local pins, tracking = {}, {}
local SCAN_MARGIN = 64 -- cache beyond the edge so pins enter smoothly between scans
local hookedMinimaps = setmetatable({}, { __mode = "k" })
local function Number(v) return ns.Readable(v) and type(v) == "number" and v == v and math.abs(v) < math.huge end
local function DirectPosition(expectedCont)
	if not UnitPosition then return end
	local ok, north, west, _, cont = pcall(UnitPosition, "player")
	-- Match our north/west map coordinates. Keep the map API fallback when
	-- positions are restricted or an instance uses another coordinate system.
	if ok and Number(north) and Number(west) and Number(cont) and cont == expectedCont then return cont, north, west end
end
local function Hide(pin)
	if pin.drawn then pin:Hide(); pin.drawn = nil end
end
local function HideAll()
	for _,pin in ipairs(pins) do Hide(pin) end
end
local function Selected(cats)
	for _,cat in ipairs(cats) do if ns:IsCategoryEnabled(cat) then return true end end
	return false
end
function Mini:IsActive() return self.active == true end

function Mini:GetTrackingCategories(index, info)
	info = info or C_Minimap.GetTrackingInfo(index)
	if not info or info.type == "spell" then return {} end
	local filter = C_Minimap.GetTrackingFilter and C_Minimap.GetTrackingFilter(index)
	local filterID = filter and filter.filterID
	local key = filterID or ("tracking:" .. tostring(info.name))
	self.filterCategories = self.filterCategories or {}
	if self.filterCategories[key] then return self.filterCategories[key], key end
	local result = {}
	for _, cat in ipairs(ns.CategoryList) do
		if filterID and cat.filter and Enum.MinimapTrackingFilter and Enum.MinimapTrackingFilter[cat.filter] == filterID then result[#result+1] = cat.id end
	end
	for key,cat in pairs({Vendor="vendor",Vender="vendor",Merchant="vendor",WeaponMaster="weaponmaster",SpiritHealer="spirit"}) do
		if filterID and Enum.MinimapTrackingFilter and Enum.MinimapTrackingFilter[key] == filterID then result[#result+1] = cat end
	end
	if #result == 0 then
		local name = info and info.name
		if ns.Readable(name) and type(name)=="string" and (name:lower():find("vendor",1,true) or name:lower():find("merchant",1,true)) then result[1]="vendor" end
		-- Some Classic clients expose tracking info without GetTrackingFilter.
		-- Match their localized menu artwork/labels; never claim tracking spells.
		for _,cat in ipairs(ns.CategoryList) do
			if cat.filter and (name == cat.label or (info.texture and cat.icon and info.texture == cat.icon.texture)) then
				result[#result+1] = cat.id
			end
		end
	end
	self.filterCategories[key] = result
	return result, key
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
	if self.syncing then return end
	if not C_Minimap or not C_Minimap.SetTracking or not C_Minimap.GetNumTrackingTypes
		or not C_Minimap.GetTrackingInfo then self.nativeCategories = {}; return end
	local now = GetTime()
	if not self.trackingDirty and self.trackingActive == self.active and self.trackingAPI == C_Minimap.GetTrackingInfo
		and self.trackingFilterAPI == C_Minimap.GetTrackingFilter and now < (self.trackingCheckAt or 0) then return end
	self.syncing = true
	local nativeCategories = {}
	for i = 1, C_Minimap.GetNumTrackingTypes() do
		local info = C_Minimap.GetTrackingInfo(i)
		local cats, key = self:GetTrackingCategories(i, info)
		if #cats > 0 and info and type(info.active) == "boolean" then
			if self.active and not self.leaving then
				tracking[key] = Selected(cats)
				local selected = tracking[key]
				if info.active ~= selected then
					pcall(C_Minimap.SetTracking, i, selected)
					info = C_Minimap.GetTrackingInfo(i) or info
				end
				if info.active then for _,cat in ipairs(cats) do nativeCategories[cat] = true end end
			elseif tracking[key] ~= nil then
				local selected = Selected(cats)
				if info.active ~= selected then pcall(C_Minimap.SetTracking, i, selected) end
				tracking[key] = nil
			end
		end
	end
	-- Native blips are anchored by the client to live NPCs. Do not cover them
	-- with another Lua-projected icon, or disable undiscovered native services.
	self.nativeCategories = nativeCategories
	self.syncing = false
	self.trackingDirty, self.trackingActive = nil, self.active
	self.trackingAPI, self.trackingFilterAPI = C_Minimap.GetTrackingInfo, C_Minimap.GetTrackingFilter
	self.trackingCheckAt = now + 2 -- events/hooks handle edits immediately; fallback catches other owners
end
local function Acquire(index)
	local pin = pins[index]
	if not pin then
		pin = CreateFrame("Button", nil, Minimap)
		pin:Hide() -- buffered sources may start outside the visible minimap
		pin:SetSize(16, 16)
		pin:SetFrameLevel(Minimap:GetFrameLevel() + 12)
		pin:RegisterForClicks("LeftButtonUp", "MiddleButtonUp")
		pin.Icon = pin:CreateTexture(nil, "OVERLAY")
		pin.Icon:SetAllPoints()
		pin.Icon:SetSnapToPixelGrid(false)
		pin.Icon:SetTexelSnappingBias(0)
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
-- This path only projects cached world positions. Discovery, native quest
-- reads, filtering, sorting and artwork remain on the separate data refresh.
function Mini:ReadView()
	if not Minimap then return false end
	local radius = C_Minimap and C_Minimap.GetViewRadius and C_Minimap.GetViewRadius()
	if not Number(radius) or radius <= 0 then return false end
	local halfW, halfH = Minimap:GetWidth()/2, Minimap:GetHeight()/2
	if halfW < 16 or halfH < 16 then return false end
	local rotate = GetCVarBool and GetCVarBool("rotateMinimap")
	if C_Minimap.IsRotateMinimapIgnored and C_Minimap.IsRotateMinimapIgnored() then rotate = false end
	self.radius, self.halfW, self.halfH = radius, halfW, halfH
	self.rotate, self.square = rotate, GetMinimapShape and GetMinimapShape() == "SQUARE"
	self.viewOwner, self.viewDirty, self.motionDirty = Minimap, nil, true
	return true
end
function Mini:StartMotion()
	if not self.motionFrame then
		self.motionFrame = CreateFrame("Frame")
		self.motionFrame:SetScript("OnUpdate", function() self:UpdatePositions() end)
	end
	if self.motionFrame:GetParent() ~= Minimap then self.motionFrame:SetParent(Minimap) end
	if not hookedMinimaps[Minimap] then
		hookedMinimaps[Minimap] = true
		local function Changed(owner)
			if owner == Minimap then self.viewDirty = true; self:RequestUpdate() end
		end
		Minimap:HookScript("OnSizeChanged", Changed)
		Minimap:HookScript("OnShow", Changed)
	end
	self.motionFrame:Show()
end
function Mini:UpdatePositions(cont, wx, wy)
	if not self.active or not Minimap or not Minimap:IsVisible() then return end
	-- The client animates radius changes (including indoor/outdoor changes).
	-- Sampling only on the data tick makes pins drift, then snap back.
	local radius = C_Minimap.GetViewRadius()
	if Number(radius) and radius > 0 and radius ~= self.radius then self.viewDirty = true end
	if self.viewDirty or self.viewOwner ~= Minimap then
		if not self:ReadView() then HideAll(); return end
	end
	if not cont then
		cont, wx, wy = DirectPosition(self.scanCont)
		if not cont then cont, wx, wy = ns.GetPlayerWorld() end
	end
	if not cont or cont ~= self.scanCont then HideAll(); self:RequestUpdate(); return end
	if math.abs(wx-self.scanX) > SCAN_MARGIN/2 or math.abs(wy-self.scanY) > SCAN_MARGIN/2
		or self.radius ~= self.scanRadius then self:RequestUpdate() end
	local facing = self.rotate and GetPlayerFacing() or 0
	if not Number(facing) then facing = 0 end
	if not self.motionDirty and self.lastX == wx and self.lastY == wy and self.lastFacing == facing then return end
	local started = ns.Background:Begin()
	local cosine, sine = math.cos(facing), math.sin(facing)
	local radius, halfW, halfH = self.radius, self.halfW, self.halfH
	local safeRadius = radius * (1 - 8/math.max(halfW,16))
	for index=1,self.cachedCount or 0 do
		local pin = pins[index]
		local east, north = wy-pin.rec.y, pin.rec.x-wx
		local x, y = east*cosine+north*sine, north*cosine-east*sine
		local visible
		if self.square then visible = math.abs(x)<=safeRadius and math.abs(y)<=safeRadius
		else visible = x*x+y*y<=safeRadius*safeRadius end
		if visible then
			local px, py = x/radius*halfW, y/radius*halfH
			if pin.anchor ~= Minimap or pin.px ~= px or pin.py ~= py then
				pin:ClearAllPoints()
				pin:SetPoint("CENTER", Minimap, "CENTER", px, py)
				pin.anchor, pin.px, pin.py = Minimap, px, py
			end
			if not pin.drawn then pin:Show(); pin.drawn = true end
		else Hide(pin) end
	end
	self.lastX, self.lastY, self.lastFacing, self.motionDirty = wx, wy, facing, nil
	ns.Background:Finish("minimap movement", started, self.cachedCount)
end
function Mini:Rebuild()
	self.active = false
	local function Inactive()
		HideAll()
		self.cachedCount = 0
		if self.motionFrame then self.motionFrame:Hide() end
		self:SyncTracking()
	end
	if self.leaving or not Minimap or not ns:GetSetting("showMinimapServices") then Inactive(); return end
	local cont, wx, wy = ns.GetPlayerWorld()
	if not cont or not self:ReadView() then Inactive(); return end
	local directCont, directX, directY = DirectPosition(cont)
	if directCont then wx, wy = directX, directY end
	local radius = self.radius
	local extent = radius + SCAN_MARGIN
	self.active = true
	self:SyncTracking()
	self.scanCont, self.scanX, self.scanY, self.scanRadius = cont, wx, wy, radius
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
	ns.MinimapTurnIns:QueryQuestGivers(cont, wx-extent-25, wx+extent+25, wy-extent-25, wy+extent+25, function(info)
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
	local used, locations, candidates, nativeLocations = 0, {}, {}, {}
	local function Collect(rec)
		local cat=ns.Categories:GetVisibleCategory(rec)
		if cat then candidates[#candidates+1]={rec=rec,cat=cat,id=rec.id,n=rec.n,x=rec.x,y=rec.y,quality=rec.ephemeral and 1 or 3} end
	end
	local function Add(candidate)
		local rec,cat=candidate.rec,candidate.cat
		if self.nativeCategories[cat] then return end
		if cat ~= "quest" then
			for _,native in ipairs(nativeLocations) do
				if ns.ServiceLocations:Same(rec,native) then return end
			end
		end
		-- A quest replaces services at the same NPC. Use identities, or a tight
		-- four-yard fallback when identity is unknown, never a screen-pixel radius
		-- that grows in world space as the minimap zooms out.
		for _, quest in ipairs(quests) do
			local distance = ns.Distance(rec.x, rec.y, quest.x, quest.y)
			if quest.n and rec.n then
				if quest.n == rec.n and distance < 25 then return end
			elseif distance < 4 then return end
		end
		for _, prior in ipairs(locations) do
			if prior == rec or ns.ServiceLocations:Same(rec,prior) then return end
		end
		locations[#locations+1] = rec
		used = used + 1
		local pin = Acquire(used)
		pin.rec, pin.catID = rec, cat
		local level = Minimap:GetFrameLevel() + (cat == "quest" and 13 or 12)
		if pin.serviceLevel ~= level then pin:SetFrameLevel(level); pin.serviceLevel = level end
		local kind, icon = ns.Categories:GetIconSource(cat, rec)
		if pin.iconKind ~= kind or pin.iconSource ~= icon then
			ns.Categories:ApplyIcon(pin.Icon, cat, rec)
			pin.iconKind, pin.iconSource = kind, icon
		end

	end
	ns.Database:Query(cont, wx-extent, wx+extent, wy-extent, wy+extent, Collect)
	ns.Seeds:Query(cont, wx-extent, wx+extent, wy-extent, wy+extent, Collect)
	ns.MinimapTurnIns:QueryServices(cont, wx-extent, wx+extent, wy-extent, wy+extent, Collect)
	for _,candidate in ipairs(candidates) do
		if self.nativeCategories[candidate.cat] then nativeLocations[#nativeLocations+1] = candidate.rec end
	end
	table.sort(candidates,function(a,b)
		if a.quality~=b.quality then return a.quality>b.quality end
		return ns.ServiceLocations:Less(a,b)
	end)
	for _,candidate in ipairs(candidates) do Add(candidate) end
	for index=used+1,#pins do Hide(pins[index]) end
	self.cachedCount, self.motionDirty = used, true
	if used>0 then self:StartMotion(); self:UpdatePositions()
	elseif self.motionFrame then self.motionFrame:Hide() end
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
	-- SetTracking can fire its event before secure post-hooks capture the user's
	-- choice. Synchronize next frame, after that choice has updated our settings.
	ns:RegisterEvent("MINIMAP_UPDATE_TRACKING", function() self.trackingDirty = true; self:RequestUpdate() end)
	ns:RegisterEvent("MINIMAP_UPDATE_ZOOM", function() self.viewDirty = true; self:RequestUpdate() end)
	ns:RegisterEvent("CVAR_UPDATE", function(_, name)
		if name == "rotateMinimap" or name == "ROTATE_MINIMAP" then self.viewDirty = true; self:RequestUpdate() end
	end)
	ns:RegisterEvent("PLAYER_LOGOUT", function() self.leaving = true; self.active = false; self:SyncTracking() end)
end
