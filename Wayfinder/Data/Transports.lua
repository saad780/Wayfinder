-- Boats, zeppelins, the Deeprun Tram and fixed portals.
-- Like the built-in town data, each dock only appears once you have explored it.
-- Dock positions are taken from Carbonite All-in-One's camelot ZoneConnections
-- (GPL-3.0, https://github.com/IrcDirk/Carbonite-All-in-One-Retail-Classic); the
-- Booty Bay/Ratchet and Feathermoon docks are from Leatrix Maps' icon data.
-- Fields: kind, uiMapID, x%, y%, label, faction (0 neutral, 1 Alliance, 2 Horde)
local _, ns = ...

ns.TransportData = {
	-- Boats
	{ "boat", 1437, 5.03, 63.46, "Boat to Theramore Isle", 1 },
	{ "boat", 1445, 71.54, 56.37, "Boat to Menethil Harbor", 1 },
	{ "boat", 1437, 4.50, 57.70, "Boat to Auberdine", 1 },
	{ "boat", 1439, 32.39, 43.82, "Boat to Menethil Harbor", 1 },
	{ "boat", 1439, 33.18, 40.10, "Boat to Rut'theran Village", 1 },
	{ "boat", 1438, 54.87, 96.80, "Boat to Auberdine", 1 },
	{ "boat", 1439, 30.69, 41.12, "Boat to Stormwind", 1 },
	{ "boat", 1453, 22.42, 55.95, "Boat to Auberdine", 1 },
	{ "boat", 1444, 31.00, 39.80, "Boat to Feathermoon Stronghold", 1 },
	{ "boat", 1444, 43.30, 42.80, "Boat to the Forgotten Coast", 1 },
	{ "boat", 1434, 25.90, 73.10, "Boat to Ratchet", 0 },
	{ "boat", 1413, 63.70, 38.60, "Boat to Booty Bay", 0 },
	{ "boat", 1416, 12.70, 52.00, "Boat to Zephras Isle", 0 },
	{ "boat", 2521, 65.80, 83.40, "Boat to Alterac Mountains", 0 },
	-- Zeppelins
	{ "zeppelin", 1411, 50.88, 13.87, "Zeppelin to Undercity", 2 },
	{ "zeppelin", 1420, 60.70, 58.78, "Zeppelin to Orgrimmar", 2 },
	{ "zeppelin", 1411, 50.57, 12.64, "Zeppelin to Grom'gol Base Camp", 2 },
	{ "zeppelin", 1434, 31.37, 30.15, "Zeppelin to Orgrimmar", 2 },
	{ "zeppelin", 1420, 61.87, 59.07, "Zeppelin to Grom'gol Base Camp", 2 },
	{ "zeppelin", 1434, 31.56, 29.13, "Zeppelin to Undercity", 2 },
	{ "zeppelin", 1412, 34.30, 25.70, "Transport to Zephras Isle", 2 },
	{ "zeppelin", 2521, 57.90, 80.70, "Transport to Mulgore", 2 },
	-- Deeprun Tram
	{ "tram", 1455, 72.78, 50.24, "Deeprun Tram to Stormwind", 1 },
	{ "tram", 1453, 69.04, 30.85, "Deeprun Tram to Ironforge", 1 },
	-- Portals
	{ "portal", 1438, 55.94, 89.84, "Portal to Darnassus", 1 },
	{ "portal", 1457, 30.75, 41.39, "Portal to Rut'theran Village", 1 },
	{ "portal", 1416, 12.00, 56.20, "Portal to Stormwind", 1 },
	{ "portal", 1453, 50.00, 87.00, "Portal to Alterac Mountains", 1 },
}
