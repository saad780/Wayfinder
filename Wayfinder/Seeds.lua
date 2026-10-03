-- Built-in locations (town services and transports) that are revealed by exploring.
--
-- A built-in location only shows once the terrain cell it sits in has been explored,
-- which is the moment the minimap would have shown its icon. Anything you have
-- recorded yourself within a few yards replaces it.
local _, ns = ...

local Seeds = ns:NewModule("Seeds")

local floor = math.floor
local GRID = 250
local SAME_SPOT_YARDS = 8     -- several spawns at one counter collapse into one icon
local SUPERSEDE_YARDS = 25    -- a recorded location this close replaces a built-in one

local buckets = {}
local all = {}
local supersedeVersion = 0

local function BucketKey(wx, wy)
	return (floor(wx / GRID) + 200) * 1000 + (floor(wy / GRID) + 200)
end

local function Query(cont, minX, maxX, minY, maxY, fn)
	local contBuckets = buckets[cont]
	if not contBuckets then
		return
	end
	for bx = floor(minX / GRID), floor(maxX / GRID) do
		for by = floor(minY / GRID), floor(maxY / GRID) do
			local bucket = contBuckets[(bx + 200) * 1000 + (by + 200)]
			if bucket then
				for i = 1, #bucket do
					local seed = bucket[i]
					if seed.x >= minX and seed.x <= maxX and seed.y >= minY and seed.y <= maxY then
						fn(seed)
					end
				end
			end
		end
	end
end

local function NearDuplicate(cont, wx, wy, catID)
	local found = false
	Query(cont, wx - SAME_SPOT_YARDS, wx + SAME_SPOT_YARDS, wy - SAME_SPOT_YARDS, wy + SAME_SPOT_YARDS, function(seed)
		if seed.cats[catID] and ns.Distance(wx, wy, seed.x, seed.y) <= SAME_SPOT_YARDS then
			found = true
		end
	end)
	return found
end

local function Add(seed)
	local contBuckets = buckets[seed.c]
	if not contBuckets then
		contBuckets = {}
		buckets[seed.c] = contBuckets
	end
	local key = BucketKey(seed.x, seed.y)
	local bucket = contBuckets[key]
	if not bucket then
		bucket = {}
		contBuckets[key] = bucket
	end
	bucket[#bucket + 1] = seed
	all[#all + 1] = seed
end

local function MakeSeed(catID, mapID, x, y, faction, name, extra)
	local cont, wx, wy = ns.MapToWorld(mapID, x / 100, y / 100)
	if not cont or NearDuplicate(cont, wx, wy, catID) then
		return
	end
	local seed = {
		k = ("s:%s:%d:%.1f:%.1f"):format(catID, mapID, x, y),
		kind = "seed",
		seed = true,
		cats = { [catID] = true },
		n = name,
		c = cont,
		x = wx,
		y = wy,
		m = mapID,
		f = faction,
		a = 5,
	}
	if extra then
		for k, v in pairs(extra) do
			seed[k] = v
		end
	end
	Add(seed)
end

function Seeds:Build()
	wipe(buckets)
	wipe(all)
	for _, entry in ipairs(ns.SeedData or {}) do
		local pts, names = entry.pts, entry.names
		for i = 1, #pts, 4 do
			local name = names and names[(i - 1) / 4 + 1] or entry.name
			MakeSeed(entry.cat, pts[i], pts[i + 1], pts[i + 2], pts[i + 3], name,
				{ cls = entry.class, builtin = true, s = names and entry.name or nil })
		end
	end
	for _, t in ipairs(ns.TransportData or {}) do
		MakeSeed("transport", t[2], t[3], t[4], t[6], t[5], { sub = t[1] })
	end
	ns.Debug(#all, "built-in locations loaded")
end

function Seeds:OnLogin()
	self:Build()
	local function Invalidate()
		supersedeVersion = supersedeVersion + 1
	end
	ns:On("POI_UPDATED", Invalidate)
	ns:On("POI_REMOVED", Invalidate)
	ns:On("DATA_CHANGED", Invalidate)
end

-- Whether a recorded location already covers this built-in one.
local function IsSuperseded(seed)
	if seed._v == supersedeVersion then
		return seed._sup
	end
	local catID = next(seed.cats)
	local rec = ns.Database:FindNearest(seed.c, seed.x, seed.y, SUPERSEDE_YARDS, function(r)
		return r.cats[catID]
	end)
	seed._v, seed._sup = supersedeVersion, rec ~= nil
	return seed._sup
end

function Seeds:IsRevealed(seed)
	if ns.db.hidden[seed.k] then
		return false
	end
	if seed.builtin and not ns:GetSetting("useSeedData") then
		return false
	end
	if IsSuperseded(seed) then
		return false
	end
	return ns.Exploration:IsExplored(seed.c, seed.x, seed.y)
end

-- Calls fn(seed) for every revealed built-in location in the box.
function Seeds:Query(cont, minX, maxX, minY, maxY, fn)
	Query(cont, minX, maxX, minY, maxY, function(seed)
		if self:IsRevealed(seed) then
			fn(seed)
		end
	end)
end

function Seeds:Hide(seed)
	ns.db.hidden[seed.k] = true
	ns:Fire("POI_REMOVED", seed)
end

function Seeds:CountRevealed()
	local n = 0
	for i = 1, #all do
		if self:IsRevealed(all[i]) then
			n = n + 1
		end
	end
	return n
end
