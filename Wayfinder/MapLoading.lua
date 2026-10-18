-- Prioritize visible Questie draw requests without importing data, increasing
-- its per-tick work, or dropping/recreating any of its markers.
local _, ns = ...
local Loading = ns:NewModule("MapLoading")
local function Number(v) return ns.Readable(v) and type(v) == "number" and v == v and math.abs(v) < math.huge end

function Loading:Prioritize()
	local map = self.questie
	local queue = map and map._mapDrawQueue
	if not WorldMapFrame:IsShown() or not ns.OpenMapCompat:IsActive() or type(queue) ~= "table" or #queue <= 24 then return end
	local boxes = ns.OpenMapCompat:GetViewBoxes(0.15)
	local groups = { {}, {}, {} }
	for _, request in ipairs(queue) do
		local group = 3
		if type(request) == "table" and Number(request[3]) and Number(request[4]) and Number(request[5]) then
			local c,x,y = ns.MapToWorld(request[3],request[4],request[5])
			for _, box in ipairs(boxes) do
				if c == box.cont and x >= box.minX and x <= box.maxX and y >= box.minY and y <= box.maxY then
					local data = request[2] and request[2].data
					group = type(data) == "table" and (data.Type == "complete" or data.Type == "available") and 1 or 2
					break
				end
			end
		end
		groups[group][#groups[group]+1] = request
	end
	if #groups[1] + #groups[2] == 0 then return end
	local index = 0
	for _, group in ipairs(groups) do
		for _, request in ipairs(group) do index=index+1; queue[index]=request end
	end
end

function Loading:Request()
	if self.pending or not WorldMapFrame:IsShown() or not ns.OpenMapCompat:IsActive() then return end
	self.pending = true
	C_Timer.After(0, function() self.pending=nil; self:Prioritize() end)
end

function Loading:Install()
	if not QuestieLoader or not QuestieLoader.ImportModule then return end
	local ok, map = pcall(QuestieLoader.ImportModule,QuestieLoader,"QuestieMap")
	if not ok or type(map) ~= "table" or type(map.QueueDraw) ~= "function" or self.questie == map then return end
	self.questie = map
	hooksecurefunc(map,"QueueDraw",function(_,typ)
		if typ == map.ICON_MAP_TYPE then self:Request() end
	end)
	self:Request()
end

function Loading:OnLogin()
	C_Timer.After(0,function() self:Install() end)
	ns.ContinuousMap.API.RegisterCallback(self,"OpenMap_ViewChanged",function() self:Request() end)
	ns:RegisterEvent("ADDON_LOADED",function(_,name)
		if name == "Questie" then C_Timer.After(0,function() self:Install() end) end
	end)
end
