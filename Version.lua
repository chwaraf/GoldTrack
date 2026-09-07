--[[ GoldTrack — client-version layer.
Detects which WoW client we are running on and provides per-version economy
defaults (the gold "resolution" of the game). TBC Anniversary has a much larger
gold economy than Classic Era, so thresholds like "AH beats vendor by X" must be
scaled per client or the addon is useless on Era. This module also manages the
SavedVariables that keep a user's own thresholds separate per client so that
switching characters/clients never destroys a carefully tuned setup.

The detection is robust: it prefers the WOW_PROJECT_ID constant (which
disambiguates the classic-family clients) and falls back to the interface
number from GetBuildInfo(). All values are numeric literals, not the
WOW_PROJECT_* globals, because a given client may not define every constant.
]]
local GT = GoldTrack

local floor = math.floor
local COPPER_G = 10000

GT.VERSION = "1.1.0"

-- Bump whenever a VERSION_PROFILES.economy default CHANGES shape/meaning, so
-- existing SavedVariables that predate the change get the corrected defaults on
-- next load (instead of silently keeping an old value that made the HUD hide).
-- rev 3 added the per-client AH deposit model + ahCut. rev 4 corrected Era's
-- deposit percentages (5/20/60, not 15/30/60) and removed the "8h_30"/"24h_30"
-- presets from the Era ladder, so any DB that adopted those stale keys (from a
-- rev-3 build) must be remapped to a key Era actually has.
GT.EconomyRev = 4

-- The values the previous economy defaults left in the DB, keyed per client.
-- A migration compares the live value against these; if it still equals the old
-- default (i.e. the user never changed it), the new default is applied. Tuned
-- fields are never touched. Only list keys whose DEFAULT changed vs the last
-- release. (hudMinLevelOn became an economy key in rev 2; before that it was a
-- plain Core default of `true`, which is why Era HUDs were hidden below level.)
GT.OldEconomyDefaults = {
  era = { hudMinLevel = 60, hudMinLevelOn = true, ahDepositPreset = "24h_30", ahCut = "faction" },
  tbc = { hudMinLevelOn = true, ahCut = "faction" },
}

