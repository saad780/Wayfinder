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


def main():
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
            print(f"  parsed {rel}")
            continue
        with open(path, encoding="utf-8") as fh:
            load_file(fh.read(), "@" + rel.replace(os.sep, "/"), ns)
        print(f"  loaded {rel}")

    lua.execute('mock.Fire("ADDON_LOADED", "Wayfinder")')
    lua.execute('mock.Fire("PLAYER_LOGIN")')
    lua.execute("mock.Advance(0.1)")

    with open(os.path.join(HERE, "test_wayfinder.lua"), encoding="utf-8") as fh:
        failed = lua.execute(fh.read())
    if failed:
        sys.exit(1)
    sys.exit(subprocess.run([sys.executable, os.path.join(HERE, "test_sources.py")]).returncode)


if __name__ == "__main__":
    main()
