# OpenMap scroll controller

`WorldMap.lua` is adapted from OpenMap 0.5.0-beta's `Map/WorldMap.lua`, installed
locally when this integration was made. Copyright (c) 2026 OpenMap contributors.
Its MIT license is preserved in [LICENSE.txt](LICENSE.txt).

Upstream: https://www.curseforge.com/wow/addons/openmap

Wayfinder keeps the cursor-anchored wheel animation, continuous panning, host-map
switching, native canvas/pin integration, and gamepad/combat handling. It uses a
private namespace, its own renderer, its own waypoint gesture, and a zoom limit
computed from Wayfinder's 140-yard minimum terrain span. Upstream's settings,
menus, dungeon maps, routes, map painting and other modules are not bundled.

`ContinuousArt.lua` also adapts the MIT coordinate and host-layout routines from
OpenMap's `Map/Stitch.lua`. Map artwork itself comes from the client's APIs.

The small set of borrowed masks has separate provenance in
`Media/MapMasks/NOTICE.md`. `UPSTREAM-TEXTURES.md` preserves OpenMap's original
asset notice for reference; most of the assets it describes are **not** bundled.
