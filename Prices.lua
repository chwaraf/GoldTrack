--[[ GoldTrack — Auctionator / TSM / GetItemInfo adapters + tiny TTL cache ]]
local GT = GoldTrack

local GetItemInfo = GetItemInfo
local GetTime = GetTime
local pcall = pcall
local floor = math.floor

local cache = {}
local cacheN = 0
local CALLER = "GoldTrack"

GT.Prices = {}
GT.Prices.status = { tsm = false, atr = false, atrLegacy = false, sellrate = "none" }

local function cacheGet(id)
  local e = cache[id]
  if not e then return nil end
  if (GetTime() - e.t) > GT.PRICE_CACHE_TTL then
    cache[id] = nil
    cacheN = cacheN - 1
    return nil
  end
  return e
end

local function cachePut(id, e)
  if not cache[id] then
    if cacheN >= GT.PRICE_CACHE_MAX then
      -- cheap eviction: drop the whole table (avoids LRU bookkeeping)
      wipe(cache)
      cacheN = 0
    end
    cacheN = cacheN + 1
  end
  e.t = GetTime()
  cache[id] = e
end

function GT.Prices.Invalidate()
  wipe(cache)
  cacheN = 0
end

local function tsmItem(itemID, link)
  if TSM_API and TSM_API.ToItemString then
    local ok, s = pcall(TSM_API.ToItemString, link or ("i:" .. itemID))
    if ok and s then return s end
    ok, s = pcall(TSM_API.ToItemString, "i:" .. itemID)
    if ok and s then return s end
  end
  if link then return link end
  return "i:" .. itemID
end

