-- One matching policy for service locations in both map views. Choose recorded
-- anchors before grouping temporary addon locations; proximity is not transitive.
local _, ns = ...
local Locations = ns:NewModule("ServiceLocations")

function Locations:Less(a,b)
	local ai,bi=a.id or 0,b.id or 0
	if ai~=bi then return ai<bi end
	if a.x~=b.x then return a.x<b.x end
	if a.y~=b.y then return a.y<b.y end
	local ac,bc=ns.CategoryByID[a.cat],ns.CategoryByID[b.cat]
	local ao,bo=ac and ac.order or 100,bc and bc.order or 100
	if ao~=bo then return ao<bo end
	return (a.n or "")<(b.n or "")
end

function Locations:Same(a,b)
	local distance=ns.Distance(a.x,a.y,b.x,b.y)
	if a.c and b.c and a.c ~= b.c then return false end
	local ai=type(a.id)=="number" and a.id>0 and a.id or nil
	local bi=type(b.id)=="number" and b.id>0 and b.id or nil
	local af = a.cat == "flight" or a.cats and a.cats.flight
	local bf = b.cat == "flight" or b.cats and b.cats.flight
	-- Taxi-node names describe a town, while its NPC has a personal name.
	if af and bf and distance <= 40 and not (ai and bi) and
		(a.kind == "taxi" or b.kind == "taxi" or a.seed or b.seed) then return true end
	if distance>25 then return false end
	if ai and bi then return ai==bi end
	local shared=a.cat and a.cat==b.cat
	for cat in pairs(a.cats or {}) do if b.cats and b.cats[cat] then shared=true;break end end
	-- Built-in service labels identify a counter, rather than an NPC.
	if a.seed or b.seed then
		if shared then return true end
	end
	local named=a.n and b.n and a.n~="Map icon" and b.n~="Map icon"
	if named and a.n~=b.n then return false end
	if named and (ai or bi) then return true end
	return shared and distance<2 or false
end

-- Service observations often share the player's exact position. Keep the
-- clickable service beside the player arrow, preserving its real coordinates.
function Locations:PlayerOffset(x,y,px,py,clearance,cat)
	if cat~="bank" and cat~="auction" then return 0,0 end
	local dx,dy=x-px,y-py
	local distance=(dx*dx+dy*dy)^.5
	if distance>=clearance then return 0,0 end
	local targetX=(cat=="bank" and -1 or 1)*math.sqrt(math.max(0,clearance*clearance-dy*dy))
	return targetX-dx,0
end

-- Nearby bankers/auctioneers share one readable icon at wider zooms.
function Locations:Overlaps(a, b, pixels)
	return a.cat == b.cat and (a.cat == "bank" or a.cat == "auction" or a.cat == "flight")
		and (not a.c or not b.c or a.c == b.c)
		and ns.Distance(a.x,a.y,b.x,b.y) <= 60 and pixels < 14
end

function Locations:Select(entries)
	local function Quality(e)
		return e.rec.seed and 1 or e.rec.ephemeral and 2 or e.rec.kind == "taxi" and 3 or 4
	end
	table.sort(entries, function(a,b)
		local aq,bq = Quality(a),Quality(b)
		if aq ~= bq then return aq > bq end
		return self:Less(a,b)
	end)
	local kept, buckets = {}, {}
	local function Bucket(entry, dx, dy)
		return (entry.c or 0) .. ":" .. (math.floor(entry.x/60)+(dx or 0)) .. ":" .. (math.floor(entry.y/60)+(dy or 0))
	end
	for _, entry in ipairs(entries) do
		local duplicate
		if entry.cat ~= "quest" then
			for dx=-1,1 do for dy=-1,1 do
				for _, prior in ipairs(buckets[Bucket(entry,dx,dy)] or {}) do
					if self:Same(entry,prior) or self:Overlaps(entry,prior,
						ns.Distance(entry.screenX,entry.screenY,prior.screenX,prior.screenY)) then duplicate=true; break end
				end
			end end
		end
		if not duplicate then
			kept[#kept+1] = entry
			if entry.cat ~= "quest" then
				local key = Bucket(entry)
				buckets[key] = buckets[key] or {}
				buckets[key][#buckets[key]+1] = entry
			end
		end
	end
	return kept
end
