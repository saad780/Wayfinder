-- Recorded locations: storage, spatial index, and merging of repeated sightings.
--
-- A record (saved in WayfinderDB.pois, keyed by record.k):
--   k     key                        kind  "npc" | "obj" | "taxi"
--   id    npc ID (npc records)       n     name           s   subtitle
--   cats  { [categoryID] = true }    cls   class token (class trainers)
--   c     continent (instance) ID    x, y  world yards (north, west)
--   m     uiMapID it was seen on     a     accuracy radius in yards
--   w     accumulated position weight f     faction: 0 neutral, 1 Alliance, 2 Horde
--   sub   transport kind             t     last seen (time())
local _, ns = ...

local Database = ns:NewModule("Database")

local floor = math.floor
local GRID = 250 -- yards per spatial bucket

-- Sightings of the same NPC ID closer than this are the same spawn.
local SAME_SPAWN_YARDS = 60
-- Unnamed objects (mailboxes) closer than this are the same object.
local SAME_OBJECT_YARDS = 12

local buckets = {} -- [cont][bucketKey] = { record = true }
local bucketOf = setmetatable({}, { __mode = "k" }) -- record -> its bucket key

local function BucketKey(wx, wy)
	return (floor(wx / GRID) + 200) * 1000 + (floor(wy / GRID) + 200)
end

local function IndexAdd(rec)
	local cont = buckets[rec.c]
	if not cont then
		cont = {}
		buckets[rec.c] = cont
	end
	local key = BucketKey(rec.x, rec.y)
	local bucket = cont[key]
	if not bucket then
		bucket = {}
		cont[key] = bucket
	end
	bucket[rec] = true
	bucketOf[rec] = key
end

local function IndexRemove(rec)
	local cont = buckets[rec.c]
	local key = bucketOf[rec]
	local bucket = cont and key and cont[key]
	if bucket then
		bucket[rec] = nil
	end
	bucketOf[rec] = nil
end

function Database:Rebuild()
	wipe(buckets)
	for key, rec in pairs(ns.db.pois) do
		if type(rec) == "table" and rec.c and rec.x and rec.y and type(rec.cats) == "table" then
			rec.k = key
			IndexAdd(rec)
		else
			ns.db.pois[key] = nil
		end
	end
end

function Database:OnInitialize()
	self:Rebuild()
end

-- Calls fn(record) for every record on a continent inside the world-space box.
function Database:Query(cont, minX, maxX, minY, maxY, fn)
	local contBuckets = buckets[cont]
	if not contBuckets then
		return
	end
	for bx = floor(minX / GRID), floor(maxX / GRID) do
		for by = floor(minY / GRID), floor(maxY / GRID) do
			local bucket = contBuckets[(bx + 200) * 1000 + (by + 200)]
			if bucket then
				for rec in pairs(bucket) do
					if rec.x >= minX and rec.x <= maxX and rec.y >= minY and rec.y <= maxY then
						fn(rec)
					end
				end
			end
		end
	end
end

-- Nearest record within radius that satisfies predicate(record).
function Database:FindNearest(cont, wx, wy, radius, predicate)
	local best, bestDist
	self:Query(cont, wx - radius, wx + radius, wy - radius, wy + radius, function(rec)
		local d = ns.Distance(wx, wy, rec.x, rec.y)
		if d <= radius and (not bestDist or d < bestDist) and (not predicate or predicate(rec)) then
			best, bestDist = rec, d
		end
	end)
	return best, bestDist
end

local function NewKey(prefix, wx, wy)
	local base = ("%s@%d,%d"):format(prefix, floor(wx + 0.5), floor(wy + 0.5))
	local key, n = base, 1
	while ns.db.pois[key] do
		n = n + 1
		key = base .. "#" .. n
	end
	return key
end

local function Insert(rec)
	ns.db.pois[rec.k] = rec
	IndexAdd(rec)
	return rec
end

-- Moves or refines a record's position from a new observation.
local function MergePosition(rec, wx, wy, accuracy)
	accuracy = math.max(accuracy or 30, 1)
	local weight = 1 / (accuracy * accuracy)
	if accuracy < (rec.a or 999) * 0.7 then
		-- Clearly better observation: take it.
		IndexRemove(rec)
		rec.x, rec.y, rec.a, rec.w = wx, wy, accuracy, weight
		IndexAdd(rec)
	elseif accuracy <= (rec.a or 999) * 1.5 then
		-- Comparable observation: weighted average, converging on the true spot.
		local w = rec.w or (1 / ((rec.a or accuracy) ^ 2))
		IndexRemove(rec)
		rec.x = (rec.x * w + wx * weight) / (w + weight)
		rec.y = (rec.y * w + wy * weight) / (w + weight)
		rec.w = w + weight
		rec.a = math.min(rec.a or accuracy, accuracy)
		IndexAdd(rec)
	end
end

