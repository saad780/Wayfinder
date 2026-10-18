-- Which parts of the terrain you have seen.
--
-- Every minimap tile is split into 16x16 cells (33 yards). A cell counts as explored
-- once it has been inside your minimap's view while you moved around, or when the
-- world map says the area it lies in is discovered (imported once per character).
--
-- Saved as WayfinderDB.explored[character][continent][tileKey] = { row1 .. row16 },
-- each row a 16-bit mask of explored cells (bit 0 = westmost).
local _, ns = ...

local Exploration = ns:NewModule("Exploration")

local floor, min, max = math.floor, math.min, math.max
local CELLS = ns.CELLS
local CELL = ns.CELL
local FULL_ROW = 2 ^ CELLS - 1
local POW = {}
for i = 0, CELLS - 1 do
	POW[i] = 2 ^ i
end

local bor = bit and bit.bor

local function HasBit(value, index)
	return floor(value / POW[index]) % 2 == 1
end

local function Or(a, b)
	if bor then
		return bor(a, b)
	end
	local result = 0
	for i = 0, CELLS - 1 do
		if HasBit(a, i) or HasBit(b, i) then
			result = result + POW[i]
		end
	end
	return result
end

ns.HasBit = HasBit

local mine          -- this character's [cont][tileKey] -> rows
local unionCache = {} -- [cont][tileKey] -> rows across characters (shareExploration)
local generation = 0

function Exploration:OnLogin()
	local all = ns.db.explored
	local key = ns:GetCharacterKey()
	all[key] = all[key] or {}
	mine = all[key]
	ns.db.imported[key] = ns.db.imported[key] or {}

	ns:On("SETTING_CHANGED", function(setting)
		if setting == "shareExploration" then
			wipe(unionCache)
			ns:Fire("EXPLORED", nil)
		end
	end)

	self:StartSampling()
	if ns:GetSetting("importExploration") then
		C_Timer.After(3, function()
			self:QueueImportCurrentZone()
			self:QueueImportAll(false)
		end)
	end
end

function Exploration:Reset()
	generation = generation + 1
	wipe(unionCache)
	local key = ns:GetCharacterKey()
	ns.db.explored[key] = {}
	ns.db.imported[key] = {}
	mine = ns.db.explored[key]
	ns:Fire("EXPLORED", nil)
end

---------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------
-- Returns the 16 row masks of a tile, or nil if nothing in it is explored.
function Exploration:GetTileRows(cont, tileKey)
	if not mine then
		return nil
	end
	if not ns:GetSetting("shareExploration") then
		local contTiles = mine[cont]
		return contTiles and contTiles[tileKey]
	end
	local contCache = unionCache[cont]
	if not contCache then
		contCache = {}
		unionCache[cont] = contCache
	end
	local cached = contCache[tileKey]
	if cached == nil then
		cached = false
		for _, chars in pairs(ns.db.explored) do
			local rows = chars[cont] and chars[cont][tileKey]
			if rows then
				if not cached then
					cached = {}
					for r = 1, CELLS do cached[r] = 0 end
				end
				for r = 1, CELLS do
					cached[r] = Or(cached[r], rows[r] or 0)
				end
			end
		end
		contCache[tileKey] = cached
	end
	return cached or nil
end

function Exploration:IsTileComplete(rows)
	for r = 1, CELLS do
		if rows[r] ~= FULL_ROW then
			return false
		end
	end
	return true
end

-- Whether a spot is explored. Ignores "show unexplored terrain", which only affects
-- what terrain is drawn, not which places count as discovered.
function Exploration:IsExplored(cont, wx, wy)
	local px, py = ns.WorldToPlane(wx, wy)
	local col, row, cx, cy = ns.PlaneToCell(px, py)
	local rows = self:GetTileRows(cont, ns.TileKey(col, row))
	return rows ~= nil and HasBit(rows[cy + 1] or 0, cx)
end

function Exploration:CountExploredCells()
	local count = 0
	for _, tiles in pairs(mine or {}) do
		for _, rows in pairs(tiles) do
			for r = 1, CELLS do
				local v = rows[r] or 0
				while v > 0 do
					count = count + v % 2
					v = floor(v / 2)
				end
			end
		end
	end
	return count