-- nil = missing; 0 is a valid value (0% sell rate, 0 copper)
local function tsmValue(priceString, itemID, link)
  if not itemID then return nil end
  local item = tsmItem(itemID, link)
  local variants = { item, "i:" .. itemID }
  local apis = {}
  if TSM_API and TSM_API.GetCustomPriceValue then
    apis[#apis + 1] = function(str, it)
      return TSM_API.GetCustomPriceValue(str, it)
    end
  end
  if TSMAPI and TSMAPI.GetCustomPriceValue then
    apis[#apis + 1] = function(str, it)
      return TSMAPI:GetCustomPriceValue(str, it)
    end
  end
  if TSMAPI_FOUR and TSMAPI_FOUR.CustomPrice and TSMAPI_FOUR.CustomPrice.GetValue then
    apis[#apis + 1] = function(str, it)
      return TSMAPI_FOUR.CustomPrice.GetValue(str, it)
    end
  end
  for a = 1, #apis do
    for v = 1, #variants do
      local ok, val = pcall(apis[a], priceString, variants[v])
      if ok and val ~= nil then return val end
    end
  end
  return nil
end

local function atrAuction(itemID, link)
  if Auctionator and Auctionator.API and Auctionator.API.v1 then
    local api = Auctionator.API.v1
    if api.GetAuctionPriceByItemID then
      local ok, v = pcall(api.GetAuctionPriceByItemID, CALLER, itemID)
      if ok and v and v > 0 then return v end
    end
    if link and api.GetAuctionPriceByItemLink then
      local ok, v = pcall(api.GetAuctionPriceByItemLink, CALLER, link)
      if ok and v and v > 0 then return v end
    end
  end
  if Atr_GetAuctionBuyout then
    local ok, v = pcall(Atr_GetAuctionBuyout, link or itemID)
    if ok and v and v > 0 then return v end
  end
  if Atr_GetAuctionPrice then
    local name = itemID and GetItemInfo(itemID)
    if name then
      local ok, v = pcall(Atr_GetAuctionPrice, name)
      if ok and v and v > 0 then return v end
    end
  end
  return nil
end

local function atrDE(itemID, link, classID, quality, ilvl)
  if Auctionator and Auctionator.API and Auctionator.API.v1 then
    local api = Auctionator.API.v1
    if api.GetDisenchantPriceByItemID then
      local ok, v = pcall(api.GetDisenchantPriceByItemID, CALLER, itemID)
      if ok and v and v > 0 then return v end
    end
    if link and api.GetDisenchantPriceByItemLink then
      local ok, v = pcall(api.GetDisenchantPriceByItemLink, CALLER, link)
      if ok and v and v > 0 then return v end
    end
  end
  if Atr_GetDisenchantValue then
    local ok, v = pcall(Atr_GetDisenchantValue, link or itemID)
    if ok and v and v > 0 then return v end
  end
  if Atr_CalcDisenchantPrice and classID and quality and ilvl then
    local ok, v = pcall(Atr_CalcDisenchantPrice, classID, quality, ilvl)
    if ok and v and v > 0 then return v end
  end
  return nil
end

local RATE_SOURCES = {
  "DBRegionSaleRate", "dbregionsalerate",
  "SaleRate", "salerate",
}

local SOLD_SOURCES = {
  "DBRegionSoldPerDay", "dbregionsoldperday",
}

-- TSM may return 0.35, 35 (%), or 3500 (rate*1g copper). 0 is valid.
local function normalizeRate(v)
  if v == nil then return nil end
  v = tonumber(v)
  if not v then return nil end
  if v > 100 then
    v = v / 10000
  elseif v > 1 then
    v = v / 100
  end
  if v < 0 then v = 0 end
  if v > 1 then v = 1 end
  return v
end

function GT.Prices.GetSellRate(itemID, link)
  GT.Prices.Probe()
  local cfg = GoldTrackDB
  for i = 1, #RATE_SOURCES do
    local src = RATE_SOURCES[i]
    local raw = tsmValue(src, itemID, link)
    if raw == nil then
      raw = tsmValue(src .. "*1g", itemID, link)
    end
    local r = normalizeRate(raw)
    if r ~= nil then
      GT.Prices.status.sellrate = src
      return r, src
    end
  end
  GT.Prices.status.sellrate = "fallback"
  return cfg.ahUnknownSellRate or 0.50, "fallback"
end

function GT.Prices.GetSoldPerDay(itemID, link)
  for i = 1, #SOLD_SOURCES do
    local raw = tsmValue(SOLD_SOURCES[i], itemID, link)
    if raw == nil then
      raw = tsmValue(SOLD_SOURCES[i] .. "*1g", itemID, link)
    end
    raw = tonumber(raw)
    if raw and raw >= 0 then
      if raw > 1000 then raw = raw / 10000 end
      return raw, SOLD_SOURCES[i]
    end
  end
  return nil, nil
end

local function firstPositive(...)
  local n = select("#", ...)
  for i = 1, n do
    local v = select(i, ...)
    if v and v > 0 then return v end
  end
  return nil
end

-- TSM custom-price strings per config field.
local TSM_FIELDS = {
  minbuyout = { "DBMinBuyout", "dbminbuyout" },
  recent = { "DBRecent", "dbrecent" },
  market = { "DBMarket", "dbmarket", "DBRegionMarketAvg", "dbregionmarketavg" },
  historical = { "DBHistorical", "dbhistorical", "DBRegionHistorical", "dbregionhistorical" },
  regionsaleavg = { "DBRegionSaleAvg", "dbregionsaleavg" },
}

local function tsmByField(field, itemID, link)
  local list = TSM_FIELDS[field or "market"] or TSM_FIELDS.market
  for i = 1, #list do
    local v = tsmValue(list[i], itemID, link)
    if v and v > 0 then return v, list[i] end
  end
  return nil, nil
end

-- Auctionator scan age in seconds, or nil if unknown.
local function atrAgeSec(itemID, link)
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  local function take(fn, ...)
    if not fn then return nil end
    local ok, v = pcall(fn, ...)
    if not ok or type(v) ~= "number" or v < 0 then return nil end
    -- unix timestamp
    if v > 1000000000 then
      local age = time() - v
      return age >= 0 and age or nil
    end
    -- seconds (just scanned to weeks)
    if v > 48 then return v end
    -- 0-48: Auctionator GetAuctionAge is days on some builds, hours on none.
    -- Treat as days so 1 = 24h (not fresh for a 2h gate). 0 = today / just scanned.
    return v * 86400
  end
  if api then
    local a = take(api.GetAuctionAgeByItemID, CALLER, itemID)
    if a then return a end
    if link then
      a = take(api.GetAuctionAgeByItemLink, CALLER, link)
      if a then return a end
    end
  end
  local stamps = {}
  local st = Auctionator and Auctionator.SavedState
  if type(st) == "table" then
    stamps[#stamps + 1] = st.TimeOfLastSnapshot
    stamps[#stamps + 1] = st.TimeOfLastFullScan
    stamps[#stamps + 1] = st.TimeOfLastBrowseScan
    stamps[#stamps + 1] = st.timeOfLastScan
  end
  if type(AUCTIONATOR_SAVEDVARS) == "table" then
    stamps[#stamps + 1] = AUCTIONATOR_SAVEDVARS.LastScanTime
  end
  if Auctionator and Auctionator.Variables then
    stamps[#stamps + 1] = Auctionator.Variables.LastFullScanTime
  end
  if Auctionator and Auctionator.Config and Auctionator.Config.Get then
    local ok, v = pcall(Auctionator.Config.Get, "last_full_scan")
    if ok then stamps[#stamps + 1] = v end
  end
  for i = 1, #stamps do
    local t = stamps[i]
    if type(t) == "number" and t > 1000000000 then
      local age = time() - t
      if age >= 0 then return age end
    end
  end
  return nil
end

function GT.Prices.AtrIsFresh(itemID, link)
  local hours = (GoldTrackDB and GoldTrackDB.atrFreshHours) or 2
  local age = atrAgeSec(itemID, link)
  if age == nil then return false, nil end
  return age < hours * 3600, age
end

function GT.Prices.Resolve(itemID, link)
  local hit = cacheGet(itemID)
  if hit then return hit end

  local name, ilink, quality, ilvl, _, itemType, _, stackCount, _, texture, sellPrice, classID, subClass, bindType =
    GetItemInfo(link or itemID)

  if not name then
    return nil
  end
  link = ilink or link

  local cfg = GoldTrackDB
  local vendor = sellPrice -- authoritative, may be 0
  if vendor == nil then
    vendor = tsmValue("vendorsell", itemID)
  end

  local tsmField = cfg.tsmPriceField or "market"
  local order = cfg.priceSource or "atr_fresh_tsm"
  local tsmVal, tsmTag, market, minbuy, atr

  if order ~= "atr_only" then
    tsmVal, tsmTag = tsmByField(tsmField, itemID, link)
    market = select(1, tsmByField("market", itemID, link))
    minbuy = select(1, tsmByField("minbuyout", itemID, link))
  end
  if order ~= "tsm_only" then
    atr = atrAuction(itemID, link)
  end

  if tsmField == "minbuyout" and tsmVal and market and tsmVal < 0.30 * market then
    tsmVal, tsmTag = nil, nil
  end
  if minbuy and market and minbuy < 0.30 * market then
    minbuy = nil
  end

  local ahRaw, ahSource
  if order == "atr_fresh_tsm" then
    local fresh = atr and select(1, GT.Prices.AtrIsFresh(itemID, link))
    if fresh then
      ahRaw, ahSource = atr, "atr"
    else
      ahRaw, ahSource = tsmVal, tsmTag
      if not ahRaw then ahRaw, ahSource = atr, atr and "atr" or nil end
    end
  elseif order == "atr_then_tsm" then
    ahRaw, ahSource = atr, atr and "atr" or nil
    if not ahRaw then ahRaw, ahSource = tsmVal, tsmTag end
  elseif order == "atr_only" then
    ahRaw, ahSource = atr, atr and "atr" or nil
  elseif order == "tsm_only" then
    ahRaw, ahSource = tsmVal, tsmTag
  else
    ahRaw, ahSource = tsmVal, tsmTag
    if not ahRaw then ahRaw, ahSource = atr, atr and "atr" or nil end
  end

  -- Legacy combined field, only when TSM field did not already pick a value.
  if not tsmVal and order ~= "atr_fresh_tsm" and order ~= "tsm_only" then
    local field = cfg.ahPriceField or "conservative"
    if field == "market" then
      ahRaw = firstPositive(market, atr)
    elseif field == "minbuyout" then
      ahRaw = firstPositive(minbuy, atr, market)
    end
  end

  local isDEable = (quality or 0) >= 2 and GT.IsArmorOrWeapon(classID, itemType)
  local de
  if isDEable then
    de = firstPositive(
      tsmValue("Destroy", itemID), tsmValue("destroy", itemID),
      tsmValue("Disenchant", itemID)
    )
    if not de then
      de = atrDE(itemID, link, classID, quality, ilvl)
    end
  end

  local e = {
    name = name,
    link = link,
    quality = quality or 0,
    ilvl = ilvl or 0,
    itemType = itemType,
    stackCount = stackCount or 1,
    texture = texture,
    sellPrice = vendor or 0,
    classID = classID,
    subClass = subClass,
    bindType = bindType or 0,
    isDEable = isDEable,
    isRecipe = GT.IsRecipeClass(classID, itemType),
    ahRaw = ahRaw,
    de = de,
    vendor = vendor or 0,
    ahSource = ahSource or (market and "market" or (atr and "atr" or (minbuy and "minbuyout" or nil))),
    sellRate = nil,
    soldPerDay = nil,
  }
  local sr, ss = GT.Prices.GetSellRate(itemID, link)
  e.sellRate, e.sellRateSource = sr, ss
  e.soldPerDay = select(1, GT.Prices.GetSoldPerDay(itemID, link))
  cachePut(itemID, e)
  return e
end

function GT.Prices.Probe()
  GT.Prices.status.tsm = not not ((TSM_API and TSM_API.GetCustomPriceValue) or TSMAPI or TSMAPI_FOUR)
  GT.Prices.status.atr = not not (Auctionator and Auctionator.API and Auctionator.API.v1)
  GT.Prices.status.atrLegacy = not not Atr_GetAuctionBuyout
  if Auctionator and Auctionator.API and Auctionator.API.v1 and Auctionator.API.v1.RegisterForDBUpdate then
    pcall(Auctionator.API.v1.RegisterForDBUpdate, CALLER, function()
      GT.Prices.Invalidate()
    end)
  end
end

function GT.IsArmorOrWeapon(classID, itemType)
  if classID == 2 or classID == 4 then return true end
  -- classID missing: last resort, English client only (TBC GetItemInfo usually has classID)
  return itemType == "Weapon" or itemType == "Armor"
end

function GT.IsRecipeClass(classID, itemType)
  if classID == 9 then return true end
  return itemType == "Recipe"
end

function GT.ParseItemID(link)
  if not link then return nil end
  if type(link) == "number" then return link end
  return tonumber(link:match("item:(%d+)"))
end

function GT.MergeKey(link)
  if not link then return nil end
  if type(link) == "number" then return link .. ":0:0" end
  local id, ench, suffix = link:match("item:(%d+):(%d*):(%d*):")
  if not id then
    id = link:match("item:(%d+)")
    if not id then return nil end
    return id .. ":0:0"
  end
  if ench == "" then ench = "0" end
  if suffix == "" then suffix = "0" end
  return id .. ":" .. ench .. ":" .. suffix
end
