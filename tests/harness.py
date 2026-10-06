"""Tiny assertion harness so each test file stays readable."""


class Suite:
    def __init__(self):
        self.total = 0
        self.fails = 0
        self._section = ""

    def section(self, text):
        self._section = text
        print("\n  %s" % text)

    def check(self, label, got, want):
        """Assert got == want (compared as strings, so Lua numbers/bools behave)."""
        self.total += 1
        ok = str(got) == str(want)
        if not ok:
            self.fails += 1
        print("    [%s] %-40s %s%s" % (
            "PASS" if ok else "FAIL", label, got, "" if ok else "   <- want %s" % want))
        return ok

    def no_throw(self, label, fn):
        """Assert fn() runs without a Lua error."""
        self.total += 1
        try:
            fn()
            print("    [PASS] %-40s no error" % label)
            return True
        except Exception as e:  # noqa: BLE001 - lupa raises LuaError
            self.fails += 1
            print("    [FAIL] %-40s %s" % (label, str(e).split("\n")[0]))
            return False


class Lua:
    """Wraps a lupa runtime so a Lua error becomes a recorded FAIL, not a crash.

    A broken addon should fail checks loudly and let the rest of the suite run --
    an uncaught LuaError would abort everything and hide how much else is wrong.
    """

    def __init__(self, lua, suite):
        self.lua = lua
        self.s = suite

    def eval(self, expr):
        try:
            return self.lua.eval(expr)
        except Exception as e:  # noqa: BLE001
            return "ERROR: " + str(e).split("\n")[0]

    def exec(self, code, label=None):
        try:
            self.lua.execute(code)
            return True
        except Exception as e:  # noqa: BLE001
            self.s.total += 1
            self.s.fails += 1
            print("    [FAIL] %-40s %s" % (
                (label or code.strip().split("\n")[0])[:40], str(e).split("\n")[0]))
            return False
