# Wayfinder

A world map addon for **WoW: Forever** (interface 16001, client 1.60.1).

- **One continuous map.** Scroll from Azeroth through continents, neighbouring zones and cities without changing views. Drag across zone borders; the underlying map follows after you stop, keeping native quest and addon markers current. OpenMap is not required.
- **The map keeps zooming.** Outdoor map art blends into the minimap's own terrain textures, down to a 140-yard window: bright where you have explored, darkened where you haven't. The cursor stays anchored throughout the zoom.
- **Cities stay on the map.** Capital artwork appears in place as you zoom, including Orgrimmar, Thunder Bluff, Stormwind, Ironforge, Darnassus and Undercity. City maps stay above terrain, so underground cities show their streets instead of the surface above them.
- **Undercity defaults underground.** At close zoom, its full city plan replaces surface terrain while retaining the marker overlay. Services, quest markers and addon objects stay visible across that zoom step and layer changes. Use the compact layer selector near the map's top-right to swap between Undercity and the overworld without changing your zoom or position. Its stacked-layer glyph highlights the current floor. Returning to the area or reopening the map defaults to Undercity again.
- **It fills in as you go.** Everything your minimap shows while you walk, ride or fly is marked as explored. The areas your character discovered before you installed the addon are imported from the world map.
- **It remembers town services.** Vendors, repair, mailboxes, quest givers, flight masters, boats, zeppelins, the tram, auctioneers, bankers, innkeepers, class and profession trainers, weapon masters, stable masters, battlemasters and spirit healers all get icons. They appear on the world map and in the detail view.
- **Quest pickups mean available quests.** Each character sees only verified unaccepted offers. Accepting the last known offer, or confirming that an NPC has no offers left, removes their pickup marker; their other services remain. Old pickup markers stay hidden until verified again. Abandoned and repeatable quests return when the game confirms they are offered again.
- **Turn-ins stay visible up close.** Completed quests from the game's map retain golden question marks in the terrain detail view, above overlapping service icons, with tooltips and middle-click navigation.
- **Quests take priority.** An NPC's quest marker replaces their service marker while a quest is available or ready to turn in. Deep zoom combines native, addon and recorded copies into one marker per NPC, while keeping different nearby NPCs and objective locations separate. The corner minimap matches quest-giver identities, with a tight location fallback when identity is unavailable, so another merchant does not disappear when zooming out near a quest marker.
- **Live minimap turn-ins use the game's tracking.** Wayfinder suppresses Questie's extra fixed turn-in pins on the corner minimap when Blizzard supplies that quest's location. Native NPC movement stays under the client's control; Wayfinder adds no competing static marker. When the client supplies no quest location, the addon fallback remains. World-map turn-ins, pickups and objectives keep their existing behavior. Toggle this under `/wf` → **Live minimap**.
- **Service icons match Blizzard's.** Merchants use the game's vendor icon; other town services use Blizzard's tracking, gossip or map artwork in both map views.
- **Services stay visible on the corner minimap.** Blizzard draws its supported service types, keeping native movement, live NPC positions and undiscovered services intact. Wayfinder fills in other types and suppresses duplicate Questie service pins. Both tracking menus control the same categories and real native checkbox state. World-map and minimap addon service locations supply temporary fallbacks; these are never imported into saved locations. Quest and gathering tracking remain available.
- **Every icon type can be turned on or off.** Use the map button, the options panel, or `/wf show|hide <category>`.
- **It gets you there.** A button returns the map to where you are. Middle-click anywhere (or on any icon) to drop a waypoint, and a floating arrow points the way.
- **Addon icons keep zooming too.** Displayed Questie, RareScanner, SilverDragon and other map markers carry into the terrain detail view with their artwork and positions. Middle-click them on either view to navigate to their location. Their owning addon's filters still apply.

## Using it