end

---------------------------------------------------------------------------
-- Writing
---------------------------------------------------------------------------
local changed = {} -- scratch: tileKey -> true

local function SetCell(cont, gx, gy, dirty)
	local col, row = floor(gx / CELLS), floor(gy / CELLS)
	local tileKey = col * 100 + row
	local tiles = ns.TileData[cont]
	if not tiles or not tiles[tileKey] then
		return -- open sea or outside the map: nothing to draw there
	end
	local contTiles = mine[cont]
	if not contTiles then
		contTiles = {}
		mine[cont] = contTiles
	end
	local rows = contTiles[tileKey]
	if not rows then
		rows = {}
		for r = 1, CELLS do rows[r] = 0 end
		contTiles[tileKey] = rows
	end
	local cx, cy = gx - col * CELLS, gy - row * CELLS
	local value = rows[cy + 1]
	if not HasBit(value, cx) then
		rows[cy + 1] = value + POW[cx]
		local changes = dirty or changed
		changes[tileKey] = true
		local cache = unionCache[cont]
		local cached = cache and cache[tileKey]
		if cached then
			cached[cy + 1] = Or(cached[cy + 1], POW[cx])
		elseif cache then
			cache[tileKey] = nil
		end
	end
end

local function FlushChanged(cont, dirty)
	dirty = dirty or changed
	if next(dirty) then
		local keys = {}
		for tileKey in pairs(dirty) do
			keys[#keys + 1] = tileKey
		end
		wipe(dirty)
		ns:Fire("EXPLORED", cont, keys)
	end
end

-- Marks every cell whose centre lies within radius yards of a world point.
function Exploration:MarkCircle(cont, wx, wy, radius)
	if not mine or not ns.TileData[cont] then
		return
	end
	local px, py = ns.WorldToPlane(wx, wy)
	-- global cell grid: gx = px / CELL + 32 * CELLS
	local ox, oy = 32 * CELLS, 32 * CELLS
	local minX = floor((px - radius) / CELL + ox)
	local maxX = floor((px + radius) / CELL + ox)
	local minY = floor((py - radius) / CELL + oy)
	local maxY = floor((py + radius) / CELL + oy)
	local r2 = radius * radius
	for gy = max(minY, 0), min(maxY, 64 * CELLS - 1) do
		local cyPlane = (gy - oy + 0.5) * CELL
		local dy = cyPlane - py
		for gx = max(minX, 0), min(maxX, 64 * CELLS - 1) do
			local dx = (gx - ox + 0.5) * CELL - px
			if dx * dx + dy * dy <= r2 then
				SetCell(cont, gx, gy)
			end
		end
	end
	FlushChanged(cont)
end

---------------------------------------------------------------------------
-- Following the player
---------------------------------------------------------------------------
local lastCont, lastX, lastY, lastRadius

local function RevealRadius()
	local radius = ns:GetSetting("revealRadius")
	if not radius or radius <= 0 then
		radius = C_Minimap and C_Minimap.GetViewRadius and C_Minimap.GetViewRadius() or 100
	end
	return min(max(radius, 30), 300)
end

function Exploration:Sample()
	local cont, wx, wy = ns.GetPlayerWorld()
	if not cont then
		return
	end
	local radius = RevealRadius()
	if cont == lastCont and lastRadius == radius and ns.Distance(wx, wy, lastX, lastY) < 8 then
		return
	end
	lastCont, lastX, lastY, lastRadius = cont, wx, wy, radius
	self:MarkCircle(cont, wx, wy, radius)
	ns:Fire("PLAYER_SAMPLED", cont, wx, wy, radius)
end

function Exploration:StartSampling()
	if self.ticker then
		return
	end
	self.ticker = C_Timer.NewTicker(0.5, function()
		self:Sample()
	end)
	ns:RegisterEvent("ZONE_CHANGED_NEW_AREA", function()
		lastCont = nil
		self:QueueImportCurrentZone()
	end)
	ns:RegisterEvent("MINIMAP_UPDATE_ZOOM", function()
		lastRadius = nil
	end)
end

---------------------------------------------------------------------------
-- Importing the world map's own exploration (runs in the background)
---------------------------------------------------------------------------
local function ImportMap(mapID, version, force)
	local rect = ns.GetMapRect(mapID)
	if not rect or not ns.TileData[rect.cont] or not C_MapExplorationInfo then return false end
	local cont, dirty = rect.cont, {}
	local pxMin, pyMin = -rect.left, -rect.top
	local o = 32 * CELLS
	local gx0, gx1 = floor(pxMin / CELL + o), floor((pxMin + rect.width) / CELL + o)
	local gy0, gy1 = floor(pyMin / CELL + o), floor((pyMin + rect.height) / CELL + o)
	local pos, steps = CreateVector2D(0, 0), 0
	local tiles = ns.TileData[cont]
	for gy = max(gy0, 0), min(gy1, 64 * CELLS - 1) do
		local py = (gy - o + 0.5) * CELL
		local ny, row = (py - pyMin) / rect.height, floor(gy / CELLS)
		for gx = max(gx0, 0), min(gx1, 64 * CELLS - 1) do
			if version ~= generation then return false end
			if not force and not ns:GetSetting("importExploration") then FlushChanged(cont, dirty); return false end
			local col = floor(gx / CELLS)
			if tiles[col * 100 + row] then
				local nx = ((gx - o + 0.5) * CELL - pxMin) / rect.width
				if nx >= 0 and nx <= 1 and ny >= 0 and ny <= 1 then
					pos:SetXY(nx, ny)
					local areas = C_MapExplorationInfo.GetExploredAreaIDsAtPosition(mapID, pos)
					if areas and #areas > 0 then SetCell(cont, gx, gy, dirty) end
				end
			end
			steps = steps + 1
			-- Bound downstream notifications too. Live sampling has its own dirty
			-- set, so it cannot flush a suspended import's cells as another continent.
			if steps % 64 == 0 then FlushChanged(cont, dirty) end
			coroutine.yield()
		end
	end
	FlushChanged(cont, dirty)
	return true
end
local function Enqueue(mapID, force)
	local imported = ns.db.imported[ns:GetCharacterKey()]
	if imported[mapID] then return end
	local version = generation
	ns.Background:Queue("exploration " .. version .. ":" .. mapID, function()
		if version ~= generation or imported[mapID] then return end
		if ImportMap(mapID, version, force) then
			imported[mapID] = true
			ns.Debug("imported exploration for map", mapID)
		end
	end)
end
function Exploration:QueueImportAll(force)
	if not force and not ns:GetSetting("importExploration") then return end
	if force then generation = generation + 1 end
	local version = generation
	ns.Background:Queue("exploration maps " .. version, function()
		local root = C_Map.GetFallbackWorldMapID and C_Map.GetFallbackWorldMapID() or 947
		local children = C_Map.GetMapChildrenInfo(root, Enum.UIMapType.Zone, true) or {}
		local imported = ns.db.imported[ns:GetCharacterKey()]
		local current = C_Map.GetBestMapForUnit("player")
		for _=1,8 do
			local info = current and C_Map.GetMapInfo(current)
			if not info or info.mapType <= Enum.UIMapType.Zone then break end
			current = info.parentMapID
		end
		if current then
			if force then imported[current] = nil end
			Enqueue(current, force)
			while ns.Background:Has("exploration " .. version .. ":" .. current) do
				if version ~= generation then return end
				coroutine.yield("frame")
			end
		end
		for _, info in ipairs(children) do
			if version ~= generation or (not force and not ns:GetSetting("importExploration")) then return end
			if force and info.mapID ~= current then imported[info.mapID] = nil end
			if not imported[info.mapID] then
				local rect = ns.GetMapRect(info.mapID)
				if rect and ns.TileData[rect.cont] then Enqueue(info.mapID, force) end
			end
			coroutine.yield()
		end
	end)
end
function Exploration:QueueImportCurrentZone()
	if not ns:GetSetting("importExploration") then return end
	local mapID = C_Map.GetBestMapForUnit("player")
	for _ = 1, 8 do
		if not mapID then break end
		local info = C_Map.GetMapInfo(mapID)
		if not info or info.mapType <= Enum.UIMapType.Zone then break end
		mapID = info.parentMapID
	end
	if mapID then Enqueue(mapID, false) end
end
