# Map mask provenance

These files were copied from the locally installed OpenMap 0.5.0-beta:

- `MapTerritory/*.tga`: masks traced from Blizzard's zone-map shapes. Upstream
  generators: `tools/map-grade` and `tools/map-preview`.
- `MapCityMask/1454.tga`, `1456.tga`, `1458.tga`: Orgrimmar, Thunder Bluff and
  Undercity masks traced from Blizzard's city artwork. Upstream generator:
  `tools/map-preview/banners.py`.
- `MapFeatherRound.tga`: generated edge mask, containing no game artwork.
  Upstream generator: `tools/map-textures/make.py`.

Blizzard-derived shapes/art remain Blizzard Entertainment's; OpenMap's MIT code
license and Wayfinder's GPL license do not relicense Blizzard's assets. OpenMap
contributors are credited for the tracing and generation work. OpenMap's code
license is retained in `Vendor/OpenMap/LICENSE.txt`, and its original full asset
notice is retained in `Vendor/OpenMap/UPSTREAM-TEXTURES.md`.

No artist-drawn dungeon maps, gap paintings, or baked `MapZones` artwork are
included. All visible world, zone and city map tiles are loaded from the game
client's map APIs at runtime.
