-- Exploration belongs to the whole stitched map, including painted zones and
-- capitals. One layer covers both map art and terrain so the blend never doubles
-- the fog. Empty tiles merge into large rectangles; only explored edges need the
-- marching-squares pieces shared with the standalone detail view.
local _, ns = ...
local Fog = ns:NewModule("WorldFog")
local TILE, CELL = ns.TILE, ns.CELL
local PATH = "Interface\\AddOns\\" .. ns.name .. "\\Media\\Fog\\Fog"
local cache, textures, used = {}, {}, 0
local view, signature

local function Pieces(cont, col, row)
	cache[cont] = cache[cont] or {}
	local key = ns.TileKey(col, row)
	if cache[cont][key] ~= nil then return cache[cont][key] end
	local rows, any = {}, false
	for dy = 0, 1 do
		for dx = 0, 1 do
			local value = ns.Exploration:GetTileRows(cont, ns.TileKey(col + dx, row + dy))
			rows[dy * 2 + dx] = value
			if value then
				for _, mask in ipairs(value) do if mask ~= 0 then any = true; break end end
			end
		end
	end
	local pieces = false -- solid fog, merged with adjacent empty tiles
	if any then
		pieces = ns.FogPieces(function(x, y)
			local dx, dy = x >= ns.CELLS and 1 or 0, y >= ns.CELLS and 1 or 0
			local value = rows[dy * 2 + dx]
			return value and ns.HasBit(value[y % ns.CELLS + 1] or 0, x % ns.CELLS)
		end, {})
	end
	cache[cont][key] = pieces
	return pieces
end

local function Draw(rect, bounds, x0, x1, y0, y1, case, u0, u1, v0, v1)
	local left, right = math.max(x0, bounds[1]), math.min(x1, bounds[2])
	local top, bottom = math.max(y0, bounds[3]), math.min(y1, bounds[4])
	if right <= left or bottom <= top then return end
	used = used + 1
	local tex = textures[used]
	if not tex then tex = Fog.frame:CreateTexture(nil, "ARTWORK"); textures[used] = tex end
	if case == 0 then
		tex:SetColorTexture(.10, .11, .14, 1)
	else
		tex:SetTexture(PATH .. case, "CLAMP", "CLAMP", "LINEAR")
		tex:SetTexCoord(u0 + (u1-u0)*(left-x0)/(x1-x0), u0 + (u1-u0)*(right-x0)/(x1-x0),
			v0 + (v1-v0)*(top-y0)/(y1-y0), v0 + (v1-v0)*(bottom-y0)/(y1-y0))
	end
	tex:SetVertexColor(.10, .11, .14)
	-- Color textures already contain the tint.
	if case == 0 then tex:SetVertexColor(1, 1, 1) end
	tex:SetAlpha(1 - (ns:GetSetting("unexploredBrightness") or .4))
	tex:ClearAllPoints()
	tex:SetPoint("TOPLEFT", Fog.frame, "TOPLEFT", rect.l + (left + rect.world.left) * rect.sx,
		-(rect.t + (top + rect.world.top) * rect.sy))
	tex:SetSize((right-left)*rect.sx, (bottom-top)*rect.sy)
	tex:Show()
end

function Fog:Refresh()
	if not view or not self.frame or not self.frame:IsShown() then return end
	used = 0
	local S = ns.ContinuousEngine.MapStitch
	local W, H = S.Size()
	local ranges, parts = {}, {}
	for _, id in ipairs({1414, 1415}) do
		local l, r, t, b = S.Rect(id)
		local world = ns.GetMapRect(id)
		if l and world and r >= view[1] and l <= view[2] and b >= view[3] and t <= view[4] then
			local bounds = {-world.left, world.width-world.left, -world.top, world.height-world.top}
			local x0 = math.max(bounds[1], (view[1]-l)/(r-l)*world.width-world.left)
			local x1 = math.min(bounds[2], (view[2]-l)/(r-l)*world.width-world.left)
			local y0 = math.max(bounds[3], (view[3]-t)/(b-t)*world.height-world.top)
			local y1 = math.min(bounds[4], (view[4]-t)/(b-t)*world.height-world.top)
			local a, z = math.floor((x0-CELL/2)/TILE)+32, math.floor((x1-CELL/2)/TILE)+32
			local c, d = math.floor((y0-CELL/2)/TILE)+32, math.floor((y1-CELL/2)/TILE)+32
			ranges[#ranges+1] = {world=world,l=l*W,t=t*H,sx=(r-l)*W/world.width,sy=(b-t)*H/world.height,
				bounds=bounds,a=a,z=z,c=c,d=d}
			parts[#parts+1] = table.concat({id,a,z,c,d}, ":")
		end
	end
	local key = table.concat(parts, ";")
	if key == signature then return end
	signature = key
	for _, rect in ipairs(ranges) do
		local open, solids = {}, {}
		for row = rect.c, rect.d do
			local nextOpen, col = {}, rect.a
			while col <= rect.z do
				local pieces = Pieces(rect.world.cont, col, row)
				if pieces then
					local ox, oy = ns.TileOrigin(col, row)
					for _, p in ipairs(pieces) do
						Draw(rect,rect.bounds,ox+p[2]*CELL,ox+p[3]*CELL,oy+p[4]*CELL,oy+p[5]*CELL,
							p[1],p[6],p[7],p[8],p[9])
					end
					col = col + 1
				else
					local first = col
					repeat col = col + 1 until col > rect.z or Pieces(rect.world.cont,col,row)
					local run = first .. ":" .. col
					local solid = open[run]
					if solid then solid[4] = row + 1
					else solid = {first,col,row,row+1}; solids[#solids+1] = solid end
					nextOpen[run] = solid
				end
			end
			open = nextOpen
		end
		for _, p in ipairs(solids) do
			Draw(rect,rect.bounds,(p[1]-32)*TILE+CELL/2,(p[2]-32)*TILE+CELL/2,
				(p[3]-32)*TILE+CELL/2,(p[4]-32)*TILE+CELL/2,0)
		end
	end
	for i = used + 1, #textures do textures[i]:Hide() end
end

function Fog:Follow(parent, level, u, v, hu, hv, shown)
	if not self.frame then
		self.frame = CreateFrame("Frame", nil, parent)
		self.frame:SetAllPoints(parent)
		self.frame:SetFrameLevel(level)
		self.frame:EnableMouse(false)
	end
	view = {u-hu,u+hu,v-hv,v+hv}
	self.frame:SetShown(shown and ns:GetSetting("unexploredTerrain") == ns.UNEXPLORED_DARKENED)
	self:Refresh()
end

function Fog:Invalidate(cont, keys)
	if cont and keys and cache[cont] then
		for _, key in ipairs(keys) do
			local col, row = ns.SplitTileKey(key)
			for dy = -1, 0 do for dx = -1, 0 do cache[cont][ns.TileKey(col+dx,row+dy)] = nil end end
		end
	else wipe(cache) end
	signature = nil
	if self.pending then return end
	self.pending = true
	C_Timer.After(.05, function() self.pending = nil; self:Refresh() end)
end

function Fog:OnLogin()
	ns:On("EXPLORED", function(cont, keys) self:Invalidate(cont, keys) end)
	ns:On("SETTING_CHANGED", function(key)
		if key == "shareExploration" or key == "unexploredTerrain" or key == "unexploredBrightness" then
			self:Invalidate()
			if self.frame then self.frame:SetShown(view and ns.ContinuousMap:IsActive()
				and ns:GetSetting("unexploredTerrain") == ns.UNEXPLORED_DARKENED) end
		end
	end)
end
