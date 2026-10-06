"""Regression for the Forever crash reported from the HUD right-click menu.

    633x GoldTrack/UI_HUD.lua:793: attempt to call a nil value
    [GoldTrack/UI_HUD.lua]:793: in function <GoldTrack/UI_HUD.lua:791>
    self=GoldTrackCtx  elapsed=0.017  (*temporary)=nil

The menu's OnUpdate called the FrameXML GLOBAL MouseIsOver(self). Retail 12.1.0
moved that global to InputUtil.IsMouseOver and Forever runs the 12.1.5-era API,
so it is nil there while Classic still has it. Because the handler runs every
frame, one missing global produced ~60 errors per second while the menu was open.

The mock models exactly that split, so reverting the fix makes Forever throw this
error while Classic still passes -- the test is sensitive to the bug, not just to
its absence.

Also covers the FauxScrollFrame_* legacy helpers used by the Loot and History
lists: they run on every refresh (same blast radius as an OnUpdate), so both the
working path and the degraded path are exercised.
"""
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from load_addon import boot  # noqa: E402
from harness import Lua  # noqa: E402

SETUP = r"""
CHAT = {}
LOGS = {}
GT.Print = function(m) CHAT[#CHAT+1] = tostring(m) end
-- GT.Log writes straight to the chat frame and only when GT.debug is on.
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) LOGS[#LOGS+1] = tostring(m) end }
GT.debug = true
GT.OnAddonLoaded()
GT.UI.Init(); GT.UI.BuildMain(); GT.RefreshHUD()
GT.UI.UpdateMain(); GT.UI.UpdateLoot()

-- Drive the menu's OnUpdate for `secs` seconds in 1/60s ticks, as the client
-- would. Any nil call inside it throws, which is the bug under test.
function TickMenu(secs)
  local m = GT.UI.ctx
  if not m then return 'no menu' end
  local f = m:GetScript('OnUpdate')
  if not f then return 'no OnUpdate' end
  local n = 0
  while n < secs * 60 do f(m, 1 / 60); n = n + 1 end
  return ('ticked %d frames, shown=%s'):format(n, tostring(m:IsShown()))
end
function OpenMenu() GT.UI.HUDMenu() return GT.UI.ctx end
function MenuLabels()
  local m, t = GT.UI.ctx, {}
  for i = 1, 4 do t[#t+1] = m[i].text:GetText() end
  return table.concat(t, ' | ')
end
function ClickMenu(i) GT.UI.ctx[i]:Click() end

-- Probes for UI_Main's self-contained pagination fallback. Its state lives on the
-- scroll frame, and FirstRowName reads what was actually DRAWN, so a test can
-- prove paging changes the rendered rows rather than only an offset variable.
function GTOff(name) local f = FindFrame(name) return f and f._gtOff end
function GTN(name) local f = FindFrame(name) return f and f._gtN end
function BarOf(name) return FindFrame(name).ScrollBar end
function FirstRowName()
  local p = FindFrame('GoldTrackLootScroll')._parent
  for _, k in ipairs(p._kids or {}) do
    if k.name and k.name.GetText then return tostring(k.name:GetText()) end
  end
  return 'none'
end
function ScrollLootBy(px)
  FindFrame('GoldTrackLootScroll'):GetScript('OnVerticalScroll')(
    FindFrame('GoldTrackLootScroll'), px)
end

-- Enough rows to paginate both lists.
function Populate()
  for i = 1, 40 do
    local k = ('%d:0'):format(2000 + i)
    GoldTrackCharDB.session.rows[k] = { key=k, itemID=2000+i, name='Item '..i,
      link='item:'..(2000+i), count=i, method='VENDOR', unitCopper=100*i, why='x', manual=false }
    table.insert(GoldTrackCharDB.session.order, k)
  end
  for i = 1, 30 do
    GoldTrackCharDB.total.archives[i] = { at=1700000000+i, realm='R', name='N',
      copper=i*1000, activeMs=60000, items=i, best=i*10 }
  end
  GT.UI.ShowTab('loot')
  if GT.UI.BuildHistory then GT.UI.BuildHistory() end
  if GT.UI.ToggleHistory then GT.UI.ToggleHistory() end
end
"""


