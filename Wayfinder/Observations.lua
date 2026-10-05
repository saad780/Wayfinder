-- Independent measurements, kept apart from imported seeds and merged POIs.
local _, ns = ...
local Observations = ns:NewModule("Observations")
local methods = { talk = true, sight = true, guard = true, mailbox = true,
	taxi_api = true, transport_manual = true }

local function Number(v)
	return ns.Readable(v) and type(v) == "number" and v == v and math.abs(v) < math.huge
end

function Observations:Capture(info, method)
	if not methods[method] or not info or not Number(info.mapID) or
		not Number(info.wx) or not Number(info.wy) or not Number(info.accuracy) or info.accuracy < 0 then return end
	local rect = ns.GetMapRect(info.mapID)
	if not rect or rect.cont ~= info.cont then return end
	local x, y = ns.WorldToMapRect(rect, info.wx, info.wy)
	if x < 0 or x > 1 or y < 0 or y > 1 then return end
	local build = GetBuildInfo and select(2, GetBuildInfo()) or "unknown"
	local version = GetBuildInfo and GetBuildInfo() or "unknown"
	local store = ns.db.observations
	for cat in pairs(info.cats or (info.cat and { [info.cat] = true }) or {}) do
		if ns.CategoryByID[cat] then
			local identity = info.npcID or info.nodeID or info.name or cat
			local key = ("%s:%s:%s:%d:%d:%d"):format(method, cat, tostring(identity), info.mapID,
				math.floor(info.wx / 25), math.floor(info.wy / 25))
			local previous = store[key]
			if not previous or info.accuracy <= previous.accuracy then
				store[key] = { schema = 1, method = method, build = tostring(build), version = version,
					observedAt = time(), mapID = info.mapID, cont = info.cont, wx = info.wx, wy = info.wy,
					x = x * 100, y = y * 100, accuracy = info.accuracy, cat = cat,
					name = info.name, title = info.title, class = info.class, faction = info.faction or 0,
					npcID = info.npcID, nodeID = info.nodeID, kind = info.kind,
					-- A copied rectangle makes offline conversion/review reproducible.
					rect = { cont = rect.cont, top = rect.top, left = rect.left,
						width = rect.width, height = rect.height } }
			end
		end
	end
end

function Observations:SurveyTransport(input)
	local kind, faction, label = input:match("^(%a+)%s+([012])%s+(.+)$")
	if not ({ boat = true, zeppelin = true, tram = true, portal = true })[kind] then
		ns.Print("Usage: /wf survey transport <boat|zeppelin|tram|portal> <0 neutral|1 Alliance|2 Horde> <route label>")
		return
	end
	local cont, wx, wy, mapID = ns.GetPlayerWorld()
	if not cont then ns.Print("Position unavailable here.") return end
	self:Capture({ cat = "transport", cont = cont, wx = wx, wy = wy, mapID = mapID,
		accuracy = 4, faction = tonumber(faction), name = label, kind = kind }, "transport_manual")
	ns.Print("Surveyed " .. label .. ". Stand at the endpoint when collecting a route.")
end
