-- Exploration belongs to the whole stitched map, including painted zones and
-- capitals. A filtered exploration field makes discoveries feather into the fog.
-- Its spacing follows the zoom, keeping the blend visible on the painted map.
-- Empty tiles still merge into large rectangles; only edges need blend textures.
local _, ns = ...
local Fog = ns:NewModule("WorldFog")
local TILE, CELL = ns.TILE, ns.CELL
local PATH = "Interface\\AddOns\\" .. ns.name .. "\\Media\\Fog\\Fog"
local BLEND = "Interface\\AddOns\\" .. ns.name .. "\\Media\\Fog\\Blend"
local LEVELS, ATLAS_SIZE, PATCH_SIZE, PATCH_COLUMNS = 4, 1024, 32, 32
local cache, textures, used = {}, {}, 0
local view, signature
local floor = math.floor

local function Key(x,y) return x .. ":" .. y end
local function State(cont, stride)
	local state = cache[cont]
	if not state or state.stride ~= stride then
		state = {stride=stride, chunks={}, coverage={}, levels={}}
		cache[cont] = state
	end
	return state
end

-- Average the original fine cells, then filter neighbouring averages. The saved
-- exploration remains exact; this only changes how its boundary is drawn.
local function Coverage(state, cont, gx, gy)
	local key = Key(gx,gy)
	local value = state.coverage[key]
	if value ~= nil then return value end
	local stride = state.stride
	local x, y = gx*stride, gy*stride
	local col,row = floor(x/ns.CELLS),floor(y/ns.CELLS)
	local rows = ns.Exploration:GetTileRows(cont,ns.TileKey(col,row))
	local count = 0
	if rows then
		local cx,cy = x%ns.CELLS,y%ns.CELLS
		for j=cy,cy+stride-1 do
			local bits = floor((rows[j+1] or 0)/2^cx)%2^stride
			while bits>0 do count=count+bits%2;bits=floor(bits/2) end
		end
	end
	value = count/(stride*stride)
	state.coverage[key] = value
	return value
end

local function Level(state, cont, gx, gy)
	local key = Key(gx,gy)
	local value = state.levels[key]
	if value ~= nil then return value end
	local sum = 0
	for dy=-1,1 do for dx=-1,1 do
		sum = sum + Coverage(state,cont,gx+dx,gy+dy)*(dx==0 and 2 or 1)*(dy==0 and 2 or 1)
	end end
	value = floor(sum/16*LEVELS+.5)
	state.levels[key] = value
	return value
end