-- Auction House deposit model, per client. The deposit is a fraction of the
-- item's vendor sell price, and the durations available (and therefore which
-- duration maps to which percent) differ between clients:
--   Classic Era (pre-2.3, Vanilla): 2h=5%, 8h=20%, 24h=60%  (24h is the LONGEST = 60%)
--   TBC (post-2.3):                12h=15%, 24h=30%, 48h=60% (24h is the MIDDLE = 30%)
-- The percentages are NOT the same set across clients. Era's base deposit rate
-- is 5% (per the Vanilla client's GetAuctionHouseDepositRate / duration/120),
-- scaling 1x/4x/12x => 5%/20%/60%. TBC's base is 15% scaling 1x/2x/4x =>
-- 15%/30%/60%. A preset is a duration+percent pair and is client-specific: the
-- old default "24h/30%" is wrong on Era (a 24h Era auction costs 60%, not 30%,
-- and Era has no 12h/48h options at all). Defaults to a common mid-length/mid-
-- cost listing: Era 8h_20 (8h / 20%), TBC 24h_30 (24h / 30%).
GT.AH_PRESETS = {
  era = {
    { key = "2h_05",  label = "2h / 5%",   pct = 0.05, hours = 2 },
    { key = "8h_20",  label = "8h / 20%",  pct = 0.20, hours = 8 },
    { key = "24h_60", label = "24h / 60%", pct = 0.60, hours = 24 },
  },
  tbc = {
    { key = "12h_15",  label = "12h / 15%",  pct = 0.15, hours = 12 },
    { key = "24h_30",  label = "24h / 30%",  pct = 0.30, hours = 24 },
    { key = "48h_60",  label = "48h / 60%",  pct = 0.60, hours = 48 },
  },
}
GT.AH_DEFAULT = { era = "8h_20", tbc = "24h_30" }

-- Keys that are economy-coupled: these get auto-set per client and are the only
-- fields that change when you switch client. Everything else (UI, price source,
-- sell-rate behavior) stays where the user put it.
GT.EconomyKeys = {
  "ahMinVsVendor", "ahMinVsDE", "deMinVsVendor",
  "commonAhMult", "commonAhFlat",
  "ahMinSellRate", "ahUnknownSellRate",
  "ahValueMode", "subtractDeposit", "ahDepositPreset", "ahCut",
  "hudMinLevel", "hudMinLevelOn",
}

-- Per-client economy defaults. TBC matches the classic GoldTrack defaults that
-- existed before client-awareness; Era is roughly an order of magnitude smaller
-- (the "5 to 10x" you asked for). Add future clients here when needed.
GT.VERSION_PROFILES = {
  era = {
    label = "Classic Era",
    maxLevel = 60,
    economy = {
      ahMinVsVendor = 1 * COPPER_G,   -- 1g   (TBC 10g)
      ahMinVsDE     = 1 * COPPER_G,   -- 1g   (TBC 8g)
      deMinVsVendor = 1000,           -- 10s  (TBC 1g)
      commonAhMult  = 3,
      commonAhFlat  = 1000,           -- 10s  (TBC 1g)
      ahMinSellRate = 0.10,
      ahUnknownSellRate = 0.50,
      ahValueMode = "if_sold",
      subtractDeposit = true,
      -- 8h (20%) on Era: the deposit percentage is a per-client concept; Era's
      -- ladder is 2h=5%/8h=20%/24h=60%, so 8h is the mid-length listing.
      ahDepositPreset = "8h_20",
      ahCut = "faction", -- faction AH cut 5%; neutral (Goblin) is 15%
      -- On by default on Era: the min-level auto-hide is disabled so the HUD
      -- shows for every character regardless of level (the user's expectation).
      hudMinLevel = 1,
      hudMinLevelOn = false,
    },
  },
  tbc = {
    label = "Burning Crusade / Anniversary",
    maxLevel = 70,
    economy = {
      ahMinVsVendor = 10 * COPPER_G,
      ahMinVsDE     = 8 * COPPER_G,
      deMinVsVendor = 1 * COPPER_G,
      commonAhMult  = 3,
      commonAhFlat  = 1 * COPPER_G,
      ahMinSellRate = 0.10,
      ahUnknownSellRate = 0.50,
      ahValueMode = "if_sold",
      subtractDeposit = true,
      ahDepositPreset = "24h_30",
      ahCut = "faction",
      hudMinLevel = 70,
      hudMinLevelOn = true,
    },
  },
  -- Stubs so future clients at least detect cleanly. They fall through to
  -- "keep current values" (no economy override) until tuned; add a real
  -- economy table when you want per-client defaults for them.
  wotlk = { label = "Wrath of the Lich King", maxLevel = 80, economy = nil },
  cata  = { label = "Cataclysm",              maxLevel = 85, economy = nil },
  mists = { label = "Mists of Pandaria",      maxLevel = 90, economy = nil },
  retail= { label = "Retail (Mainline)",      maxLevel = 80, economy = nil },
  unknown = { label = "Unknown client",       maxLevel = 70, economy = nil },
}

-- Detect the running client. Prefer WOW_PROJECT_ID (2=Classic Era, 5=TBC,
-- 11=Wrath, 14=Cata, 19=Mists, 1=Retail); fall back to the interface number so
-- we still come up on any client that lacks the constant.
function GT.DetectGameVersion()
  local p = WOW_PROJECT_ID
  if p == 2 then return "era" end        -- WOW_PROJECT_CLASSIC
  if p == 5 then return "tbc" end        -- WOW_PROJECT_BURNING_CRUSADE_CLASSIC
  if p == 11 then return "wotlk" end     -- WOW_PROJECT_WRATH_CLASSIC
  if p == 14 then return "cata" end      -- WOW_PROJECT_CATACLYSM_CLASSIC
  if p == 19 then return "mists" end     -- WOW_PROJECT_MISTS_CLASSIC
  if p == 1 then return "retail" end     -- WOW_PROJECT_MAINLINE

  -- Fallback to the interface number. A `GetBuildInfo()` call used directly in
  -- an `and`/`or`/parenthesised expression is truncated to a single value (the
  -- version string), leaving `toc` nil. Capture the call into locals FIRST so
  -- the 4th return (the interface number) survives.
  local toc
  if GetBuildInfo then
    local _, _, _, maybeToc = GetBuildInfo()
    toc = maybeToc
  end
  toc = toc or 0
  -- Check from the HIGHEST threshold down. A naive "era first, then tbc" would
  -- match every modern client (e.g. 20506 >= 11500) as Era.
  if toc >= 50500 then return "mists"
  elseif toc >= 40400 then return "cata"
  elseif toc >= 30400 then return "wotlk"
  elseif toc >= 20500 then return "tbc"
  elseif toc >= 11500 then return "era"
  end
  return "unknown"
end

function GT.GameVersionLabel(v)
  local prof = GT.VERSION_PROFILES[v or GT.gameVersion or "unknown"]
  return (prof and prof.label) or "Unknown client"
end

function GT.GameMaxLevel(v)
  local prof = GT.VERSION_PROFILES[v or GT.gameVersion or "unknown"]
  return (prof and prof.maxLevel) or 70
end

-- Auction deposit preset list for the current client (duration->percent pairs).
-- Era: 2h=5%/8h=20%/24h=60%; TBC: 12h=15%/24h=30%/48h=60%. Falls back to TBC for
-- unknown clients so the config dropdown is never empty.
function GT.AHList(v)
  return GT.AH_PRESETS[v or GT.gameVersion or "unknown"] or GT.AH_PRESETS.tbc
end

-- The default deposit preset key for a client (a mid-length cost listing on
-- both: Era 8h_20 = 8h/20%, TBC 24h_30 = 24h/30%).
function GT.AHDefault(v)
  return GT.AH_DEFAULT[v or GT.gameVersion or "unknown"] or "24h_30"
end

-- Deposit percentage (0..1) for a preset key on the current client. Key is
-- client-specific (e.g. "24h_30" is TBC's 24h=30% and doubles as a generic 30%
-- preset, but on Era 30% doesn't exist; "24h_60" is Era's 24h=60%). If the
-- exact key isn't valid on this client (a stale preset from the other client,
-- or an economy-rev before durations diverged), fall back to the percent encoded
-- in the key suffix (_30 -> 0.30, _20 -> 0.20), else the client default.
function GT.AHPercent(preset, v)
  local client = v or GT.gameVersion or "unknown"
  local list = GT.AHList(client)
  if preset == "custom" then
    return (GoldTrackDB.ahDepositPercent) or 0.30
  end
  for i = 1, #list do
    if list[i].key == preset then return list[i].pct end
  end
  local pct = tonumber((preset or ""):match("_(%d+)$"))
  if pct then
    pct = pct / 100
    return pct
  end
  return 0.30
end

-- Remap a stored preset key onto the current client's duration ladder, keeping
-- the same deposit percentage. Used by the migration so a TBC "24h_30" becomes
-- a valid Era preset (Era has no 24h/30%; 30% maps to none, so it falls back to
-- the Era default "8h_20"), and a stale "8h_30" becomes "8h_20".
function GT.AHRemap(preset)
  local client = GT.gameVersion or "unknown"
  if preset == "custom" or preset == "ignore" then return preset end
  local pct = GT.AHPercent(preset, client)
  local list = GT.AHList(client)
  for i = 1, #list do
    if math.abs(list[i].pct - pct) < 0.0001 then return list[i].key end
  end
  return GT.AHDefault(client)
end

-- AH cut (faction 5% / neutral 15% of the winning/hammer price). Reads the
-- per-client `ahCut` economy key. Used for both the `cut` term in AHNet and
-- the tooltip label.
function GT.AHCut()
  return (GoldTrackDB.ahCut == "neutral") and 0.15 or 0.05
end

-- Snapshot the currently-active economy fields into a plain table.
function GT.EconomySnapshot()
  local t = {}
  for i = 1, #GT.EconomyKeys do
    local k = GT.EconomyKeys[i]
    t[k] = GoldTrackDB[k]
  end
  return t
end

-- Write a snapshot table back into GoldTrackDB (only keys it actually defines).
function GT.EconomyApply(t)
  if not t then return end
  for i = 1, #GT.EconomyKeys do
    local k = GT.EconomyKeys[i]
    if t[k] ~= nil then
      GoldTrackDB[k] = t[k]
    end
  end
  -- hudMinLevel may require the HUD visibility to be re-evaluated.
  if GT.UI and GT.UI.ApplyHUDVisibility then GT.UI.ApplyHUDVisibility() end
end

-- Does tbl exactly match the economy defaults of the given client?
function GT.EconomyMatches(tbl, profile)
  if not tbl then return false end
  local e = profile and profile.economy
  if not e then return false end
  for i = 1, #GT.EconomyKeys do
    local k = GT.EconomyKeys[i]
    if tbl[k] ~= e[k] then return false end
  end
  return true
end

-- Persist a single economy field, keeping a per-client record so a tuned setup
-- survives switching clients. Use this instead of assigning GoldTrackDB directly
-- for any field in GT.EconomyKeys.
function GT.SetEconomy(key, value)
  GoldTrackDB[key] = value
  local v = GT.gameVersion or "unknown"
  local presets = GoldTrackDB.thresholdPresets or {}
  if not presets[v] then presets[v] = {} end
  presets[v][key] = value
  GoldTrackDB.thresholdPresets = presets
end

-- Reset the active economy fields to this client's defaults and clear that
-- client's custom record (so the reset is what is remembered).
function GT.ResetEconomy()
  local v = GT.gameVersion or "unknown"
  local prof = GT.VERSION_PROFILES[v]
  if not prof or not prof.economy then
    GT.Print("No economy defaults defined for this client.")
    return
  end
  GT.EconomyApply(prof.economy)
  local presets = GoldTrackDB.thresholdPresets or {}
  presets[v] = {}
  for k, val in pairs(prof.economy) do presets[v][k] = val end
  GoldTrackDB.thresholdPresets = presets
  GT.Print("GoldTrack: reset economy to " .. prof.label .. " defaults.")
  if GT.UI and GT.UI.RefreshConfig then GT.UI.RefreshConfig() end
end

-- Called from OnAddonLoaded after defaults are merged. Detects the client,
-- and if the client changed since last time, swaps in the right economy values
-- while saving the outgoing client's values so nothing is lost.
function GT.ApplyGameVersion()
  local v = GT.DetectGameVersion()
  GT.gameVersion = v
  GT.maxLevel = GT.GameMaxLevel(v)

  local presets = GoldTrackDB.thresholdPresets or {}
  local known = GoldTrackDB.gameVersionKnown

  if not known then
    -- First run with client-awareness. Fresh installs (or an upgrade whose
    -- values are still the untouched TBC defaults) adopt this client's defaults.
    -- Otherwise keep whatever the user had, so we never clobber a tuned setup.
    local cur = GT.EconomySnapshot()
    local prof = GT.VERSION_PROFILES[v]
    if prof and prof.economy and v ~= "tbc" and GT.EconomyMatches(cur, GT.VERSION_PROFILES.tbc) then
      GT.EconomyApply(prof.economy)
      cur = GT.EconomySnapshot()
    end
    presets[v] = cur
    GoldTrackDB.gameVersion = v
    GoldTrackDB.gameVersionKnown = true
    -- Fresh DB: this revision's defaults are baked in, nothing to migrate.
    GoldTrackDB.economyRev = GT.EconomyRev
    GoldTrackDB.thresholdPresets = presets
    return
  end

  -- Existing (already-initialized) DB. If the client changed, swap in the
  -- incoming client's profile (saving the outgoing one) FIRST, then run the
  -- one-time default-correction migration so stale defaults that changed meaning
  -- (e.g. hudMinLevelOn on Era) catch up without clobbering user tweaks.
  if GoldTrackDB.gameVersion ~= v then
    local prev = GoldTrackDB.gameVersion or "unknown"
    presets[prev] = GT.EconomySnapshot()
    local prof = GT.VERSION_PROFILES[v]
    local nextVals = presets[v] or (prof and prof.economy)
    if nextVals then
      GT.EconomyApply(nextVals)
      GT.Print("GoldTrack: using " .. (GT.VERSION_PROFILES[v] and GT.VERSION_PROFILES[v].label or v) .. " economy settings.")
    end
    GoldTrackDB.gameVersion = v
    GoldTrackDB.thresholdPresets = presets
  end

  local rev = GoldTrackDB.economyRev or 0
  if rev < GT.EconomyRev then
    local prof = GT.VERSION_PROFILES[v] or GT.VERSION_PROFILES.unknown
    local old = GT.OldEconomyDefaults[v]
    if old then
      for i = 1, #GT.EconomyKeys do
        local k = GT.EconomyKeys[i]
        if old[k] ~= nil and GoldTrackDB[k] == old[k] then
          local nv = prof.economy and prof.economy[k]
          if nv ~= nil then
            GoldTrackDB[k] = nv
            if presets[v] then presets[v][k] = nv end
          end
        end
      end
    end
    -- Deposit durations diverged between clients (Era 2/8/24h vs TBC 12/24/48h).
    -- Even a value the user chose (not the old default) may be a preset key from
    -- the other ladder; remap it to the equivalent-% preset on THIS client so the
    -- config dropdown shows a real option and the deposit math stays correct.
    local preset = GoldTrackDB.ahDepositPreset
    if preset and preset ~= "custom" and preset ~= "ignore" then
      local remapped = GT.AHRemap(preset)
      if remapped ~= preset then
        GoldTrackDB.ahDepositPreset = remapped
        if presets[v] then presets[v].ahDepositPreset = remapped end
      end
    end
    GoldTrackDB.economyRev = GT.EconomyRev
    GoldTrackDB.thresholdPresets = presets
    if GT.UI and GT.UI.ApplyHUDVisibility then GT.UI.ApplyHUDVisibility() end
  end
end

-- Human-readable, for /gt version and config display.
function GT.VersionSummary()
  local v = GT.gameVersion or GT.DetectGameVersion()
  local prof = GT.VERSION_PROFILES[v]
  return format("GoldTrack %s\nClient: %s%s\nMax level: %s",
    GT.VERSION,
    (prof and prof.label) or v,
    (prof and " (" .. v .. ")") or "",
    GT.GameMaxLevel(v))
end
