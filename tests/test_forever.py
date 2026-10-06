"""Two-client regression: Forever (Camelot) and the Classic line must behave alike.

Everything here runs against the REAL addon files, booted from their real TOC
manifests, under a mock that reproduces each client's API surface. The point is
that a Forever-specific break shows up as a difference between the two columns.
"""
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from load_addon import boot  # noqa: E402
from harness import Lua  # noqa: E402

# Shared setup: defaults merged, one miner character, Auctionator's v1 API mocked
# (the same surface its Classic and retail builds expose) so GT.Prices.Resolve
# really derives ahRaw instead of being stubbed out.
SETUP = r"""
GT.Print = function() end
GT.OnAddonLoaded()

SPELLS[2575]='Mining'; SPELLS[7411]='Enchanting'; SPELLS[13262]='Disenchant'; SPELLS[31252]='Prospecting'
ITEMS[2770]={name='Copper Ore',link='item:2770:0:0:0',vendor=5,quality=1,bindType=0,stackCount=20,
             itemType='Trade Goods',subType='Metal & Stone',texture='I'}
ITEMS[2840]={name='Copper Bar',link='item:2840:0:0:0',vendor=10,quality=1,bindType=0,stackCount=20,
             itemType='Trade Goods',subType='Metal & Stone',texture='I'}

local function idof(v) local n=tonumber(v); if n then return n end
  return tonumber(tostring(v):match('item:(%d+)')) end
ATR_PRICE = { [2770]=19000, [2840]=60000 }
BAR_KNOWN = true
Auctionator = { API = { v1 = {
  GetAuctionPriceByItemID = function(_, id) return ATR_PRICE[idof(id)] end,
  GetAuctionPriceByItemLink = function(_, l) return ATR_PRICE[idof(l)] end,
  GetAuctionAgeByItemID = function() return 0 end,       -- 0 = just scanned => fresh
  GetAuctionAgeByItemLink = function() return 0 end,
} } }
GT.Prices.Invalidate(); GT.Prices.Probe()

GoldTrackDB.subtractDeposit=false; GoldTrackDB.ahDepositPreset='ignore'
GoldTrackDB.ahCut='faction'; GoldTrackDB.ahMinSellRate=0; GoldTrackDB.ahValueMode='if_sold'
GoldTrackDB.commonAhMult=3; GoldTrackDB.commonAhFlat=10000
GoldTrackDB.priceSource='atr_fresh_tsm'

-- A miner who cannot enchant, set up the way each client family exposes it.
if FOREVER then PROFS[1]='Mining'; KNOWN_SPELLS[2575]=true
else SKILLS[1]='Mining'; KNOWN_SPELLS[2575]=true end

local function deepcopy(t) local r={} for k,v in pairs(t) do r[k]=(type(v)=='table') and deepcopy(v) or v end return r end
GoldTrackCharDB.session = deepcopy(GT.charDefaults.session)
GoldTrackCharDB.session.state = 'RUNNING'

GT.Events.Init(); GT.Events.SetListen(true)

function LootOre(n)
  local info = GT.Prices.Resolve(2770); info.itemID = 2770
  local val = GT.ValueItem(info, false); val.itemID = 2770
  GT.Ledger.CreditItem('2770:0', n, val, 'loot')
end
function RowState()
  local r = GoldTrackCharDB.session.rows['2770:0']
  return ('%s unit=%s sess=%s | %s'):format(r.method, r.unitCopper,
    GoldTrackCharDB.session.copper, r.why)
end
function EvCount()
  local n = 0
  for _, f in pairs(REGISTERED_EVENTS) do for _ in pairs(f) do n = n + 1 end end
  return n
end
function EvRegistered(name)
  for _, f in pairs(REGISTERED_EVENTS) do if f[name] then return true end end
  return false
end
-- Deposit measured with this client's own default preset (SETUP turns it off so
-- the valuation maths is deterministic elsewhere).
function DepositAtDefault(vendor)
  local keepP, keepS = GoldTrackDB.ahDepositPreset, GoldTrackDB.subtractDeposit
  GoldTrackDB.subtractDeposit = true
  GoldTrackDB.ahDepositPreset = GT.AHDefault()
  local pct = GT.AHPercent(GT.AHDefault())
  local dep = GT.ComputeDeposit(vendor)
  GoldTrackDB.ahDepositPreset, GoldTrackDB.subtractDeposit = keepP, keepS
  return pct, dep
end
function AHLadder()
  local t = {} for _, p in ipairs(GT.AHList()) do t[#t+1] = p.label end
  return table.concat(t, ',')
end
"""


