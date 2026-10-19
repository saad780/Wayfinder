"""Load Wayfinder in a Lua 5.1 runtime with a mocked WoW API and run its tests.

    python tests/run_tests.py

Needs `pip install lupa`. Every file listed in Wayfinder.toc is compiled (Lua) or
parsed (XML) exactly as the client would load it, then the addon is started with
ADDON_LOADED / PLAYER_LOGIN and driven through tests/test_wayfinder.lua.
"""

import os
import subprocess
import sys
import xml.etree.ElementTree as ET

import lupa.lua51 as lupa

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.join(HERE, "..", "Wayfinder")


def toc_files():
    files = []
    with open(os.path.join(ADDON, "Wayfinder.toc"), encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line and not line.startswith("#"):
                files.append(line.replace("\\", os.sep))
    return files


def load_addon(continuous=False, with_openmap=False, disabled=False, quiet=False):
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.execute("io.stdout:setvbuf('no')")
    with open(os.path.join(HERE, "wowmock.lua"), encoding="utf-8") as fh:
        lua.execute(fh.read())

    load_file = lua.eval(
        """function(source, chunkname, ns)
            local chunk, err = loadstring(source, chunkname)
            if not chunk then error(err, 0) end
            chunk("Wayfinder", ns)
        end"""
    )
    ns = lua.table()
    for rel in toc_files():
        path = os.path.join(ADDON, rel)
        if rel.endswith(".xml"):
            ET.parse(path)  # must at least be well-formed
            if not continuous and not quiet:
                print(f"  parsed {rel}")
            continue
        with open(path, encoding="utf-8") as fh:
            load_file(fh.read(), "@" + rel.replace(os.sep, "/"), ns)
        if not continuous and not quiet:
            print(f"  loaded {rel}")

    if continuous:
        lua.execute(f"mock.withOpenMap = {'true' if with_openmap else 'false'}")
        with open(os.path.join(HERE, "continuous_fixture.lua"), encoding="utf-8") as fh:
            lua.execute(fh.read())
        if disabled:
            lua.execute("WayfinderDB = { settings = { continuousMap = false } }")

    lua.execute('mock.Fire("ADDON_LOADED", "Wayfinder")')
    lua.execute('mock.Fire("PLAYER_LOGIN")')
    lua.execute("mock.Advance(0.1)")
    return lua


def main():
    lua = load_addon()

    with open(os.path.join(HERE, "test_wayfinder.lua"), encoding="utf-8") as fh:
        failed = lua.execute(fh.read())
    if failed:
        sys.exit(1)
    with open(os.path.join(HERE, "test_openmap.lua"), encoding="utf-8") as fh:
        if lua.execute(fh.read()):
            sys.exit(1)
    with open(os.path.join(HERE, "test_turnins.lua"), encoding="utf-8") as fh:
        if lua.execute(fh.read()):
            sys.exit(1)
    with open(os.path.join(HERE, "test_minimap_turnins.lua"), encoding="utf-8") as fh:
        if lua.execute(fh.read()):
            sys.exit(1)
    with open(os.path.join(HERE, "test_minimap_services.lua"), encoding="utf-8") as fh:
        if lua.execute(fh.read()):
            sys.exit(1)
    with open(os.path.join(HERE, "test_tracking_menu.lua"), encoding="utf-8") as fh:
        if lua.execute(fh.read()):
            sys.exit(1)
    startup = load_addon(quiet=True)
    with open(os.path.join(HERE, "test_startup.lua"), encoding="utf-8") as fh:
        if startup.execute(fh.read()):
            sys.exit(1)
    idle = load_addon(quiet=True)
    with open(os.path.join(HERE, "test_idle.lua"), encoding="utf-8") as fh:
        if idle.execute(fh.read()):
            sys.exit(1)
    motion = load_addon(quiet=True)
    with open(os.path.join(HERE, "test_minimap_motion.lua"), encoding="utf-8") as fh:
        if motion.execute(fh.read()):
            sys.exit(1)
    visibility = load_addon(quiet=True)
    with open(os.path.join(HERE, "test_service_visibility.lua"), encoding="utf-8") as fh:
        if visibility.execute(fh.read()):
            sys.exit(1)
    for with_openmap in (False, True):
        continuous = load_addon(continuous=True, with_openmap=with_openmap)
        with open(os.path.join(HERE, "test_continuous.lua"), encoding="utf-8") as fh:
            if continuous.execute(fh.read()):
                sys.exit(1)
        player = load_addon(continuous=True, with_openmap=with_openmap, quiet=True)
        with open(os.path.join(HERE, "test_continuous_player.lua"), encoding="utf-8") as fh:
            if player.execute(fh.read()):
                sys.exit(1)
        flights = load_addon(continuous=True, with_openmap=with_openmap, quiet=True)
        with open(os.path.join(HERE, "test_flight_quests.lua"), encoding="utf-8") as fh:
            if flights.execute(fh.read()):
                sys.exit(1)
    disabled = load_addon(continuous=True, with_openmap=True, disabled=True)
    disabled.execute("""
        assert(not Wayfinder.ContinuousMap.started)
        assert(mock.openMapModule.enabled and mock.openMapModule.db.enabled)
        assert(Wayfinder.OpenMapCompat:GetAPI() == OpenMapAPI)
        io.write('  ok    disabling continuous mode preserves OpenMap and its compatibility adapter\\n')
    """)
    for suite in ("test_sources.py", "test_arrow_art.py"):
        result = subprocess.run([sys.executable, os.path.join(HERE, suite)])
        if result.returncode:
            sys.exit(result.returncode)


if __name__ == "__main__":
    main()
