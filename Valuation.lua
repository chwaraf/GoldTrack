--[[ GoldTrack — valuation rule engine ]]
local GT = GoldTrack

local floor = math.floor

local DEPOSIT_PCT = {
  ignore = 0,
  ["12h_15"] = 0.15,
  ["24h_30"] = 0.30,
  ["48h_60"] = 0.60,
}

function GT.DepositPercent()
  local cfg = GoldTrackDB
  if not cfg.subtractDeposit then return 0 end
  local p = cfg.ahDepositPreset or "24h_30"
  if p == "custom" then return cfg.ahDepositPercent or 0.30 end
  if p == "ignore" then return 0 end
  return DEPOSIT_PCT[p] or 0.30
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
  local cut = floor(ahRaw * 0.05)
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
      if ahEligible and GT.MatBeatsVendor(ahNet, vendor) then
        method, unit, why = "AH", ahNet, "mat: net >= 3x vendor or vendor+1g"
      else
        method, unit, why = "VENDOR", vendor, "mat: AH gate failed"
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
    cut = ahRaw and floor(ahRaw * 0.05) or 0,
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
    -- AH rows net out the 5% cut inside ValueItem; derive expected from raw.
    local wantCop = f.want == "AH"
      and (f.ahNet - math.floor(f.ahNet * 0.05))
      or f.cop
    if val.method == f.want and val.unitCopper == wantCop then
      pass = pass + 1
    else
      fail = fail + 1
      GT.Print(format("FAIL %s: got %s %d want %s %d",
        f.n, val.method, val.unitCopper or 0, f.want, wantCop))
    end
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
