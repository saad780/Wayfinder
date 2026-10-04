# Wayfinder

A world map addon for **WoW: Forever** (interface 16001, client 1.60.1).

- **The map keeps zooming.** Zoom the world map in as far as it goes, then scroll in again. The view continues into the minimap's own terrain textures: bright where you have explored, darkened where you haven't.
- **It fills in as you go.** Everything your minimap shows while you walk, ride or fly is marked as explored. The areas your character discovered before you installed the addon are imported from the world map.
- **It remembers town services.** Vendors, repair, mailboxes, quest givers, flight masters, boats, zeppelins, the tram, auctioneers, bankers, innkeepers, class and profession trainers, weapon masters, stable masters, battlemasters and spirit healers all get icons. They appear on the world map and in the detail view.
- **Quest markers mean available pickups.** Each character sees only verified unaccepted quests. Accepting the last known offer, or confirming that an NPC has no offers left, removes their quest marker; their other services remain. Old quest markers stay hidden until verified again. Abandoned and repeatable quests return when the game confirms they are offered again.
- **Every icon type can be turned on or off.** Use the map button, the options panel, or `/wf show|hide <category>`.
- **It gets you there.** A button returns the map to where you are. Middle-click anywhere (or on any icon) to drop a waypoint, and a floating arrow points the way.

## Using it

| Where | What |
|---|---|
| World map, fully zoomed in, scroll up | Opens the detail view at exactly what the map was showing |
| Detail view | Scroll to zoom toward the cursor, drag to pan. Right-click, **Back to map**, or zoom all the way out to return. |
| Map button (top-right of the map) | Turn icon types on or off, choose how unexplored terrain looks, open the detail view, open settings |
| Locate button (top-left of the map, next to Blizzard's map pin button) | Switches the map to your zone and slides it to you. In the detail view it re-centres on you. |
| Middle-click the map, the detail view, or an icon | Sets a waypoint there. Middle-click the waypoint's pin to remove it. |
| Left-click a waypoint pin, or `/wf share` | Copies a `[Wayfinder:map:x:y:label]` location into your chat box. Send it directly or copy/paste the full text. Wayfinder 1.3.2+ makes it clickable in the recipient's chat; left-click sets their waypoint and arrow, replacing their current waypoint. Both players should update and `/reload`. |
| `/wf add <shared waypoint>` | Adds a full pasted `[Wayfinder:...]` location, including one copied from outside the game. |
| Waypoint arrow | Points toward the waypoint and shows the distance; turns green when you're close. Drag it to move it; right-click it to remove the waypoint. Cleared automatically when you arrive. |
| Shift-click an icon | Remove it (for example, a vendor who moved) |
| `/wf` | Options. `/wf stats`, `/wf reveal [hide\|dim\|show]`, `/wf show all`, `/wf hide mailbox`, `/wf way <x> <y> [label]`, `/wf clear`, `/wf arrow`, `/wf import`, `/wf reset pois` |

Options are also under *Esc → Options → AddOns → Wayfinder*.

## How locations are found

1. **Talking to an NPC records them exactly**, because you are within a few yards when their window opens. The window type says what they are: merchant (plus repair, and food, ammo or reagents depending on what they sell), trainer (class or profession), banker, flight master, innkeeper, auctioneer, stable master, battlemaster, spirit healer, or quest giver. Opening a mailbox records the mailbox.
2. **Mousing over or targeting a service NPC records them approximately.** This covers anyone whose title names a service, such as `<Banker>` or `<Weapon Merchant>`. Range is estimated as within about 10 or 28 yards, and later, closer sightings refine the spot. Approximate icons are drawn slightly faded.
3. **Asking a city guard for directions records the place the guard marks.** Ask about "The bank", "Class Trainer → Warrior" and so on.
4. **Flight paths your character already knows** are imported at login.
5. **Built-in town services** (mailboxes, bankers, innkeepers, trainers, flight masters) and every boat, zeppelin, tram and portal are included. Each one stays hidden until the spot is explored, which is the moment your minimap would have shown it. Anything you record yourself replaces the built-in entry.

No NPC identity is read while the client marks it as restricted (12.x "secret values"). Nothing is recorded in combat.

## How the detail view works

Forever's minimap terrain consists of 512×512 textures, one per 533⅓-yard map tile. They can only be loaded by FileDataID, so `Data/Tiles.lua` holds the ID of every tile in Eastern Kingdoms, Kalimdor, Zephras Isle and the Darkspear Islands. The table was read from the client's own WDT files.

Each tile is split into 16×16 cells of about 33 yards, and the cells you have explored are drawn at full brightness. The **Unexplored terrain** setting decides what happens everywhere else:

- **Darkened** (default): the real terrain under a soft fog of war. Edges fade over about 33 yards and corners are rounded (marching squares, see `tools/make_fog.py`). Fog strength is adjustable in Options.
- **Hidden**: nothing is drawn, so the zone's normal map art shows through.
- **Shown**: the real terrain at full brightness.

The detail view is a separate frame laid over the map. Blizzard's map state is never modified, apart from panning it to where you were looking when you leave, so the addon does not taint the world map.

## Known limits

- **Cities.** City maps don't zoom into the detail view: the minimap terrain under a city shows the ground outside it (inside Ironforge and Undercity, the ground above), not the city itself.
- **Mouseover positions** are only as good as the distance estimate until you get close or talk to the NPC.
- **Testing.** Changes are checked against a model of the game's API (see `tests/`), built from Blizzard's UI source for build 70170, before they reach the client. If anything misbehaves in game, `/wf debug` turns on extra output.

## After a Forever patch

Tile IDs can change between builds. To regenerate the table:

```
python tools/build_tiles.py 1.60.2.xxxxx
```

The script downloads the new build's WDT files from wago.tools. The other tools:

- `tools/build_seed.py`: builds reviewed independent replacements and a report of remaining imported locations.
- `tools/export_observations.py`: exports new Wayfinder measurements from SavedVariables for review.
- `tools/make_icons.py`: redraws the addon's own icons.
- `tools/make_fog.py`: redraws the 16 soft fog-edge pieces.
- `python tests/run_tests.py`: runs the test suite (needs `pip install lupa`).

## Acknowledgements

Wayfinder is migrating to independently collected data. All existing built-in locations remain available until their replacements are verified; see [the collection workflow](data/README.md) and [remaining coverage](data/coverage.json).

Wayfinder still includes material copied from these projects:

- **[Carbonite All-in-One](https://github.com/IrcDirk/Carbonite-All-in-One-Retail-Classic)** (GPL-3.0):
  - The legacy built-in town service locations in `Data/Seed.lua`, originally converted from its Forever guide data by the generator shipped with Wayfinder 1.3.3.
  - Most boat, zeppelin, tram and portal positions in `Data/Transports.lua`, from its zone connections.
- **Leatrix Maps**: the Booty Bay–Ratchet and Feathermoon dock positions in `Data/Transports.lua`.

Map geometry and explored-area textures come from client APIs. Overlay placement uses Wayfinder's own rectangle-clipping implementation; test map rectangles are synthetic. The minimap tile lookup comes from client WDT files, retrieved through wago.tools. Blizzard's game assets are not relicensed by Wayfinder.

## License

GPL-3.0, because Wayfinder includes Carbonite's GPL-3.0 data. See `Wayfinder/LICENSE.txt`.
