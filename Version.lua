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

-- Keys that are economy-coupled: these get auto-set per client and are the only
-- fields that change when you switch client. Everything else (UI, price source,
-- sell-rate behavior) stays where the user put it.
GT.EconomyKeys = {
  "ahMinVsVendor", "ahMinVsDE", "deMinVsVendor",
  "commonAhMult", "commonAhFlat",
  "ahMinSellRate", "ahUnknownSellRate",
  "ahValueMode", "subtractDeposit", "ahDepositPreset",
  "hudMinLevel",
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
      ahDepositPreset = "24h_30",
      hudMinLevel = 60,
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
      hudMinLevel = 70,
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

  local _, _, _, toc = GetBuildInfo and GetBuildInfo() or nil
  toc = toc or 0
  if toc >= 11500 then return "era"
  elseif toc >= 20500 then return "tbc"
  elseif toc >= 30400 then return "wotlk"
  elseif toc >= 40400 then return "cata"
  elseif toc >= 50500 then return "mists"
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

  if not GoldTrackDB.gameVersionKnown then
    -- First run with client-awareness. If the stored values are exactly the old
    -- (TBC) defaults, treat this as fresh and adopt this client's defaults.
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
    GoldTrackDB.thresholdPresets = presets
    return
  end

  if GoldTrackDB.gameVersion ~= v then
    local prev = GoldTrackDB.gameVersion or "unknown"
    -- Save what the outgoing client had, then load the incoming client's
    -- custom record (or its defaults if the user never touched it).
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