def run(s):
    for mode in ("classic", "forever"):
        lua, files = boot(mode)
        lua.execute(SETUP)
        L = Lua(lua, s)
        ev = L.eval

        s.section("%s  (%s, interface %s, WOW_PROJECT_ID %s)" % (
            mode.upper(), ev("GT.GameVersionLabel()"),
            ev("select(4, GetBuildInfo())"), ev("WOW_PROJECT_ID")))

        s.check("boots from its own TOC", len(files), 12 if mode == "forever" else 11)
        s.check("DetectGameVersion", ev("GT.DetectGameVersion()"),
                "era" if mode == "classic" else "forever")
        s.check("IsForever", ev("tostring(GT.IsForever())"),
                "true" if mode == "forever" else "false")
        s.check("GameMaxLevel", ev("GT.GameMaxLevel()"), 60)

        s.check("AH ladder", ev("AHLadder()"),
                "12h / 15%,24h / 30%,48h / 60%" if mode == "forever"
                else "2h / 5%,8h / 20%,24h / 60%")
        s.check("default deposit %", ev("(DepositAtDefault(1000))"),
                0.30 if mode == "forever" else 0.20)
        s.check("deposit on vendor 1000", ev("select(2, DepositAtDefault(1000))"),
                300 if mode == "forever" else 200)

        # One event name must fail per client, and be swallowed: LOOT_READY on
        # Classic, BAG_UPDATE on Forever. Without the pcall guard, SetListen
        # would abort there and lose every later registration.
        s.check("events registered", ev("EvCount()"), 36)
        s.check("unknown events caught", ev("table.concat(EVENT_ERRORS, ',')"),
                "LOOT_READY" if mode == "classic" else "BAG_UPDATE")
        s.check("CHAT_MSG_LOOT live", ev("tostring(EvRegistered('CHAT_MSG_LOOT'))"), "true")
        s.check("GET_ITEM_INFO_RECEIVED live",
                ev("tostring(EvRegistered('GET_ITEM_INFO_RECEIVED'))"), "true")
        s.check("BAG_UPDATE_DELAYED live",
                ev("tostring(EvRegistered('BAG_UPDATE_DELAYED'))"), "true")
        s.check("LOOT_READY live where it exists",
                ev("tostring(EvRegistered('LOOT_READY'))"),
                "false" if mode == "classic" else "true")

        s.check("CanMining (skill lines / professions)", ev("tostring(GT.CanMining())"), "true")
        s.check("CanDisenchant (not an enchanter)", ev("tostring(GT.CanDisenchant())"), "false")
        L.exec("TIME = TIME + 61")
        L.exec("if FOREVER then PROFS[2]='Enchanting'; KNOWN_SPELLS[13262]=true "
                    "else SKILLS[2]='Enchanting'; KNOWN_SPELLS[13262]=true end")
        s.check("CanDisenchant (enchanter)", ev("tostring(GT.CanDisenchant())"), "true")

        s.check("Auctionator detected", ev("tostring(GT.Prices.status.atr)"), "true")
        s.check("Resolve() via the compat layer", ev("GT.Prices.Resolve(2770).name"), "Copper Ore")
        s.check("Resolve() carries ahRaw", ev("tostring(GT.Prices.Resolve(2770).ahRaw)"), 19000)

        # Automatic ore -> bar: the bar's per-ore AH net (57000) beats the ore's (18050).
        L.exec("LootOre(10)")
        s.check("loot 10 ore -> auto smelt", ev("RowState()"),
                "AH unit=57000 sess=570000 | smelt to Copper Bar")

        # Bar data missing at loot time -> ore's own value + smeltPending, then
        # upgraded when GET_ITEM_INFO_RECEIVED lands. This is the path that most
        # depends on the item API being resolved correctly per client.
        L.exec(r"""
        GoldTrackCharDB.session.rows['2770:0'] = nil
        GoldTrackCharDB.session.order = {}
        GoldTrackCharDB.session.copper = 0
        GoldTrackCharDB.session.byMethod = { AH=0, DE=0, VENDOR=0, NONE=0, GOLD=0 }
        BAR_KNOWN = false
        local realResolve = GT.Prices.Resolve
        GT.Prices.Resolve = function(id, link)
          if id == 2840 and not BAR_KNOWN then return nil end
          return realResolve(id, link)
        end
        """)
        L.exec("LootOre(10)")
        s.check("bar unknown -> ore's own AH", ev("RowState()"),
                "AH unit=18050 sess=180500 | mat: net >= 3x vendor or vendor+1g")
        s.check("row flagged smeltPending", ev("tostring(GoldTrackCharDB.session.rows['2770:0'].smeltPending)"),
                "true")
        L.exec("BAR_KNOWN = true; GT.Prices.Invalidate(); GT.Events.OnItemInfo(2840)")
        s.check("deferred revalue upgrades row", ev("RowState()"),
                "AH unit=57000 sess=570000 | smelt to Copper Bar")
        s.check("smeltPending cleared", ev("tostring(GoldTrackCharDB.session.rows['2770:0'].smeltPending)"),
                "nil")
        s.check("byMethod.AH total", ev("tostring(GoldTrackCharDB.session.byMethod.AH)"), 570000)
        s.check("SmeltPrefetch warms the bars", ev("GT.SmeltPrefetch()"), 8)

        # Forever mirrors the account config into the per-character table, because
        # the Forever client does not read account-wide SavedVariables back.
        L.exec("GoldTrackDB.ahMinVsVendor = 123456; GT.SaveCfgMirror()")
        s.check("config mirror written", ev("tostring(GoldTrackCharDB[GT.CFG_MIRROR] ~= nil)"),
                "true" if mode == "forever" else "false")
        if mode == "forever":
            L.exec("GoldTrackDB = {}; GT.RestoreCfgMirror()")
            s.check("config restored from mirror", ev("tostring(GoldTrackDB.ahMinVsVendor)"), 123456)
            L.exec("GoldTrackDB.gameVersionKnown = true; GoldTrackDB.ahMinVsVendor = nil;"
                        " GT.RestoreCfgMirror()")
            s.check("restore self-disables when SV works",
                    ev("tostring(GoldTrackDB.ahMinVsVendor)"), "nil")

        # Backdrop: the mixin exists on both families, so every window is created
        # with BackdropTemplate and really gets a backdrop (a Forever traceback
        # confirmed this: GoldTrackCtx carried backdropInfo + NineSlice textures).
        L.exec("GT.UI.Init(); GT.UI.BuildMain(); GT.RefreshHUD()")
        s.check("HUD frame got a backdrop", ev("tostring(FindFrame('GoldTrackHUD').backdropInfo ~= nil)"),
                "true")
        s.check("main frame got a backdrop", ev("tostring(FindFrame('GoldTrackMain').backdropInfo ~= nil)"),
                "true")
        # ... and the texture fallback in GT.UI.Backdrop still works for a frame
        # that has no backdrop methods.
        s.no_throw("GT.UI.Backdrop fallback branch", lambda: lua.execute(r"""
            local plain = CreateFrame('Frame', 'GoldTrackPlainProbe', UIParent)
            GT.UI.Backdrop(plain)
            if plain.backdropInfo then error('plain frame should not have a backdrop') end
            if #plain._tex == 0 then error('fallback should have created a texture') end
        """))
