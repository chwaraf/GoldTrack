--[[ GoldTrack — valuation rule engine ]]
local GT = GoldTrack

local floor = math.floor

function GT.DepositPercent()
  local cfg = GoldTrackDB
  if not cfg.subtractDeposit then return 0 end
  local p = cfg.ahDepositPreset or GT.AHDefault()
  if p == "ignore" then return 0 end
  -- Client-aware: resolves the preset against the running client's duration
  -- ladder (Era 2/8/24h, TBC 12/24/48h) via GT.AHPercent.
  local pct
  if p == "custom" then
    pct = cfg.ahDepositPercent or 0.30
  else
    pct = GT.AHPercent(p)
  end
  -- Neutral (Goblin) AHs charge 5x the faction deposit as well as a 15% cut.
  if cfg.ahCut == "neutral" then pct = pct * 5 end
  return pct
end

function GT.ComputeDeposit(vendor)
  vendor = vendor or 0
  if vendor <= 0 then return 0 end
  local pct = GT.DepositPercent()
  if pct <= 0 then return 0 end
  return floor(vendor * pct)
end

function GT.AHNet(ahRaw, vendor, sellRate, sellSrc)
  if not ahRaw or ahRaw <= 0 then return nil, 0, 0, "if_sold" end
  local cfg = GoldTrackDB
  local cut = floor(ahRaw * GT.AHCut())
  local deposit = GT.ComputeDeposit(vendor)
  local p = sellRate
  if p == nil then p = cfg.ahUnknownSellRate or 0.50 end
  if p < 0 then p = 0 elseif p > 1 then p = 1 end

  -- Unknown rate must not invent a 50% haircut on market value.
  local mode = cfg.ahValueMode or "if_sold"
  if sellSrc == "fallback" or not sellSrc then
    mode = "if_sold"
  end

  local lost, ahNet
  if mode == "expected_single" then
    lost = floor((1 - p) * deposit)
    ahNet = floor(p * (ahRaw - cut) - (1 - p) * deposit)
  elseif mode == "expected_relist" then
    local pp = p < 0.01 and 0.01 or p
    lost = floor(deposit * (1 - p) / pp)
    ahNet = floor((ahRaw - cut) - lost)
  else
    lost = floor(deposit * (1 - p))
    ahNet = (ahRaw - cut) - lost
  end
  if ahNet < 0 then ahNet = 0 end
  return ahNet, deposit, lost, mode
end

function GT.MatBeatsVendor(ahNet, vendor)
  local cfg = GoldTrackDB
  if not ahNet or ahNet <= vendor then return false end
  local flat = cfg.commonAhFlat or 10000
  if vendor <= 0 then
    return ahNet >= flat
  end
  local mult = cfg.commonAhMult or 3
  return (ahNet >= vendor * mult) or (ahNet >= vendor + flat)
end

-- Smelting (Mining): ore -> bar map, from the Classic client's smelting recipes.
-- Each entry: barID, barName (a sanity guard so a stale/wrong ID never fires),
-- oreIn (ore required per craft) and barsOut (bars produced).
-- Only SINGLE-ORE smelts are listed (Bronze/Steel/Felsteel are multi-reagent
-- alloys and not a clean "one ore -> one bar" choice). VSP/deposit/AH value for
-- the ORE itself is still the basis; the bar only ever wins when it is worth
-- more, and then the ore is credited at the bar's per-ore value.
-- TBC-only ores (Fel Iron / Adamantite / Eternium / Khorium, 2:1) can be added
-- here with their (verified) item IDs later; the mechanism needs no other change.
GT.SMELT = {
  [2770]  = { barID = 2840,  barName = "Copper Bar",     oreIn = 1, barsOut = 1 }, -- Copper Ore
  [2771]  = { barID = 3576,  barName = "Tin Bar",        oreIn = 1, barsOut = 1 }, -- Tin Ore
  [2775]  = { barID = 2842,  barName = "Silver Bar",     oreIn = 1, barsOut = 1 }, -- Silver Ore
  [2772]  = { barID = 3575,  barName = "Iron Bar",       oreIn = 1, barsOut = 1 }, -- Iron Ore
  [2776]  = { barID = 3577,  barName = "Gold Bar",       oreIn = 1, barsOut = 1 }, -- Gold Ore
  [3858]  = { barID = 3860,  barName = "Mithril Bar",    oreIn = 1, barsOut = 1 }, -- Mithril Ore
  [10620] = { barID = 12359, barName = "Thorium Bar",    oreIn = 1, barsOut = 1 }, -- Thorium Ore
  [7911]  = { barID = 6037,  barName = "Truesilver Bar", oreIn = 1, barsOut = 1 }, -- Truesilver Ore
}