| Where | What |
|---|---|
| World map | Scroll to zoom toward the cursor, drag to pan continuously across zones and cities. Outdoor terrain blends in at close zoom. |
| Left-click / right-click open map space | Zoom into the next map under the cursor / zoom out to its parent. Scrolling out also returns smoothly to the world view. |
| Layer selector near Undercity | Swap between the underground city and overworld. The current layer appears inside the control. |
| Map button (top-right of the map) | Turn icon types on or off, choose how unexplored terrain looks, open the detail view, open settings |
| Shift + left-drag the map button | Move it away from other addons' buttons. The position is saved across reloads and logins. Reset it in the button's menu or under `/wf` → **World map → Map menu button → Reset position**. |
| Locate button (top-left of the map, next to Blizzard's map pin button) | Switches the map to your zone and slides it to you. In the detail view it re-centres on you. |
| Middle-click the map, the detail view, or an icon | Sets a waypoint there. Middle-click the waypoint's pin to remove it. |
| Left-click a waypoint pin, or `/wf share` | Copies a `[Wayfinder:map:x:y:label]` location into your chat box. Send it directly or copy/paste the full text. Wayfinder 1.3.2+ makes it clickable in the recipient's chat; left-click sets their waypoint and arrow, replacing their current waypoint. Both players should update and `/reload`. |
| `/wf add <shared waypoint>` | Adds a full pasted `[Wayfinder:...]` location, including one copied from outside the game. |
| Waypoint arrow | A wider, raised arrow points toward the waypoint, with small distance/name text beneath it and a transparent background. It turns green when you're close. Drag it to move it; right-click it to remove the waypoint. Cleared automatically when you arrive. |
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

The continuous map uses Blizzard's native canvas and data providers. The terrain layer follows that canvas's exact position and scale, while city artwork and native markers remain above it. Terrain starts fading in at about 2,500 yards across the view and becomes fully visible by 1,400 yards; the closest zoom remains 140 yards across. Once panning settles, the underlying map switches to the visible zone or city without moving the view. Undercity's underground layer uses its full native city artwork and keeps the surface minimap hidden until you choose the overworld.

At terrain zoom, Wayfinder carries services, waypoints and other addons' map markers into a screen-sized overlay above the terrain. The same overlay stays above Undercity's underground city plan, with surface tiles released rather than built invisibly. The persistent markers take over drawing from the originals during this transition; zooming out restores the originals and their current alpha. Icons remain readable when the original canvas fades or scales them down; explicit owner visibility filters still apply. Duplicate quest and service markers at the same NPC combine, with quests above other icons. Tooltips and middle-click navigation remain available. Golden quest turn-ins retain their fallback above services. A separate detail view remains available when continuous mode is disabled under `/wf` (requires `/reload`).

Service markers in the detail overlay share Wayfinder's icon size and Blizzard artwork, including services mirrored from other addons. Offscreen pins are rejected before zone and artwork lookups. Visible artwork is cached, so an idle map does not rebuild every marker or recull terrain. Native pin changes request an update on the next frame; a lightweight compatibility poll catches addons that change their own artwork or visibility. Large spatial queries visit occupied buckets instead of scanning empty continent-sized grids. When Questie has a draw backlog, requests in the visible area go first (quests before services); other requests retain their order, and Questie's minimap queue and draw budget remain unchanged.

The detail overlay and corner minimap use the same service-location ordering and matching rules. Recorded locations are considered first, then temporary addon locations in a stable order. Both world-map and minimap service frames feed the local spatial index, so a canvas wrapper fading or disappearing during zoom does not remove its fallback. Questie's manual services use their service visibility rules rather than testing NPC IDs against quest filters. Only category copies at an identical source point combine beforehand, so a nearby intermediate point cannot swallow a distinct location. Different NPC IDs remain separate even when the NPCs stand close together.

Startup imports and existing Questie icon discovery share a cooperative 1 ms work budget per rendered frame, checked between individual operations. Taxi-map queries run at most once per frame; repeated flight nodes and unchanged records do not trigger repeated redraws. The current zone's exploration imports first. Icon changes coalesce into one minimap refresh per frame, and nearby services and quest givers are queried through a spatial index. Existing pins remain visible while background discovery proceeds. Client API calls cannot be interrupted, so an individual slow API call can exceed the budget.

For startup diagnostics, enable `/wf debug`, reload, and use `/wf debug timings` to see total and peak times for background slices, taxi API calls and minimap refreshes. Timings are collected only while debug is enabled and reset on reload. Use `/wf debug` again to turn diagnostics off.

The corner minimap discovers nearby icons and checks native quest data every 0.2 seconds. Native services stay under the client's renderer, with no duplicate Wayfinder projection. A separate lightweight frame update keeps additional cached world locations attached to the moving terrain, using direct player coordinates when available and following animated radius changes every frame. These textures permit subpixel positioning. Unchanged icons keep their artwork and anchors. A small surrounding buffer lets icons enter and leave the edge smoothly between data scans. Verified quest pickups retain a fallback when no native or addon marker supplies their location. Quest readiness is checked once per quest/map batch rather than for every duplicate pooled pin. Blizzard tracking changes synchronize through events and hooks, with a two-second fallback for other addons that omit notifications. Synchronization waits until the next frame so native tracking events cannot undo a click before its post-hook captures the choice. Quest, service and menu changes still request the next frame; native quest positions continue to be read live rather than cached across updates.

## Known limits

- **OpenMap.** With Wayfinder's continuous map enabled, Wayfinder takes control of the map for that session so two wheel/scroll controllers do not compete. OpenMap's saved settings are unchanged. You can disable OpenMap, or disable Wayfinder's continuous map and reload to use the older public-API compatibility mode with OpenMap 0.5.0-beta.

- **Cities.** City artwork can be enlarged continuously; it is limited to the resolution Blizzard provides. Outdoor minimap textures supply the deeper terrain detail. The separate detail view used with continuous mode disabled still excludes cities.
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
- `tools/make_arrow.py`: renders the standalone arrow's 128 perspective headings from project-defined geometry. See [the design and provenance notes](docs/arrow-design.md).
- `tools/make_fog.py`: redraws the 16 soft fog-edge pieces.
- `python tests/run_tests.py`: runs the test suite (needs `pip install lupa pillow`).

## Acknowledgements

Wayfinder is migrating to independently collected data. All existing built-in locations remain available until their replacements are verified; see [the collection workflow](data/README.md) and [remaining coverage](data/coverage.json).

Wayfinder still includes material copied from these projects:

- **[OpenMap](https://www.curseforge.com/wow/addons/openmap)** (0.5.0-beta, MIT code): the adapted continuous-map scroll controller and coordinate/layout routines. Copyright (c) 2026 OpenMap contributors; the original license is preserved in `Wayfinder/Vendor/OpenMap/LICENSE.txt`. Borrowed zone/city masks and their separate asset provenance are documented in `Wayfinder/Media/MapMasks/NOTICE.md`. No artist-drawn dungeon or gap artwork is included.
- **[Carbonite All-in-One](https://github.com/IrcDirk/Carbonite-All-in-One-Retail-Classic)** (GPL-3.0):
  - The legacy built-in town service locations in `Data/Seed.lua`, originally converted from its Forever guide data by the generator shipped with Wayfinder 1.3.3.
  - Most boat, zeppelin, tram and portal positions in `Data/Transports.lua`, from its zone connections.
- **Leatrix Maps**: the Booty Bay–Ratchet and Feathermoon dock positions in `Data/Transports.lua`.

Map geometry and explored-area textures come from client APIs. Overlay placement uses Wayfinder's own rectangle-clipping implementation; test map rectangles are synthetic. The minimap tile lookup comes from client WDT files, retrieved through wago.tools. Blizzard's game assets are not relicensed by Wayfinder.

## License

GPL-3.0, because Wayfinder includes Carbonite's GPL-3.0 data. See `Wayfinder/LICENSE.txt`.