local function MergeCats(rec, cats)
	if cats then
		for catID in pairs(cats) do
			rec.cats[catID] = true
		end
	end
end

--[[ Records an NPC.
info = {
	npcID, name, title, cats (set), class, faction,
	cont, wx, wy, mapID, accuracy, source ("talk" | "sight" | "guard")
} ]]
function Database:RecordNPC(info)
	if not (info.cont and info.wx and info.wy) then
		return nil
	end
	if info.source then ns.Observations:Capture(info, info.source) end
	local rec
	if info.npcID then
		rec = self:FindNearest(info.cont, info.wx, info.wy, SAME_SPAWN_YARDS + (info.accuracy or 0), function(r)
			return r.kind == "npc" and r.id == info.npcID
		end)
	end
	if not rec and info.name then
		rec = self:FindNearest(info.cont, info.wx, info.wy, 30 + (info.accuracy or 0), function(r)
			return r.kind == "npc" and r.n == info.name and (not r.id or not info.npcID)
		end)
	end
	-- A spot a guard pointed out and the NPC standing there are the same record.
	local fromGuard = info.source == "guard"
	if not rec and info.cats then
		rec = self:FindNearest(info.cont, info.wx, info.wy, 20 + (info.accuracy or 0), function(r)
			if r.kind ~= "npc" or not (fromGuard or (r.guard and not r.id)) then
				return false
			end
			for catID in pairs(info.cats) do
				if r.cats[catID] then
					return true
				end
			end
			return false
		end)
	end

	local isNew = not rec
	if isNew then
		rec = Insert({
			k = NewKey("n" .. (info.npcID or 0), info.wx, info.wy),
			kind = "npc",
			id = info.npcID,
			cats = {},
			c = info.cont,
			x = info.wx,
			y = info.wy,
			a = info.accuracy or 30,
			w = 1 / ((info.accuracy or 30) ^ 2),
		})
	else
		MergePosition(rec, info.wx, info.wy, info.accuracy)
	end

	rec.id = rec.id or info.npcID
	if info.name and not (fromGuard and rec.n) then rec.n = info.name end
	if info.title then rec.s = info.title end
	if info.class then rec.cls = info.class end
	if info.faction then rec.f = info.faction end
	if info.mapID then rec.m = info.mapID end
	if info.source == "talk" then rec.talked = true end
	MergeCats(rec, info.cats)
	rec.t = time()

	ns:Fire("POI_UPDATED", rec, isNew)
	return rec, isNew
end

--[[ Records an object with no identity of its own (mailboxes).
info = { cat, name, cont, wx, wy, mapID, accuracy } ]]
function Database:RecordObject(info)
	if not (info.cont and info.wx and info.wy and info.cat) then
		return nil
	end
	if info.source then ns.Observations:Capture(info, info.source) end
	local rec = self:FindNearest(info.cont, info.wx, info.wy, SAME_OBJECT_YARDS, function(r)
		return r.kind == "obj" and r.cats[info.cat]
	end)
	local isNew = not rec
	if isNew then
		rec = Insert({
			k = NewKey("o" .. info.cat, info.wx, info.wy),
			kind = "obj",
			cats = { [info.cat] = true },
			c = info.cont,
			x = info.wx,
			y = info.wy,
			a = info.accuracy or 5,
			w = 1 / ((info.accuracy or 5) ^ 2),
		})
	else
		MergePosition(rec, info.wx, info.wy, info.accuracy)
	end
	rec.n = info.name or rec.n
	rec.m = info.mapID or rec.m
	rec.f = info.faction or rec.f
	rec.t = time()
	ns:Fire("POI_UPDATED", rec, isNew)
	return rec, isNew
end

--[[ Records a flight point the character knows.
info = { nodeID, name, faction, cont, wx, wy, mapID } ]]
function Database:RecordTaxi(info)
	local key = "t" .. info.nodeID
	local rec = ns.db.pois[key]
	local isNew = not rec
	if isNew then
		-- A flight master may already have been recorded by talking to them.
		local near = self:FindNearest(info.cont, info.wx, info.wy, 40, function(r)
			return r.cats.flight and r.kind == "npc"
		end)
		if near then
			near.taxi = info.nodeID
			if not near.n then near.n = info.name end
			return near, false
		end
		rec = Insert({
			k = key,
			kind = "taxi",
			cats = { flight = true },
			c = info.cont,
			x = info.wx,
			y = info.wy,
			a = 10,
			w = 0.01,
		})
	end
	rec.n = info.name
	rec.f = info.faction
	rec.m = info.mapID
	ns:Fire("POI_UPDATED", rec, isNew)
	return rec, isNew
end

function Database:Remove(rec)
	if not rec or not rec.k or ns.db.pois[rec.k] ~= rec then
		return
	end
	IndexRemove(rec)
	ns.db.pois[rec.k] = nil
	ns:Fire("POI_REMOVED", rec)
end