-- True if this character has the Mining profession (spell 2575), cached like
-- GT.CanDisenchant. Mirrors the Enchanting detection (GetSpellInfo(7411)) and is
-- client-agnostic.
local mineCached, mineAt = nil, 0
function GT.CanMining()
  local now = GetTime()
  if mineCached ~= nil and (now - mineAt) < 30 then return mineCached end
  local yes = false
  if GetSpellInfo and GetNumSkillLines and GetSkillLineInfo then
    local mineName = GetSpellInfo(2575)
    if mineName then
      for i = 1, GetNumSkillLines() do
        local name = GetSkillLineInfo(i)
        if name == mineName then yes = true; break end
      end
    end
  end
  mineCached, mineAt = yes, now
  return yes
end

-- If `info` is a smeltable ore and the player can mine it, resolve the bar and
-- return the bar's per-ore disposition value when it exceeds the ore's own. The
-- bar is valued with the same rule engine (ValueItem), so it respects AH cut,
-- deposit, sell rate and the mat AH/vendor gate. Returns nil when not applicable
-- or when the bar is worth no more than the ore.
function GT.SmeltBetter(oreVal, info)
  if not oreVal or not info then return nil end
  local id = info.itemID or GT.ParseItemID(info.link)
  if not id then return nil end
  local s = GT.SMELT[id]
  if not s then return nil end
  if not (GT.CanMining and GT.CanMining()) then return nil end
  if not (GT.Prices and GT.Prices.Resolve) then return nil end
  local bar = GT.Prices.Resolve(s.barID)
  if not bar or bar.name ~= s.barName then return nil end
  local barVal = GT.ValueItem(bar, false)
  if not barVal or not barVal.unitCopper or barVal.unitCopper <= 0 then return nil end
  local perOre = floor(barVal.unitCopper * (s.barsOut or 1) / (s.oreIn or 1))
  if perOre <= 0 or perOre <= oreVal.unitCopper then return nil end
  return {
    unit = perOre,
    method = barVal.method,
    why = "smelt to " .. s.barName,
    barName = s.barName,
  }
end

