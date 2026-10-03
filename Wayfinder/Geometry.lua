-- Coordinate conversions between uiMap positions, world yards and the minimap tile grid.
--
-- World coordinates follow the game: wx grows north, wy grows west, both in yards,
-- per continent (instance ID). The detail view works on a flat "plane" with
-- px = -wy (east) and py = -wx (south) so it maps directly onto screen axes.
--
-- Terrain is a 64x64 grid of ADT tiles, each 1600/3 yards across. Tile column
-- A = floor(32 - wy / TILE) (west to east), row B = floor(32 - wx / TILE)
-- (north to south); the minimap texture for a tile is world/minimaps/<dir>/mapA_B.
local _, ns = ...

local floor = math.floor

local TILE = 1600 / 3
local CELLS = 16 -- exploration resolution: 16x16 cells per tile, 33.3 yards each
local CELL = TILE / CELLS

ns.TILE = TILE
ns.CELLS = CELLS
ns.CELL = CELL

---------------------------------------------------------------------------
-- uiMap rectangles in world space
---------------------------------------------------------------------------
local rectCache = {}

local function WorldPos(mapID, x, y)
	local ok, continentID, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
	if ok and continentID and pos then
		local wx, wy = pos:GetXY()
		return continentID, wx, wy
	end
end

-- Returns { cont, top, left, width, height } where top/left are the world
-- coordinates of the map's top-left corner and width/height are in yards,
-- or nil for maps without a world position (cosmic, world, some instances).
function ns.GetMapRect(mapID)
	if not mapID then
		return nil
	end
	local rect = rectCache[mapID]
	if rect ~= nil then
		return rect or nil
	end
	rect = false
	-- Sample two interior points and extrapolate: corners can fall outside the
	-- area a map is assigned to, interior points never do.
	local c1, wx1, wy1 = WorldPos(mapID, 0.25, 0.25)
	local c2, wx2, wy2 = WorldPos(mapID, 0.75, 0.75)
	if c1 and c2 and c1 == c2 and wx1 ~= wx2 and wy1 ~= wy2 then
		local height = (wx1 - wx2) * 2
		local width = (wy1 - wy2) * 2
		if width > 0 and height > 0 then
			rect = {
				cont = c1,
				top = wx1 + height * 0.25,
				left = wy1 + width * 0.25,
				width = width,
				height = height,
			}
		end
	end
	rectCache[mapID] = rect
	return rect or nil
end

function ns.MapToWorld(mapID, x, y)
	local rect = ns.GetMapRect(mapID)
	if not rect then
		return nil
	end
	return rect.cont, rect.top - y * rect.height, rect.left - x * rect.width
end

-- Normalized map position of a world point (may be outside 0..1).
function ns.WorldToMapRect(rect, wx, wy)
	return (rect.left - wy) / rect.width, (rect.top - wx) / rect.height
end

---------------------------------------------------------------------------
-- Player position
---------------------------------------------------------------------------
-- Returns continentID, wx, wy, uiMapID, mapX, mapY or nil (instances, loading).
function ns.GetPlayerWorld()
	local mapID = C_Map.GetBestMapForUnit("player")
	if not mapID then
		return nil
	end
	local pos = C_Map.GetPlayerMapPosition(mapID, "player")
	if not pos then
		return nil
	end
	local x, y = pos:GetXY()
	if not x or not y or (x == 0 and y == 0) then
		return nil
	end
	local cont, wx, wy = ns.MapToWorld(mapID, x, y)
	if not cont then
		return nil
	end
	return cont, wx, wy, mapID, x, y
end

---------------------------------------------------------------------------
-- Tile grid
---------------------------------------------------------------------------
function ns.WorldToTile(wx, wy)
	local fa = 32 - wy / TILE
	local fb = 32 - wx / TILE
	local col, row = floor(fa), floor(fb)
	return col, row, fa - col, fb - row
end

function ns.TileKey(col, row)
	return col * 100 + row
end

function ns.SplitTileKey(key)
	return floor(key / 100), key % 100
end

-- Plane coordinates of a tile's north-west corner.
function ns.TileOrigin(col, row)
	return (col - 32) * TILE, (row - 32) * TILE
end

function ns.WorldToPlane(wx, wy)
	return -wy, -wx
end

function ns.PlaneToWorld(px, py)
	return -py, -px
end

-- Tile column/row and cell indices (0-based) containing a plane point.
function ns.PlaneToCell(px, py)
	local tx = px / TILE + 32
	local ty = py / TILE + 32
	local col, row = floor(tx), floor(ty)
	local cx = floor((tx - col) * CELLS)
	local cy = floor((ty - row) * CELLS)
	if cx >= CELLS then cx = CELLS - 1 end
	if cy >= CELLS then cy = CELLS - 1 end
	return col, row, cx, cy
end

-- Yards between two world points on the same continent.
function ns.Distance(wx1, wy1, wx2, wy2)
	local dx, dy = wx1 - wx2, wy1 - wy2
	return (dx * dx + dy * dy) ^ 0.5
end
