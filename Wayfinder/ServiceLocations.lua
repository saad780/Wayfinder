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
	if distance>25 then return false end
	local ai=type(a.id)=="number" and a.id>0 and a.id or nil
	local bi=type(b.id)=="number" and b.id>0 and b.id or nil
	if ai and bi then return ai==bi end
	local named=a.n and b.n and a.n~="Map icon" and b.n~="Map icon"
	if named and a.n~=b.n then return false end
	if named and (ai or bi) then return true end
	return distance<2
end