local function Pieces(cont, col, row, stride)
	local state = State(cont,stride)
	local key = ns.TileKey(col, row)
	if state.chunks[key] ~= nil then return state.chunks[key] end
	local any = false
	for dy = -1, (stride == ns.CELLS and 2 or 1) do
		for dx = -1, (stride == ns.CELLS and 2 or 1) do
			local value = ns.Exploration:GetTileRows(cont, ns.TileKey(col+dx,row+dy))
			if value then
				for _, mask in ipairs(value) do if mask ~= 0 then any = true; break end end
			end
		end
	end
	local pieces = false -- solid fog, merged with adjacent empty tiles
	if any then
		pieces = {}
		local count, solid, nonzero = ns.CELLS/stride, {}, false
		for j=0,count-1 do
			local mask = 0
			for i=0,count-1 do
				local gx,gy = col*count+i,row*count+j
				local tl,tr = Level(state,cont,gx,gy),Level(state,cont,gx+1,gy)
				local bl,br = Level(state,cont,gx,gy+1),Level(state,cont,gx+1,gy+1)
				local code = tl+5*tr+25*bl+125*br
				if code==0 then mask=mask+2^i
				else
					nonzero=true
					if code~=624 then
						pieces[#pieces+1]={code,(i+.5)*stride,(i+1.5)*stride,(j+.5)*stride,(j+1.5)*stride}
					end
				end
			end
			solid[j+1]=mask
		end
		if nonzero then
			for _,r in ipairs(ns.ExploredRectangles(solid)) do
				pieces[#pieces+1]={0,(r[1]+.5)*stride,(r[2]+.5)*stride,(r[3]+.5)*stride,(r[4]+.5)*stride}
			end
		else pieces=false end
	end
	state.chunks[key] = pieces
	return pieces
end

-- Exposed for renderer regression tests and previewing the delivered textures.
Fog.GetPieces = Pieces

local function SetBlend(tex, code, u0,u1,v0,v1)
	if tex:SetTexture(BLEND,"CLAMP","CLAMP","LINEAR") ~= false then
		local x,y = code%PATCH_COLUMNS*PATCH_SIZE,floor(code/PATCH_COLUMNS)*PATCH_SIZE
		local function U(u) return (x+1.5+u*(PATCH_SIZE-3))/ATLAS_SIZE end
		local function V(v) return (y+1.5+v*(PATCH_SIZE-3))/ATLAS_SIZE end
		tex:SetTexCoord(U(u0),U(u1),V(v0),V(v1))
		return true
	end
	-- A client already running when the new atlas is installed may not see it
	-- until restart. Its existing soft-edge textures remain a usable fallback.
	local bits, place = 0,1
	for _=1,4 do
		if code%5>=2 then bits=bits+place end
		code,place=floor(code/5),place*2
	end
	tex:SetTexture(PATH..bits,"CLAMP","CLAMP","LINEAR")
	tex:SetTexCoord(u0,u1,v0,v1)
	return bits~=15
end

local function Draw(rect, bounds, x0, x1, y0, y1, case)
	local left, right = math.max(x0, bounds[1]), math.min(x1, bounds[2])
	local top, bottom = math.max(y0, bounds[3]), math.min(y1, bounds[4])
	if right <= left or bottom <= top then return end
	used = used + 1
	local tex = textures[used]
	if not tex then
		tex = Fog.frame:CreateTexture(nil, "ARTWORK")
		tex:SetSnapToPixelGrid(false)
		tex:SetTexelSnappingBias(0)
		textures[used] = tex
	end
	if case == 0 then
		tex:SetColorTexture(.10, .11, .14, 1)
		tex:SetTexCoord(0,1,0,1)
	else
		if not SetBlend(tex,case,(left-x0)/(x1-x0),(right-x0)/(x1-x0),
			(top-y0)/(y1-y0),(bottom-y0)/(y1-y0)) then tex:Hide();return end
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
			local pixels = CELL*(r-l)/world.width*WorldMapFrame.ScrollContainer:GetWidth()/(view[2]-view[1])
			local stride = 1
			while stride<ns.CELLS and pixels*stride<10 do stride=stride*2 end
			local offset = CELL*stride/2
			local a, z = math.floor((x0-offset)/TILE)+32, math.floor((x1-offset)/TILE)+32
			local c, d = math.floor((y0-offset)/TILE)+32, math.floor((y1-offset)/TILE)+32
			ranges[#ranges+1] = {world=world,l=l*W,t=t*H,sx=(r-l)*W/world.width,sy=(b-t)*H/world.height,
				bounds=bounds,a=a,z=z,c=c,d=d,stride=stride,offset=offset}
			parts[#parts+1] = table.concat({id,a,z,c,d,stride}, ":")
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
				local pieces = Pieces(rect.world.cont, col, row,rect.stride)
				if pieces then
					local ox, oy = ns.TileOrigin(col, row)
					for _, p in ipairs(pieces) do
						Draw(rect,rect.bounds,ox+p[2]*CELL,ox+p[3]*CELL,oy+p[4]*CELL,oy+p[5]*CELL,p[1])
					end
					col = col + 1
				else
					local first = col
					repeat col = col + 1 until col > rect.z or Pieces(rect.world.cont,col,row,rect.stride)
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
			Draw(rect,rect.bounds,(p[1]-32)*TILE+rect.offset,(p[2]-32)*TILE+rect.offset,
				(p[3]-32)*TILE+rect.offset,(p[4]-32)*TILE+rect.offset,0)
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
		local state = cache[cont]
		local count = ns.CELLS/state.stride
		for _, key in ipairs(keys) do
			local col, row = ns.SplitTileKey(key)
			for dy=-2,1 do for dx=-2,1 do state.chunks[ns.TileKey(col+dx,row+dy)]=nil end end
			for y=row*count,(row+1)*count-1 do
				for x=col*count,(col+1)*count-1 do state.coverage[Key(x,y)]=nil end
			end
			for y=row*count-1,(row+1)*count do
				for x=col*count-1,(col+1)*count do state.levels[Key(x,y)]=nil end
			end
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