def run(s):
    for mode in ("classic", "forever"):
        lua, _ = boot(mode)
        lua.execute(SETUP)
        L = Lua(lua, s)
        ev = L.eval

        s.section("%s — HUD right-click menu" % mode.upper())

        # The API split that caused the crash.
        s.check("global MouseIsOver present", ev("tostring(type(MouseIsOver) == 'function')"),
                "true" if mode == "classic" else "false")
        s.check("InputUtil.IsMouseOver present", ev(
            "tostring(InputUtil ~= nil and type(InputUtil.IsMouseOver) == 'function')"),
            "false" if mode == "classic" else "true")
        s.check("method IsMouseOver present", ev(
            "tostring(type(FindFrame('UIParent').IsMouseOver) == 'function')"), "true")
        s.check("GT.Api.MouseIsOver resolves", ev("tostring(type(GT.Api.MouseIsOver) == 'function')"),
                "true")

        # The user's action, and the per-frame handler that threw.
        s.no_throw("open the menu", lambda: ev("OpenMenu()"))
        s.check("menu is shown", ev("tostring(GT.UI.ctx:IsShown())"), "true")
        s.check("menu labels", ev("MenuLabels()"),
                "Lock HUD | Reset session | Hide HUD | Config")
        s.check("menu frame has a real backdrop",
                ev("tostring(FindFrame('GoldTrackCtx').backdropInfo ~= nil)"), "true")

        L.exec("GT.UI.ctx._mouseOver = true")
        s.check("hover 5s (300 frames)", ev("TickMenu(5)"), "ticked 300 frames, shown=true")
        s.check("_life held at 0 while hovered", ev("tostring(GT.UI.ctx._life < 0.1)"), "true")

        L.exec("GT.UI.ctx._mouseOver = false")
        s.check("idle 5s -> auto-hides at 3s", ev("TickMenu(5)"), "ticked 300 frames, shown=false")

        # Each menu entry.
        L.exec("OpenMenu(); ClickMenu(1)")
        s.check("Lock HUD toggles on", ev("tostring(GoldTrackDB.hudLocked)"), "true")
        s.check("menu closes after a click", ev("tostring(not GT.UI.ctx:IsShown())"), "true")
        L.exec("OpenMenu(); ClickMenu(1)")
        s.check("Lock HUD toggles back off", ev("tostring(GoldTrackDB.hudLocked)"), "false")
        # Labels are written when the menu opens, so re-open to read the new state.
        L.exec("OpenMenu()")
        s.check("reopening shows Unlock->Lock again", ev("MenuLabels()"),
                "Lock HUD | Reset session | Hide HUD | Config")
        L.exec("ClickMenu(1)")
        L.exec("OpenMenu()")
        s.check("label tracks hudLocked=true", ev("MenuLabels()"),
                "Unlock HUD | Reset session | Hide HUD | Config")
        L.exec("ClickMenu(1)")   # leave it unlocked for the rest of the run
        L.exec("OpenMenu(); ClickMenu(3)")
        s.check("Hide HUD toggles showHUD", ev("tostring(GoldTrackDB.showHUD)"), "false")
        L.exec("LAST_POPUP = nil; OpenMenu(); ClickMenu(2)")
        s.check("Reset session asks for confirmation", ev("tostring(LAST_POPUP)"), "GOLDTRACK_RESET")
        L.exec("OpenMenu(); ClickMenu(4)")
        s.check("Config opens the main window", ev("tostring(FindFrame('GoldTrackMain'):IsShown())"),
                "true")

        s.section("%s — scroll lists" % mode.upper())

        # Forever is modelled without the Blizzard helpers; see mock_setup.lua for
        # the manifest survey behind that and for the FOREVER_FAUX override.
        faux_present = (mode == "classic")
        note_count = (
            "tostring((function() local n=0 for _,m in ipairs(LOGS) do "
            "if m:find('built-in list pagination', 1, true) then n=n+1 end end return n end)())")
        refresh = ("GT.UI.UpdateLoot(); "
                   "if GT.UI.UpdateArchive then GT.UI.UpdateArchive() end")
        off_probe = ("tostring(FAUX_OFFSET)" if faux_present
                     else "tostring(GTOff('GoldTrackLootScroll'))")

        # fauxNote() fires while the window is built, i.e. during SETUP, so read
        # the count before the log is cleared for the rest of the section.
        note_at_build = ev(note_count)
        lua.execute("LOGS = {}; FAUX_CALLS = 0; FAUX_OFFSET = 0")
        ev("Populate()")
        lua.execute("FAUX_CALLS = 0; FAUX_OFFSET = 0")
        s.check("Blizzard helpers present as modelled", ev(
            "tostring(type(FauxScrollFrame_Update) == 'function')"),
            "true" if faux_present else "false")
        s.no_throw("refresh both lists", lambda: lua.execute(refresh))
        first_row = ev("FirstRowName()")
        s.check("a row was drawn", "true" if first_row not in ("none", "nil") else first_row, "true")

        s.no_throw("scroll 100px", lambda: ev("ScrollLootBy(100)"))
        s.check("offset is 5 rows at 20px each", ev(off_probe), 5)
        second_row = ev("FirstRowName()")
        s.check("page 2 drew a different first row",
                "changed" if second_row != first_row else "same:" + str(second_row), "changed")

        if faux_present:
            s.check("used the Blizzard helper", ev("tostring(FAUX_CALLS > 0)"), "true")
            s.check("no fallback note needed", note_at_build, 0)
            s.check("loot list got its item count", ev(
                "tostring(FindFrame('GoldTrackLootScroll')._fauxItems)"), 40)
            s.check("archive list got its item count", ev(
                "tostring(FindFrame('GoldTrackArchScroll')._fauxItems)"), 30)
        else:
            # The fallback must reproduce the Blizzard helpers' behaviour exactly:
            # same offset arithmetic, same bar range, bar hidden when it fits.
            s.check("no Blizzard helper to call", ev("tostring(FAUX_CALLS)"), 0)
            s.check("fallback noted once at build", note_at_build, 1)
            s.check("fallback stored the item count", ev("tostring(GTN('GoldTrackLootScroll'))"), 40)
            s.check("fallback drove the bar to 100px", ev(
                "tostring(BarOf('GoldTrackLootScroll'):GetValue())"), 100)
            s.check("bar range is 0..(40-14)*20", ev(
                "tostring((function() local lo,hi = "
                "BarOf('GoldTrackLootScroll'):GetMinMaxValues() "
                "return lo..'-'..hi end)())"), "0-520")
            s.check("bar shown while the list overflows", ev(
                "tostring(BarOf('GoldTrackLootScroll'):IsShown())"), "true")
            s.no_throw("scroll far past the end", lambda: ev("ScrollLootBy(99999)"))
            s.check("offset clamps to the last page", ev(off_probe), 26)
            s.no_throw("scroll back to the top", lambda: ev("ScrollLootBy(0)"))
            s.check("offset returns to 0", ev(off_probe), 0)
            s.check("bar snaps back with it", ev(
                "tostring(BarOf('GoldTrackLootScroll'):GetValue())"), 0)

        # Under Classic the helpers exist, so take them away mid-session and prove
        # the fallback picks the list up rather than freezing it on page one.
        if faux_present:
            lua.execute("FauxScrollFrame_Update = nil; FauxScrollFrame_GetOffset = nil;"
                        " FauxScrollFrame_OnVerticalScroll = nil")
            s.no_throw("lists still refresh without them", lambda: lua.execute(refresh))
            s.no_throw("scroll handler still safe without them", lambda: ev("ScrollLootBy(100)"))
            s.check("fallback took over: offset 5", ev(
                "tostring(GTOff('GoldTrackLootScroll'))"), 5)
            s.no_throw("and refresh again", lambda: lua.execute(refresh))
            s.check("rows still drawn after the switch", ev(
                "tostring(FirstRowName() ~= 'none')"), "true")

        # And the override modelling a Forever client that DOES ship the helpers.
        if not faux_present:
            lua2, _ = boot("forever", {"FOREVER_FAUX": "true"})
            lua2.execute(SETUP)
            ev2 = lua2.eval
            s.check("FOREVER_FAUX override restores them", ev2(
                "tostring(type(FauxScrollFrame_Update) == 'function')"), "true")
            lua2.execute("LOGS = {}; FAUX_CALLS = 0; FAUX_OFFSET = 0")
            lua2.execute("Populate()")
            s.no_throw("lists refresh", lambda: lua2.execute(refresh))
            s.check("Blizzard helper used instead of the fallback", ev2(
                "tostring(FAUX_CALLS > 0)"), "true")
            s.check("loot list got its item count", ev2(
                "tostring(FindFrame('GoldTrackLootScroll')._fauxItems)"), 40)
            s.no_throw("scroll 100px", lambda: lua2.execute("ScrollLootBy(100)"))
            s.check("offset is 5 via the Blizzard helper", ev2("tostring(FAUX_OFFSET)"), 5)
            s.check("no fallback note on that client", ev2(note_count), 0)

            # Worst case for Forever: the helper functions AND the template are
            # both gone, so CreateFrame errors and there is no scroll bar at all.
            lua3, _ = boot("forever", {"NO_FAUX_TEMPLATE": "true"})
            lua3.execute(SETUP)
            ev3 = lua3.eval
            s.check("CreateFrame survived the unknown template", ev3(
                "tostring(FindFrame('GoldTrackLootScroll') ~= nil)"), "true")
            s.check("no ScrollBar came with it", ev3(
                "tostring(BarOf('GoldTrackLootScroll') == nil)"), "true")
            s.check("mouse wheel enabled instead", ev3(
                "tostring(FindFrame('GoldTrackLootScroll')._wheel)"), "true")
            lua3.execute("LOGS = {}")
            lua3.execute("Populate()")
            s.no_throw("lists refresh with no bar", lambda: lua3.execute(refresh))
            wheel_first = ev3("FirstRowName()")
            s.no_throw("wheel down three rows", lambda: lua3.execute(
                "FindFrame('GoldTrackLootScroll'):GetScript('OnMouseWheel')"
                "(FindFrame('GoldTrackLootScroll'), -3)"))
            s.check("wheel moved the offset by 3", ev3(
                "tostring(GTOff('GoldTrackLootScroll'))"), 3)
            s.check("wheel re-drew the rows",
                    "changed" if ev3("FirstRowName()") != wheel_first else "same", "changed")
            s.no_throw("wheel back up", lambda: lua3.execute(
                "FindFrame('GoldTrackLootScroll'):GetScript('OnMouseWheel')"
                "(FindFrame('GoldTrackLootScroll'), 3)"))
            s.check("offset back to 0", ev3("tostring(GTOff('GoldTrackLootScroll'))"), 0)
