"""Boot the real GoldTrack addon under the lupa WoW mock, from its actual TOC.

Reads the manifest so the tests exercise the shipped load order and file list:
  classic -> GoldTrack.toc         (Core, Version, Compat, ...)
  forever -> GoldTrack_Camelot.toc (Core, Forever, Version, Compat, ...)

Core.lua is a vararg chunk invoked as Core('GoldTrack', GoldTrack), the way the
Blizzard loader does it.

Usage:  python3 tests/run_tests.py     (see tests/README.md)
"""
import os
import re

import lupa

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HERE = os.path.dirname(os.path.abspath(__file__))


def toc_files(toc_name):
    """The .lua/.xml entries of a manifest, in load order."""
    text = open(os.path.join(REPO, toc_name), encoding="utf-8").read()
    files = []
    for line in text.splitlines():
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        s = re.sub(r"\s*\[.*\]\s*$", "", s)   # strip per-line TOC directives
        if s.lower().endswith((".lua", ".xml")):
            files.append(s)
    return files


def boot(mode="classic", overrides=None):
    """Load the addon into a fresh mock client. Returns (lua, files).

    `overrides` sets Lua globals BEFORE the mock is evaluated, which is how a
    test flips a modelling assumption -- e.g. boot("forever",
    {"FOREVER_FAUX": "true"}) to model a Forever client that does still ship the
    legacy FauxScrollFrame helpers. See mock_setup.lua for why that is a flag.
    """
    if mode not in ("classic", "forever"):
        raise ValueError("mode must be 'classic' or 'forever'")
    lua = lupa.LuaRuntime()
    lua.execute("FOREVER = %s" % ("true" if mode == "forever" else "false"))
    for name, value in (overrides or {}).items():
        lua.execute("%s = %s" % (name, value))
    lua.execute(open(os.path.join(HERE, "mock_setup.lua"), encoding="utf-8").read())

    toc = "GoldTrack_Camelot.toc" if mode == "forever" else "GoldTrack.toc"
    files = toc_files(toc)
    for fn in files:
        if fn.lower().endswith(".xml"):
            continue
        code = open(os.path.join(REPO, fn), encoding="utf-8").read()
        if fn == "Core.lua":
            lua.execute("local f = assert(load(%r, '=Core', 't')); f('GoldTrack', GoldTrack)" % code)
        else:
            lua.execute("local f,e = load(%r, %r, 't'); if not f then error(e) end; f()" % (code, "=" + fn))
    return lua, files
