#!/usr/bin/env python3
"""Run GoldTrack's two-client test suite.

    python3 -m venv /tmp/gt && /tmp/gt/bin/pip install lupa
    /tmp/gt/bin/python tests/run_tests.py

Boots the real addon files, in the order their real TOC manifests list them,
inside a mock WoW client -- once as Classic Era and once as WoW: Forever -- and
asserts that both behave the same where they should and differently where they
must. Exits non-zero on any failure.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from harness import Suite  # noqa: E402

MODULES = ("test_forever", "test_hud_menu")


def main():
    try:
        import lupa  # noqa: F401
    except ImportError:
        print("lupa is required:  pip install lupa")
        return 2

    s = Suite()
    print("GoldTrack: booting the real addon from its real TOCs, on both client families")
    for name in MODULES:
        mod = __import__(name)
        print("\n" + "=" * 78)
        print(name)
        mod.run(s)
    print("\n" + "=" * 78)
    print("RESULT: %d checks, %d failure(s)" % (s.total, s.fails))
    return 1 if s.fails else 0


if __name__ == "__main__":
    sys.exit(main())
