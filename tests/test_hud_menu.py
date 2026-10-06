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

        s.section("%s — scroll lists (FauxScrollFrame_*)" % mode.upper())
        L.exec("Populate()")
        L.exec("FAUX_CALLS = 0; FAUX_OFFSET = 0")
        s.no_throw("refresh both lists", lambda: lua.execute(
            "GT.UI.UpdateLoot(); if GT.UI.UpdateArchive then GT.UI.UpdateArchive() end"))
        s.check("FauxScrollFrame_Update was used", ev("tostring(FAUX_CALLS > 0)"), "true")
        s.check("loot list got its item count", ev(
            "tostring(FindFrame('GoldTrackLootScroll')._fauxItems)"), 40)
        s.check("archive list got its item count", ev(
            "tostring(FindFrame('GoldTrackArchScroll')._fauxItems)"), 30)
        s.no_throw("scroll 100px", lambda: ev(
            "FindFrame('GoldTrackLootScroll'):GetScript('OnVerticalScroll')"
            "(FindFrame('GoldTrackLootScroll'), 100)"))
        s.check("offset is 5 rows at 20px each", ev("tostring(FAUX_OFFSET)"), 5)

        # Now take the legacy helpers away, as a retail-engine client could.
        L.exec("FauxScrollFrame_Update = nil; FauxScrollFrame_GetOffset = nil;"
                    " FauxScrollFrame_OnVerticalScroll = nil")
        L.exec("LOGS = {}")
        calls_before = ev("FAUX_CALLS")

        # The warning must fire exactly ONCE, not once per refresh: these lists
        # redraw on every loot event, so a per-refresh warning would be the same
        # kind of spam as the OnUpdate crash this file exists to prevent.
        warn_count = (
            "tostring((function() local n=0 for _,m in ipairs(LOGS) do "
            "if m:find('unavailable on this client', 1, true) then n=n+1 end end return n end)())")

        s.no_throw("scroll handler still safe without them", lambda: ev(
            "FindFrame('GoldTrackLootScroll'):GetScript('OnVerticalScroll')"
            "(FindFrame('GoldTrackLootScroll'), 100)"))
        s.check("warned once via GT.Log", ev(warn_count), 1)
        s.no_throw("lists still refresh without them", lambda: lua.execute(
            "GT.UI.UpdateLoot(); if GT.UI.UpdateArchive then GT.UI.UpdateArchive() end"))
        s.no_throw("and refresh again", lambda: lua.execute(
            "GT.UI.UpdateLoot(); if GT.UI.UpdateArchive then GT.UI.UpdateArchive() end"))
        s.check("no helper calls remain possible", ev("tostring(FAUX_CALLS)"), calls_before)
        s.check("did not warn again (no spam)", ev(warn_count), 1)
