# Independent location collection

Version 1.3.4 starts a staged migration. No Carbonite or Leatrix location has
been relabeled as independent: the current manifest intentionally contains no
reviewed replacements. All 735 service and 28 transport entries remain available
with their original attribution. GPL continues to apply to this release.

## Collect measurements

After `/reload`, Wayfinder separately records new service interactions, nearby
sightings, mailbox visits, guard directions, and client flight-node coordinates
in `WayfinderDB.observations`. Each measurement has its collection method, client
version/build, timestamp, identity when available, positional accuracy, and the
client's map rectangle. Existing merged POIs are preserved and are not exported
as new measurements. Opening a flight map also collects undiscovered nodes if
the client returns them; they are not marked as learned flight paths.

Stand at a dock, tram entrance, or portal and record its route explicitly:

```
/wf survey transport boat 0 Boat to Ratchet
/wf survey transport portal 1 Portal to Darnassus
/wf survey
```

Kinds: `boat`, `zeppelin`, `tram`, `portal`. Factions: `0` neutral, `1` Alliance,
`2` Horde. The label must describe the destination. Surveying collects evidence;
it does not immediately add or replace a built-in marker. No uploads occur.
Resetting recorded locations also clears these observations.

## Export and review

Reload or log out so the game saves observations, then export that file:

```
python tools/export_observations.py "path/to/SavedVariables/Wayfinder.lua" candidate.json
```

The export contains `schema`, `sources`, and `records`; each record starts with
`verified: false`. Review the location, category, faction, identity, and accuracy
before marking it verified. Review class tokens and profession labels explicitly.
For profession trainers, use a service label such as `Alchemy Trainer`, backed by
the observed title/service. Only measurements accurate to eight yards or better
can replace built-ins; distant sightings need closer observations first.

Retain original source evidence. Do not paste another addon's coordinates into
an observation or invent collection metadata. Exported client observations use
the `client-observation` designation, which describes their origin and does not
grant rights over Blizzard's underlying data or assets.

External general datasets require verified data-specific permission, rather
than merely a publicly accessible URL or a license on the site's software.
Their source entry needs `origin: external`, `description`, `url`, `license`, and
`dataPermission` (the permission reference). Accepted data terms are CC0, MIT,
BSD-2-Clause, BSD-3-Clause, ISC, or CC-BY-4.0. Except for CC0, supply the required
license/copyright/attribution text in `notice`; it is included in generated Lua
so bundled replacements carry their notices. Review Forever compatibility and
origin before accepting any external measurements.

## Generate replacements

Merge reviewed observations and their source entries into `data/observations.json`:

```
python tools/build_seed.py data/observations.json --check
python tools/build_seed.py data/observations.json
python tests/run_tests.py
```

The default target build is `70170`; specify `--build` after a client update and
recollect or reverify build-specific observations. The builder emits
`Wayfinder/Data/Independent.lua` and `data/coverage.json`. Unreviewed records are
excluded. Malformed coordinates, unsupported sources, incompatible builds,
insufficient accuracy, and conflicting nearby replacements are rejected.

Replacement matching requires the same category, map, faction, and class; routes
also need the same transport kind and destination, and profession trainers need
the same profession label. A unique nearest measurement within 25 yards can
replace an imported entry. Unmatched entries remain available. Output is
deterministic, and the report groups unresolved entries by category, zone,
faction, class, profession, and route.

Runtime replacements preserve exploration reveal, settings, and recorded-location
precedence. Hidden markers migrate through verified replacement aliases;
unmatched hidden keys remain saved. If client geometry cannot place a replacement,
the original marker remains available. Gameplay requires no external service.

## Completing the migration

The report lists source and coverage gaps; zero unresolved entries is a coverage
gate, not automatic permission to relicense. Legacy data, generation aliases
derived from it, copied material elsewhere in the repository, and every retained
source's terms must be reviewed before a permissive release. Remove each source's
acknowledgement only once its material has been replaced. MIT is the target for
project-owned code; third-party assets/data keep their own terms. Earlier GPL
releases keep their existing permissions.

Before releasing replacements, check services from both factions and all classes
and professions, every transport route, overlay edges and zoom, per-character
quest availability, and waypoint sharing between two real clients. Automated
tests simulate the APIs; they do not replace these in-game checks.
