--[[ GoldTrack — namespace, defaults, clock, slash ]]
local ADDON, GT = ...
_G.GoldTrack = GT

local GetTime, time, floor = GetTime, time, math.floor
local UnitIsAFK = UnitIsAFK

GT.ADDON = "GoldTrack"
GT.VERSION = "1.0.0"

-- Caps (memory)
GT.PRICE_CACHE_TTL = 30
GT.PRICE_CACHE_MAX = 256
GT.DEDUP_SIZE = 200
-- Short TTL: the ring only needs to catch duplicate DELIVERY of one event
-- (same frame / next frame). A 5s TTL swallowed legitimate repeats of the
-- same item+count looted in quick succession (skinning, cloth runs).
GT.DEDUP_TTL = 1
GT.LOOT_ROW_MAX = 400
GT.ARCHIVE_MAX = 30
GT.PENDING_MAX = 32
GT.OPENABLE_CACHE_MAX = 512

-- Timing
GT.HUD_INTERVAL = 1.0
GT.NIT_LOCK_MIN = 1 -- NIT ticker is 1s; never pull faster
GT.BAG_DEBOUNCE = 0.05
GT.TRANSFER_GRACE = 2.0
GT.OPEN_TTL = 2.0
GT.DESTROY_SUPPRESS = 5.0
-- Longer window when the trigger is session-farmed DE-able gear leaving bags:
-- that signal only fires for gear we already counted, so a wider net is safe.
GT.DESTROY_SUPPRESS_BAG = 15.0
-- Armed at UNIT_SPELLCAST_START so the window covers the full cast even if
-- SUCCEEDED is delayed or missed (bar/macro/addon casts included).
GT.DESTROY_SUPPRESS_START = 10.0
GT.RELOAD_GAP = 60
GT.LOOT_FRAME_RECENT = 1.5

local COPPER_G = 10000

GT.defaults = {
  hudScale = 1,
  mainScale = 1,
  hudLocked = false,
  showHUD = true,
  hudMinLevelOn = true,
  hudMinLevel = 70,
  showMinimap = true,
  hideHudInCombat = false,
  hudPoint = nil, -- nil = under minimap
  uiRev = 2,
  mainPoint = { "CENTER", "UIParent", "CENTER", 0, 0 },
  mainW = 520,
  mainH = 420,

  ahMinVsVendor = 10 * COPPER_G,
  ahMinVsDE = 8 * COPPER_G,
  deMinVsVendor = 1 * COPPER_G,
  commonAhMult = 3,
  commonAhFlat = 1 * COPPER_G,
  ahPriceField = "conservative",
  tsmPriceField = "market",
  ahValueMode = "if_sold",
  ahMinSellRate = 0.10,
  ahUnknownSellRate = 0.50,
  subtractDeposit = true,
  ahDepositPreset = "24h_30",
  ahDepositPercent = 0.30,
  priceSource = "atr_fresh_tsm",
  atrFreshHours = 2,

  minGhSeconds = 30,
  pauseWhenAFK = true,
  resumeAfterReload = true,
  resumeAfterLogout = false,
  countQuestRewards = false,
  autoStartOnLoot = false,
  revalueLive = false,
}

GT.charDefaults = {
  session = {
    state = "STOPPED",
    activeMs = 0,
    leavingAt = nil,
    startedAt = nil,
    zone = "",
    copper = 0,
    items = 0,
    byMethod = { AH = 0, DE = 0, VENDOR = 0, NONE = 0, GOLD = 0 },
    rows = {},
    order = {},
  },
  total = {
    copper = 0,
    items = 0,
    activeMs = 0,
    sessionsCompleted = 0,
    bestSessionCopper = 0,
    bestSessionGh = 0,
    byMethod = { AH = 0, DE = 0, VENDOR = 0, NONE = 0, GOLD = 0 },
    archives = {},
  },
}

-- Runtime (never persisted)
GT.segmentStart = nil
GT.afkPaused = false
GT.debug = false
GT._dirtyUI = false

local function deepcopy(src)
  local t = {}
  for k, v in pairs(src) do
    if type(v) == "table" then
      t[k] = deepcopy(v)
    else
      t[k] = v
    end
  end
  return t
end

