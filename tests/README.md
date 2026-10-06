# GoldTrack test harness

Boots the **real** addon files — in the order their **real** TOC manifests list
them — inside a mock WoW client, and asserts that Classic Era and WoW: Forever
behave the same where they should and differently where they must.

```bash
python3 -m venv /tmp/gt && /tmp/gt/bin/pip install lupa
/tmp/gt/bin/python tests/run_tests.py
```

Exit code is non-zero if any check fails. 124 checks at the time of writing.

## Why this exists

GoldTrack ships from one package to three client families whose APIs have
diverged. Most Forever breakage cannot be reasoned about from the code: it only
appears when a global the addon assumed is there turns out not to be. Two real
examples this harness now pins:

- `Prices.lua` captured `local GetItemInfo = GetItemInfo` at file scope. On
  Forever that global is absent, so it captured `nil` and crashed **before**
  `ADDON_LOADED` — the addon never loaded at all.
- The HUD right-click menu called the FrameXML global `MouseIsOver(frame)`,
  which retail 12.1.0 moved to `InputUtil.IsMouseOver`. Forever runs the
  12.1.5-era API, so it threw `attempt to call a nil value` **once per frame**
  while the menu was open (633 errors in one sitting). Classic still has the
  global, so nothing about the Classic build suggested a problem.

Both were invisible to code review and obvious the moment the two clients were
booted side by side.

## Files

| File | Purpose |
| --- | --- |
| `run_tests.py` | Runner. Imports each `test_*` module and reports a total. |
| `harness.py` | `Suite` (PASS/FAIL reporting) and `Lua` (turns a Lua error into a recorded FAIL instead of aborting the run). |
| `load_addon.py` | Parses `GoldTrack.toc` / `GoldTrack_Camelot.toc` and loads the listed files in order. `Core.lua` is invoked as a vararg chunk, as the Blizzard loader does. |
| `mock_setup.lua` | The mock client. Defines the widget API, fixtures, and **which globals exist**. |
| `test_forever.py` | Detection, AH ladder, deposit maths, events, professions, price resolution, the ore→bar valuation chain, the SavedVariables mirror, backdrops. |
| `test_hud_menu.py` | The HUD right-click menu and its per-frame `OnUpdate`; the Loot/History scroll lists, including their degraded path. |

## How the two clients are modelled

`FOREVER = true` selects the Forever client. The differences that matter are
modelled explicitly, because each one caught (or would have caught) a real bug:

| | Classic mode | Forever mode |
| --- | --- | --- |
| `WOW_PROJECT_ID` | 2 (CLASSIC) | 1 (MAINLINE — same as retail) |
| Interface | 11509 | 16001 |
| Item/spell/addon API | `GetItemInfo`, `GetSpellInfo`, `IsAddOnLoaded`, … | absent; `C_Item`, `C_Spell` (returns a **table**), `C_AddOns`, `C_Container`, `C_TradeSkillUI` |
| Professions | `GetNumSkillLines` / `GetSkillLineInfo` | absent; `GetProfessions` / `GetProfessionInfo` |
| Open trade skill | `GetTradeSkillLine` | absent; `C_TradeSkillUI.GetBaseProfessionInfo` |
| Global `MouseIsOver` | present | **absent** (`InputUtil.IsMouseOver` instead) |
| `BAG_UPDATE` | present | **absent** (removed retail 10.0) |
| `LOOT_READY` | absent | present |
| `RegisterEvent` of an unknown name | — | **throws**, as the real client does |

Two details worth knowing before editing the mock:

- `SetBackdrop` comes from `BackdropTemplateMixin`, not the base widget API, so
  only frames created *with* `"BackdropTemplate"` have it. That is what makes the
  addon's `if frame.SetBackdrop then` test meaningful and keeps its
  texture-fallback branch covered. The mixin exists on both families (retail
  since 9.0, backported to Classic) — a Forever traceback confirmed it, since
  `GoldTrackCtx` carried `backdropInfo` and NineSlice textures.
- `RegisterEvent` throwing is deliberate. Without it the pcall guard in
  `GT.Api.RegisterEvent` would pass tests while being useless in game.

## Writing a check

```python
s.check("label", ev("GT.GameMaxLevel()"), 60)          # expression -> compared as strings
s.no_throw("label", lambda: lua.execute("GT.UI.Init()"))  # statement -> must not error
```

`ev` is `Lua.eval`, which returns `"ERROR: …"` instead of raising, so a broken
addon fails checks loudly and the rest of the suite still runs. Use
`lua.execute` directly (inside a `no_throw` lambda) when the point is that the
call must not throw.

Statements — assignments, `if … end`, multi-call lines — need `lua.execute`,
not `lua.eval`; `eval` only accepts a single expression.

## Known limits

The mock is a behavioural model, not a client. It cannot tell you about texture
paths, font metrics, secure-template restrictions, or how a widget actually lays
out. Geometry assertions elsewhere in this suite resolve anchors arithmetically,
which is good enough to catch a control positioned outside its window but is not
a substitute for looking at the addon in game. Anything visual still needs a real
client.