-- Manual-smelt values for an ore itemID, for the Loot edit popup: the bar's
-- per-ore AH net and per-ore vendor price (one ore feeds one bar for the listed
-- smelts). Returns nil when not applicable (not a smeltable ore, not a miner, no
-- price source, or the bar won't resolve/name-match). A 0 value means the bar
-- has no such value (e.g. no AH data), so only the corresponding button enables.
-- Unlike GT.SmeltBetter, this reports the bar's own AH net even when the rule
-- engine would auto-prefer vendor, so the user can force the AH disposition.
function GT.SmeltBarVals(id)
  local s = GT.SMELT[id]
  if not s then return nil end
  if not (GT.CanMining and GT.CanMining()) then return nil end
  if not (GT.Prices and GT.Prices.Resolve) then return nil end
  local bar = GT.Prices.Resolve(s.barID)
  if not bar or bar.name ~= s.barName then return nil end
  local barVal = GT.ValueItem(bar, false)
  if not barVal then return nil end
  local n = (s.barsOut or 1) / (s.oreIn or 1)
  local perOre = function(v) return floor((v or 0) * n) end
  return {
    barName = s.barName,
    ah = perOre(barVal.ahNet or 0),
    vendor = perOre(bar.vendor or 0),
  }
end

-- info: table from Prices.Resolve + soulbound override
function GT.ValueItem(info, soulbound)
  local cfg = GoldTrackDB
  local vendor = info.vendor or 0
  local de = info.de or 0
  local quality = info.quality or 0
  local bindType = info.bindType or 0
  local stackCount = info.stackCount or 1
  local isDEable = info.isDEable
  local isRecipe = info.isRecipe

  local sellRate, sellSrc = 0.50, "fallback"
  local ahRaw = info.ahRaw
  local ahNet, deposit, lost, usedMode = nil, 0, 0, "if_sold"
  local ahEligible = false

  local bop = soulbound or bindType == 1 or bindType == 4

  if ahRaw and ahRaw > 0 and not bop and quality > 0 then
    if info.sellRate ~= nil then
      sellRate, sellSrc = info.sellRate, info.sellRateSource or "tsm"
    else
      sellRate, sellSrc = GT.Prices.GetSellRate(info.itemID or GT.ParseItemID(info.link), info.link)
    end
    if sellRate >= (cfg.ahMinSellRate or 0.10) then
      ahNet, deposit, lost, usedMode = GT.AHNet(ahRaw, vendor, sellRate, sellSrc)
      ahEligible = ahNet ~= nil
    end
  end

  local method, unit, why

  if quality == 0 then
    method, unit, why = "VENDOR", vendor, "grey -> vendor"
  elseif bop then
    local canDE = GT.CanDisenchant and GT.CanDisenchant()
    if canDE and de >= vendor + (cfg.deMinVsVendor or 10000) and de > 0 then
      method, unit, why = "DE", de, "BoP/soulbound: DE >= vendor+1g"
    elseif vendor > 0 then
      method, unit, why = "VENDOR", vendor, canDE and "BoP/soulbound: vendor" or "BoP: not an enchanter, vendor"
    else
      method, unit, why = "NONE", 0, canDE and "BoP/soulbound: no vendor, no DE" or "BoP: not an enchanter, no vendor"
    end
  else
    local matTrack = (not isDEable) and ((stackCount or 1) > 1 or isRecipe)
    if matTrack then
      -- Base verdict for the raw mat (ore): AH if it beats vendor, else vendor.
      if ahEligible and GT.MatBeatsVendor(ahNet, vendor) then
        method, unit, why = "AH", ahNet, "mat: net >= 3x vendor or vendor+1g"
      else
        method, unit, why = "VENDOR", vendor, "mat: AH gate failed"
      end
      -- Mined ore: if a miner can smelt it, the BAR may be worth more than the
      -- raw ore/mat (some servers post bars above ore). When it is, credit the
      -- ore at the bar's per-ore value. The bar is valued by the same rule
      -- engine, so AH cut, deposit, sell rate and the mat gate still apply.
      if GT.SMELT and GT.SMELT[info.itemID or GT.ParseItemID(info.link)] and GT.SmeltBetter then
        local smeltVal = GT.SmeltBetter({ unitCopper = unit or vendor or 0, method = method }, info)
        if smeltVal then
          method, unit, why = smeltVal.method, smeltVal.unit, smeltVal.why
        end
      end
    else
      local ahBetter = ahEligible
        and (ahNet >= vendor + (cfg.ahMinVsVendor or 100000))
        and (ahNet >= de + (cfg.ahMinVsDE or 100000))
      local deBetter = (de >= vendor + (cfg.deMinVsVendor or 10000)) and (not ahBetter) and de > 0
      if ahBetter then
        method, unit, why = "AH", ahNet, "gear: net >= vendor+10g and DE+10g"
      elseif deBetter then
        method, unit, why = "DE", de, "gear: DE >= vendor+1g, AH not better"
      else
        method, unit, why = "VENDOR", vendor, "gear: fallback vendor"
      end
    end
  end

  return {
    unitCopper = unit or 0,
    method = method,
    why = why,
    vendor = vendor,
    de = de,
    ahRaw = ahRaw or 0,
    ahNet = ahNet or 0,
    deposit = deposit,
    expectedLostDep = lost,
    ahMode = usedMode or "if_sold",
    cut = ahRaw and floor(ahRaw * GT.AHCut()) or 0,
    sellRate = sellRate,
    sellRateSource = sellSrc,
    soldPerDay = info.soldPerDay,
    quality = quality,
    texture = info.texture,
    name = info.name,
    link = info.link,
    stackCount = stackCount,
    bindType = bindType,
    isDEable = isDEable,
  }
end

-- Self-test uses pre-baked ahNet (no live prices)
local FIXTURES = {
  { n = "grey", q = 0, stack = 20, vendor = 5000, de = 0, ahNet = 50000, bop = false, deable = false, recipe = false, want = "VENDOR", cop = 5000 },
  { n = "bop DE", q = 2, stack = 1, vendor = 8000, de = 30000, ahNet = 400000, bop = true, deable = true, recipe = false, want = "DE", cop = 30000 },
  { n = "bop vendor", q = 2, stack = 1, vendor = 8000, de = 8000, ahNet = 400000, bop = true, deable = true, recipe = false, want = "VENDOR", cop = 8000 },
  { n = "bop none", q = 2, stack = 1, vendor = 0, de = 0, ahNet = 800000, bop = true, deable = true, recipe = false, want = "NONE", cop = 0 },
  { n = "gear AH", q = 2, stack = 1, vendor = 20000, de = 80000, ahNet = 250000, bop = false, deable = true, recipe = false, want = "AH", cop = 250000 },
  { n = "gear DE", q = 2, stack = 1, vendor = 20000, de = 80000, ahNet = 150000, bop = false, deable = true, recipe = false, want = "DE", cop = 80000 },
  { n = "gear vendor", q = 2, stack = 1, vendor = 110000, de = 0, ahNet = 120000, bop = false, deable = true, recipe = false, want = "VENDOR", cop = 110000 },
  { n = "runecloth", q = 1, stack = 20, vendor = 400, de = 0, ahNet = 1840, bop = false, deable = false, recipe = false, want = "AH", cop = 1840 },
  { n = "mote", q = 1, stack = 10, vendor = 0, de = 0, ahNet = 40000, bop = false, deable = false, recipe = false, want = "AH", cop = 40000 },
  { n = "mote low", q = 1, stack = 10, vendor = 0, de = 0, ahNet = 5000, bop = false, deable = false, recipe = false, want = "VENDOR", cop = 0 },
  { n = "junk white", q = 1, stack = 20, vendor = 10, de = 0, ahNet = 20, bop = false, deable = false, recipe = false, want = "VENDOR", cop = 10 },
  { n = "dust", q = 2, stack = 20, vendor = 0, de = 0, ahNet = 30000, bop = false, deable = false, recipe = false, want = "AH", cop = 30000 },
  { n = "thrown", q = 2, stack = 5, vendor = 5000, de = 80000, ahNet = 20000, bop = false, deable = true, recipe = false, want = "DE", cop = 80000 },
  { n = "recipe", q = 2, stack = 1, vendor = 0, de = 0, ahNet = 50000, bop = false, deable = false, recipe = true, want = "AH", cop = 50000 },
}

function GT.SelfTest()
  local pass, fail = 0, 0
  local saved = {
    ahMinVsVendor = GoldTrackDB.ahMinVsVendor,
    ahMinVsDE = GoldTrackDB.ahMinVsDE,
    deMinVsVendor = GoldTrackDB.deMinVsVendor,
    commonAhMult = GoldTrackDB.commonAhMult,
    commonAhFlat = GoldTrackDB.commonAhFlat,
    ahMinSellRate = GoldTrackDB.ahMinSellRate,
    ahValueMode = GoldTrackDB.ahValueMode,
    subtractDeposit = GoldTrackDB.subtractDeposit,
    ahDepositPreset = GoldTrackDB.ahDepositPreset,
    ahCut = GoldTrackDB.ahCut,
  }
  local savedCanDE = GT.CanDisenchant
  GoldTrackDB.ahMinVsVendor = 100000
  GoldTrackDB.ahMinVsDE = 100000
  GoldTrackDB.deMinVsVendor = 10000
  GoldTrackDB.commonAhMult = 3
  GoldTrackDB.commonAhFlat = 10000
  GoldTrackDB.ahMinSellRate = 0
  GoldTrackDB.ahValueMode = "if_sold"
  GoldTrackDB.subtractDeposit = false
  GoldTrackDB.ahDepositPreset = "ignore" -- deposit off; fixtures are cut-only
  GoldTrackDB.ahCut = "faction" -- keep 5% cut assumption in fixtures
  GT.CanDisenchant = function() return true end

  -- Runs the REAL rule engine (GT.ValueItem) with injected prices, so the
  -- fixtures cannot drift from production logic.
  for i = 1, #FIXTURES do
    local f = FIXTURES[i]
    local info = {
      vendor = f.vendor, de = f.de, ahRaw = f.ahNet,
      quality = f.q, bindType = f.bop and 1 or 0,
      stackCount = f.stack, isDEable = f.deable, isRecipe = f.recipe,
      name = f.n, itemID = 1,
      sellRate = 1, sellRateSource = "tsm", -- bypass live sell-rate lookup
    }
    local val = GT.ValueItem(info, false)
    -- AH rows net out the AH cut inside ValueItem; derive expected from raw.
    -- SelfTest forces ahCut="faction" (GT.AHCut()==0.05) so this stays exact.
    local wantCop = f.want == "AH"
      and (f.ahNet - math.floor(f.ahNet * GT.AHCut()))
      or f.cop
    if val.method == f.want and val.unitCopper == wantCop then
      pass = pass + 1
    else
      fail = fail + 1
      GT.Print(format("FAIL %s: got %s %d want %s %d",
        f.n, val.method, val.unitCopper or 0, f.want, wantCop))
    end
  end

  -- Smelt check: if this is a miner and Prices.Resolve is live, confirm an ore
  -- (Copper Ore, id 2770) can resolve to a smelted bar when the bar has value.
  -- Guarded so a non-miner or a missing price source skips it (never fails).
  if GT.CanMining and GT.CanMining() and GT.Prices and GT.Prices.Resolve then
    local smelt = GT.SmeltBetter({ unitCopper = 0, method = "VENDOR" },
      { itemID = 2770, link = "item:2770:0:0:0" })
    if smelt and smelt.unit > 0 and smelt.barName then
      pass = pass + 1
    end
    -- No fail branch: a miner behind a price source always has a Copper Bar with
    -- a vendor value on a live client, so a missing smelt means only that data
    -- is absent; do not count it against valuation correctness.
  end

  for k, v in pairs(saved) do GoldTrackDB[k] = v end
  GT.CanDisenchant = savedCanDE

  local st = GT.Prices.status
  GT.Print(format("selftest %d pass / %d fail  TSM:%s Atr:%s/%s  enchanter:%s",
    pass, fail,
    st.tsm and "yes" or "no",
    st.atr and "yes" or "no",
    st.atrLegacy and "legacy" or "-",
    GT.CanDisenchant() and "yes" or "no"))
  -- Live TSM probe (netherweave 21877)
  local id = 21877
  local rate, rsrc = GT.Prices.GetSellRate(id)
  local spd, ssrc = GT.Prices.GetSoldPerDay(id)
  GT.Print(format("TSM netherweave saleRate=%s (%s)  sold/day=%s (%s)",
    rate and format("%.2f", rate) or "nil", rsrc or "-",
    spd and format("%.2f", spd) or "nil", ssrc or "-"))
end