local function merge(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then dst[k] = {} end
      merge(dst[k], v)
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
end

function GT.Cfg()
  return GoldTrackDB
end

function GT.Char()
  return GoldTrackCharDB
end

function GT.Sess()
  return GoldTrackCharDB.session
end

function GT.IsRunning()
  return GoldTrackCharDB and GoldTrackCharDB.session.state == "RUNNING" and not GT.afkPaused
end

function GT.IsSessionLive()
  return GoldTrackCharDB and GoldTrackCharDB.session.state == "RUNNING"
end

function GT.NowMs()
  local s = GoldTrackCharDB.session
  local live = 0
  if s.state == "RUNNING" and GT.segmentStart and not GT.afkPaused then
    live = floor((GetTime() - GT.segmentStart) * 1000)
    if live < 0 then live = 0 end
  end
  return s.activeMs + live
end

function GT.FoldSegment()
  local s = GoldTrackCharDB.session
  if s.state == "RUNNING" and GT.segmentStart and not GT.afkPaused then
    local d = floor((GetTime() - GT.segmentStart) * 1000)
    if d > 0 then s.activeMs = s.activeMs + d end
  end
  GT.segmentStart = nil
end

function GT.StartSegment()
  local s = GoldTrackCharDB.session
  if s.state == "RUNNING" and not GT.segmentStart and not GT.afkPaused then
    GT.segmentStart = GetTime()
  end
end

local function refreshUI()
  if GT.RefreshHUD then GT.RefreshHUD() end
  if GT.RefreshMain then GT.RefreshMain() end
end

function GT.SessionStart()
  local s = GoldTrackCharDB.session
  if s.state == "RUNNING" then
    if GT.afkPaused then
      GT.afkPaused = false
      GT.StartSegment()
    end
    refreshUI()
    return
  end
  s.state = "RUNNING"
  if not s.startedAt then
    s.startedAt = time()
    s.zone = GetRealZoneText and GetRealZoneText() or ""
  end
  GT.afkPaused = false
  GT.StartSegment()
  if GT.Events and GT.Events.OnSessionStart then GT.Events.OnSessionStart() end
  refreshUI()
end

function GT.SessionStop()
  local s = GoldTrackCharDB.session
  if s.state ~= "RUNNING" then return end
  GT.FoldSegment()
  s.state = "STOPPED"
  GT.afkPaused = false
  if GT.Events and GT.Events.SetListen then GT.Events.SetListen(false) end
  refreshUI()
end

function GT.SessionReset(force)
  local s = GoldTrackCharDB.session
  local empty = (s.copper == 0 and s.items == 0 and (not s.order or #s.order == 0))
  if not empty then
    GT.Ledger.ArchiveCurrent()
  end
  GT.FoldSegment()
  s.state = "STOPPED"
  s.activeMs = 0
  s.leavingAt = nil
  s.startedAt = nil
  s.zone = ""
  s.copper = 0
  s.items = 0
  s.byMethod = { AH = 0, DE = 0, VENDOR = 0, NONE = 0, GOLD = 0 }
  s.rows = {}
  s.order = {}
  GT.segmentStart = nil
  GT.afkPaused = false
  if GT.Events then
    GT.Events.ResetRuntime()
    if GT.Events.SetListen then GT.Events.SetListen(false) end
  end
  refreshUI()
end

function GT.GPerHour(copper, ms)
  local sec = (ms or 0) / 1000
  local minSec = (GoldTrackDB and GoldTrackDB.minGhSeconds) or 30
  if sec < minSec then return nil end
  if sec <= 0 then return 0 end
  return copper / (sec / 3600)
end

function GT.Log(fmt, ...)
  if not GT.debug then return end
  DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffGT|r " .. format(fmt, ...))
end

function GT.Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffGoldTrack|r " .. msg)
end

function GT.OnAFK(isAFK)
  if not GoldTrackDB.pauseWhenAFK then return end
  local s = GoldTrackCharDB.session
  if s.state ~= "RUNNING" then return end
    if isAFK and not GT.afkPaused then
    GT.FoldSegment()
    GT.afkPaused = true
    if GT.RefreshHUD then GT.RefreshHUD() end
  elseif (not isAFK) and GT.afkPaused then
    GT.afkPaused = false
    GT.StartSegment()
    if GT.RefreshHUD then GT.RefreshHUD() end
  end
end

function GT.OnLeavingWorld()
  GT.FoldSegment()
  GoldTrackCharDB.session.leavingAt = time()
end

function GT.OnLogout()
  -- /reload also fires LOGOUT. Do not STOP here.
  -- ADDON_LOADED uses leavingAt gap: short = reload (keep RUNNING), long = real logout.
  GT.FoldSegment()
  GoldTrackCharDB.session.leavingAt = time()
end

function GT.OnAddonLoaded()
  if type(GoldTrackDB) ~= "table" then GoldTrackDB = {} end
  if type(GoldTrackCharDB) ~= "table" then GoldTrackCharDB = {} end
  merge(GoldTrackDB, deepcopy(GT.defaults))
  merge(GoldTrackCharDB, deepcopy(GT.charDefaults))
  if (GoldTrackDB.uiRev or 0) < 2 then
    GoldTrackDB.hudPoint = nil
    GoldTrackDB.uiRev = 2
  end
  if (GoldTrackDB.uiRev or 0) < 3 then
    GoldTrackDB.mainW = 422
    GoldTrackDB.mainH = 351
    GoldTrackDB.uiRev = 3
  end
  if (GoldTrackDB.cfgRev or 0) < 3 then
    if GoldTrackDB.minGhSeconds == 60 then GoldTrackDB.minGhSeconds = 30 end
    if GoldTrackDB.ahMinVsDE == 10 * COPPER_G then GoldTrackDB.ahMinVsDE = 8 * COPPER_G end
    if GoldTrackDB.priceSource == "tsm_then_atr" then GoldTrackDB.priceSource = "atr_fresh_tsm" end
    if GoldTrackDB.tsmPriceField == nil then GoldTrackDB.tsmPriceField = "market" end
    GoldTrackDB.cfgRev = 3
  end

  -- never persist GetTime
  GT.segmentStart = nil
  GT.afkPaused = false

  local s = GoldTrackCharDB.session
  if s.state == "RUNNING" then
    local gap = s.leavingAt and (time() - s.leavingAt) or 99999
    if gap <= GT.RELOAD_GAP and GoldTrackDB.resumeAfterReload then
      -- keep RUNNING; StartSegment on ENTERING_WORLD
    else
      if not GoldTrackDB.resumeAfterLogout then
        s.state = "STOPPED"
      end
    end
  end
  s.leavingAt = nil

  if not s.byMethod then
    s.byMethod = { AH = 0, DE = 0, VENDOR = 0, NONE = 0, GOLD = 0 }
  end
  if not s.rows then s.rows = {} end
  if not s.order then s.order = {} end
end

function GT.OnEnteringWorld()
  GT.StartSegment()
  if GT.UI and GT.UI.Init then GT.UI.Init() end
  -- NIT writes leftTime on leave; it can lag behind ENTERING_WORLD
  GT.PullNITLockout(true)
  GT.RefreshHUD()
  GT.After(0.5, function() GT.PullNITLockout(true); GT.RefreshHUD() end)
  GT.After(2, function() GT.PullNITLockout(true); GT.RefreshHUD() end)
end

-- Slash -----------------------------------------------------------------
SLASH_GOLDTRACK1 = "/gt"
SLASH_GOLDTRACK2 = "/goldtrack"
SlashCmdList.GOLDTRACK = function(msg)
  msg = (msg or ""):lower():match("^%s*(.-)%s*$")
  if msg == "" then
    if GT.UI then GT.UI.ToggleMain() end
  elseif msg == "hud" then
    GoldTrackDB.showHUD = not GoldTrackDB.showHUD
    if GT.UI then GT.UI.ApplyHUDVisibility() end
  elseif msg == "start" then
    GT.SessionStart()
    GT.Print("session started")
  elseif msg == "stop" then
    GT.SessionStop()
    GT.Print("session stopped")
  elseif msg == "reset" then
    StaticPopup_Show("GOLDTRACK_RESET")
  elseif msg == "config" then
    if GT.UI then GT.UI.ShowTab("config") end
  elseif msg == "refresh" then
    GT.RefreshTSMRows(false)
  elseif msg == "stripde" then
    local n, c = GT.Ledger.StripDEReagents()
    GT.Print(format("removed %d DE/prospect mats (%s) from this session", n, GT.FormatCopper(c or 0)))
  elseif msg == "selftest" then
    GT.SelfTest()
  elseif msg == "debug" then
    GT.debug = not GT.debug
    GT.Print("debug " .. (GT.debug and "on" or "off"))
  else
    GT.Print("/gt  /gt hud  /gt start|stop  /gt reset  /gt refresh  /gt config  /gt selftest  /gt debug")
  end
end

-- Keybinds (Bindings.xml; listed under Key Bindings > AddOns > GoldTrack) --
_G.BINDING_NAME_GOLDTRACK_TOGGLE = "Toggle Main Window"
_G.BINDING_NAME_GOLDTRACK_STARTSTOP = "Start / Pause Session"
_G.BINDING_NAME_GOLDTRACK_HUD = "Toggle HUD"
_G.BINDING_NAME_GOLDTRACK_RESET = "Reset Session (asks to confirm)"

function GoldTrackBindingToggleMain()
  if GT.UI then GT.UI.ToggleMain() end
end

function GoldTrackBindingStartStop()
  -- Same toggle the HUD Start/Pause button uses.
  if GoldTrackCharDB.session.state == "RUNNING" then
    GT.SessionStop()
    GT.Print("session stopped")
  else
    GT.SessionStart()
    GT.Print("session started")
  end
end

function GoldTrackBindingToggleHUD()
  GoldTrackDB.showHUD = not GoldTrackDB.showHUD
  if GT.UI then GT.UI.ApplyHUDVisibility() end
end

function GoldTrackBindingReset()
  -- Goes through the confirm popup; never resets silently.
  StaticPopup_Show("GOLDTRACK_RESET")
end

StaticPopupDialogs["GOLDTRACK_RESET"] = {
  text = "Archive this session into Total and clear?",
  button1 = YES,
  button2 = NO,
  OnAccept = function() GT.SessionReset() end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1,
  preferredIndex = 3,
}

StaticPopupDialogs["GOLDTRACK_WIPE"] = {
  text = "Type DELETE to wipe this character's GoldTrack data.",
  button1 = OKAY,
  button2 = CANCEL,
  hasEditBox = 1,
  OnAccept = function(self)
    local box = self.editBox or _G[self:GetName() .. "EditBox"]
    if box and box:GetText() == "DELETE" then
      GoldTrackCharDB = deepcopy(GT.charDefaults)
      GT.segmentStart = nil
      GT.Print("character data wiped")
      GT.RefreshHUD()
      GT.RefreshMain()
    else
      GT.Print("wipe cancelled (type DELETE)")
    end
  end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1,
  preferredIndex = 3,
}

-- Bootstrap --------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:RegisterEvent("PLAYER_LEAVING_WORLD")
boot:RegisterEvent("PLAYER_LOGOUT")
boot:RegisterEvent("PLAYER_FLAGS_CHANGED")
boot:RegisterEvent("PLAYER_LEVEL_UP")
boot:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 ~= ADDON then return end
    GT.OnAddonLoaded()
    if GT.Events then GT.Events.Init() end
  elseif event == "PLAYER_LOGIN" then
    if GT.Prices then GT.Prices.Probe() end
    -- TSM AppHelper often fills AuctionDB a few seconds after login
    GT.After(2, function() GT.RefreshTSMRows(true) end)
    GT.After(8, function() GT.RefreshTSMRows(true) end)
    GT.After(20, function() GT.RefreshTSMRows(true) end)
  elseif event == "PLAYER_ENTERING_WORLD" then
    GT.OnEnteringWorld()
  elseif event == "PLAYER_LEAVING_WORLD" then
    GT.OnLeavingWorld()
  elseif event == "PLAYER_LOGOUT" then
    GT.OnLogout()
  elseif event == "PLAYER_FLAGS_CHANGED" then
    if arg1 == "player" or arg1 == nil then
      GT.OnAFK(UnitIsAFK("player"))
    end
  elseif event == "PLAYER_LEVEL_UP" then
    if GT.UI and GT.UI.ApplyHUDVisibility then GT.UI.ApplyHUDVisibility() end
  end
end)

function GT.RefreshHUD()
  if GT.UI and GT.UI.UpdateHUD then GT.UI.UpdateHUD() end
end

function GT.RefreshMain()
  GT._dirtyUI = true
  if GT.UI and GT.UI.UpdateMain then GT.UI.UpdateMain() end
end

function GT.After(sec, fn)
  if C_Timer and C_Timer.After then
    C_Timer.After(sec, fn)
    return
  end
  local f = CreateFrame("Frame")
  local t = 0
  f:SetScript("OnUpdate", function(_, e)
    t = t + e
    if t >= sec then
      f:SetScript("OnUpdate", nil)
      fn()
    end
  end)
end

function GT.RefreshTSMRows(silent)
  if not GT.Ledger or not GT.Ledger.RefreshTSM then return end
  local s = GoldTrackCharDB and GoldTrackCharDB.session
  if not s or not s.order or #s.order == 0 then
    if not silent then GT.Print("TSM refresh: 0 items") end
    return
  end
  local n, hit = GT.Ledger.RefreshTSM()
  if not silent then
    GT.Print(format("TSM refresh: %d items, %d have region data (not fallback)", n, hit))
  end
  if GT.UI and GT.UI.UpdateLoot then GT.UI.UpdateLoot() end
end

-- True if this character can disenchant (knows spell 13262).
local encCached, encAt = nil, 0
local addonsAt, addonsT, addonsA, addonsN = -99
function GT.AddonsOn()
  local now = GetTime()
  -- Short TTL so HUD T/A/N indicators track addon load state closely.
  if addonsT ~= nil and (now - addonsAt) < 5 then
    return addonsT, addonsA, addonsN
  end
  local tsm = not not ((TSM_API and TSM_API.GetCustomPriceValue) or TSMAPI or TSMAPI_FOUR)
  local atr = not not ((Auctionator and Auctionator.API and Auctionator.API.v1) or Atr_GetAuctionBuyout or Atr_GetAuctionPrice)
  local nit = not not (_G.NIT)
  if not nit and IsAddOnLoaded then
    nit = not not (IsAddOnLoaded("NovaInstanceTracker") or IsAddOnLoaded("NovaInstanceTracker-TBC"))
  end
  addonsAt, addonsT, addonsA, addonsN = now, tsm, atr, nit
  return tsm, atr, nit
end

-- Same numbers as NIT minibutton: NIT:getInstanceLockoutInfo().
-- NIT itself walks the log every 1s (NIT:ticker -> updateDataBrokerText).
-- We do not. Pull on instance enter/leave (plus 0.5s/2s for late leftTime)
-- and once when a cached lock ages out. HUD 0.2s only paints the cache.
-- returns used, max, nextFreeSec  (nextFreeSec only when used >= max)
-- nil used = NIT not loaded
local lockPulledAt, lockUsed, lockMax, lockTs = 0, nil, 5, nil

local function lockLeft()
  if lockUsed == nil then return nil end
  if lockUsed >= (lockMax or 5) and type(lockTs) == "number" and lockTs > 0 then
    local now = (GetServerTime and GetServerTime()) or time()
    local left = 3600 - (now - lockTs)
    if left < 0 then left = 0 end
    return left
  end
  return nil
end

function GT.PullNITLockout(force)
  if not force and (GetTime() - lockPulledAt) < (GT.NIT_LOCK_MIN or 1) then
    return
  end
  lockPulledAt = GetTime()
  local NIT = _G.NIT
  if not NIT or type(NIT.getInstanceLockoutInfo) ~= "function" then
    lockUsed, lockMax, lockTs = nil, 5, nil
    return
  end
  local ok, hourCount, _, hourTimestamp = pcall(NIT.getInstanceLockoutInfo, NIT)
  if not ok or type(hourCount) ~= "number" then
    lockUsed, lockMax, lockTs = nil, 5, nil
    return
  end
  lockUsed = hourCount
  lockMax = NIT.hourlyLimit or 5
  lockTs = hourTimestamp
  if GT.UI and GT.UI.SetHUDPulse then GT.UI.SetHUDPulse() end
end

function GT.HourlyLockout()
  if lockUsed ~= nil and type(lockTs) == "number" and lockTs > 0 then
    local now = (GetServerTime and GetServerTime()) or time()
    if now - lockTs >= 3600 then
      GT.PullNITLockout()
    end
  end
  return lockUsed, lockMax or 5, lockLeft()
end

function GT.CanDisenchant()
  local now = GetTime()
  if encCached ~= nil and (now - encAt) < 30 then return encCached end
  local yes = false
  if IsSpellKnown and IsSpellKnown(13262) then
    yes = true
  elseif IsPlayerSpell and IsPlayerSpell(13262) then
    yes = true
  elseif GetSpellInfo and GetNumSkillLines and GetSkillLineInfo then
    local encName = GetSpellInfo(7411) -- Enchanting
    if encName then
      for i = 1, GetNumSkillLines() do
        local name = GetSkillLineInfo(i)
        if name == encName then yes = true; break end
      end
    end
  end
  encCached, encAt = yes, now
  return yes
end
