--[[ GoldTrack — session ledger. Incremental totals, hard row cap. ]]
local GT = GoldTrack

local time = time

GT.Ledger = {}

local METHODS = { "AH", "DE", "VENDOR", "NONE", "GOLD" }

local function bump(by, method, delta)
  if not by[method] then by[method] = 0 end
  by[method] = by[method] + delta
end

local function ensure(s)
  if not s.rows then s.rows = {} end
  if not s.order then s.order = {} end
  if not s.byMethod then
    s.byMethod = { AH = 0, DE = 0, VENDOR = 0, NONE = 0, GOLD = 0 }
  end
end

function GT.Ledger.StripDEReagents()
  local s = GoldTrackCharDB and GoldTrackCharDB.session
  if not s or not s.rows or not GT.DE_REAGENT then return 0, 0 end
  local n, copper = 0, 0
  local keys = {}
  for key, row in pairs(s.rows) do
    if row.itemID and GT.DE_REAGENT[row.itemID] then
      keys[#keys + 1] = key
    end
  end
  for i = 1, #keys do
    local row = s.rows[keys[i]]
    if row then
      n = n + (row.count or 0)
      copper = copper + (row.count or 0) * (row.unitCopper or 0)
      GT.Ledger.Decrement(keys[i], row.count)
    end
  end
  return n, copper
end

function GT.Ledger.RefreshTSM()
  local s = GoldTrackCharDB and GoldTrackCharDB.session
  if not s or not s.rows then return 0, 0 end
  GT.Prices.Probe()
  local n, hit = 0, 0
  for _, row in pairs(s.rows) do
    if row.itemID and row.itemID > 0 and row.method ~= "GOLD" then
      n = n + 1
      local r, src = GT.Prices.GetSellRate(row.itemID, row.link)
      local spd = select(1, GT.Prices.GetSoldPerDay(row.itemID, row.link))
      row.sellRate = r
      row.sellRateSource = src
      row.soldPerDay = spd
      if src and src ~= "fallback" then hit = hit + 1 end
    end
  end
  return n, hit
end

-- val = result of GT.ValueItem
function GT.Ledger.CreditItem(mergeKey, count, val, source)
  if not mergeKey or not count or count <= 0 then return end
  local s = GoldTrackCharDB.session
  ensure(s)

  local row = s.rows[mergeKey]
  if row then
    local add = count * row.unitCopper
    row.count = row.count + count
    row.lastSeen = time()
    s.copper = s.copper + add
    s.items = s.items + count
    bump(s.byMethod, row.method, add)
    GT.Log("credit +%d %s (%s) frozen", count, row.name or mergeKey, row.method)
    GT.RefreshHUD()
    GT.RefreshMain()
    return row
  end

  if #s.order >= GT.LOOT_ROW_MAX then
    -- memory cap: still add copper into an overflow bucket
    mergeKey = "overflow"
    row = s.rows[mergeKey]
    if row then
      local add = count * (val.unitCopper or 0)
      row.count = row.count + count
      s.copper = s.copper + add
      s.items = s.items + count
      bump(s.byMethod, val.method or "NONE", add)
      GT.RefreshHUD()
      return row
    end
  end

  row = {
    key = mergeKey,
    itemID = val.itemID or GT.ParseItemID(val.link),
    name = val.name or "?",
    link = val.link,
    quality = val.quality or 0,
    texture = val.texture,
    count = count,
    unitCopper = val.unitCopper or 0,
    method = val.method or "NONE",
    vendor = val.vendor or 0,
    de = val.de or 0,
    ahRaw = val.ahRaw or 0,
    ahNet = val.ahNet or 0,
    deposit = val.deposit or 0,
    expectedLostDep = val.expectedLostDep or 0,
    ahMode = val.ahMode,
    cut = val.cut,
    sellRate = val.sellRate or 0,
    sellRateSource = val.sellRateSource or "none",
    soldPerDay = val.soldPerDay,
    why = val.why,
    firstSeen = time(),
    lastSeen = time(),
    source = source or "loot",
  }
  s.rows[mergeKey] = row
  s.order[#s.order + 1] = mergeKey
  local add = count * row.unitCopper
  s.copper = s.copper + add
  s.items = s.items + count
  bump(s.byMethod, row.method, add)
  GT.Log("credit new %s x%d %s %s", row.name, count, row.method, GT.FormatCopper(add))
  GT.RefreshHUD()
  GT.RefreshMain()
  return row
end

function GT.Ledger.CreditGold(copper, source)
  if not copper or copper <= 0 then return end
  local s = GoldTrackCharDB.session
  ensure(s)
  local key = "gold"
  local row = s.rows[key]
  if not row then
    row = {
      key = key,
      itemID = 0,
      name = "Coin loot",
      link = nil,
      quality = 1,
      texture = "Interface\\Icons\\INV_Misc_Coin_01",
      count = 0,
      unitCopper = 1,
      method = "GOLD",
      vendor = 0, de = 0, ahRaw = 0, ahNet = 0,
      deposit = 0, expectedLostDep = 0,
      sellRate = 0, sellRateSource = "none",
      why = "world coin",
      firstSeen = time(),
      lastSeen = time(),
      source = source or "money",
    }
    s.rows[key] = row
    -- pin gold at front
    table.insert(s.order, 1, key)
  end
  row.count = row.count + copper
  row.lastSeen = time()
  s.copper = s.copper + copper
  bump(s.byMethod, "GOLD", copper)
  GT.Log("credit gold %s", GT.FormatCopper(copper))
  GT.RefreshHUD()
  GT.RefreshMain()
end

-- Remove one (or n) units of a row; used by OPEN replace
function GT.Ledger.Decrement(mergeKey, n)
  n = n or 1
  local s = GoldTrackCharDB.session
  local row = s.rows[mergeKey]
  if not row or n <= 0 then return 0 end
  if n > row.count then n = row.count end
  local sub = n * row.unitCopper
  row.count = row.count - n
  s.copper = s.copper - sub
  if row.method ~= "GOLD" then s.items = s.items - n end
  bump(s.byMethod, row.method, -sub)
  if row.count <= 0 then
    s.rows[mergeKey] = nil
    local order = s.order
    for i = 1, #order do
      if order[i] == mergeKey then
        table.remove(order, i)
        break
      end
    end
  end
  GT.RefreshHUD()
  GT.RefreshMain()
  return n
end

function GT.Ledger.FindOpenableRow(itemID)
  local s = GoldTrackCharDB.session
  if not s.rows then return nil end
  -- prefer exact itemID match on any mergeKey prefix
  local prefix = tostring(itemID) .. ":"
  for key, row in pairs(s.rows) do
    if row.itemID == itemID or (type(key) == "string" and key:sub(1, #prefix) == prefix) then
      return key, row
    end
  end
  return nil
end

-- Manual override. Session copper / byMethod / g/h update immediately.
function GT.Ledger.Override(mergeKey, method, unitCopper)
  local s = GoldTrackCharDB and GoldTrackCharDB.session
  if not s or not s.rows then return end
  local row = s.rows[mergeKey]
  if not row then return end
  local old = (row.count or 0) * (row.unitCopper or 0)
  bump(s.byMethod, row.method, -old)
  s.copper = (s.copper or 0) - old
  if row.origMethod == nil then
    row.origMethod = row.method
    row.origUnit = row.unitCopper
    row.origCount = row.count
  end
  if method and method ~= "" then row.method = method end
  if unitCopper ~= nil then
    if unitCopper < 0 then unitCopper = 0 end
    if row.method == "GOLD" then
      row.unitCopper = 1
      row.count = math.floor(unitCopper + 0.5)
    else
      row.unitCopper = math.floor(unitCopper + 0.5)
    end
  end
  row.manual = true
  row.why = "manual override"
  local neu = (row.count or 0) * (row.unitCopper or 0)
  s.copper = s.copper + neu
  bump(s.byMethod, row.method, neu)
  GT.RefreshHUD()
  GT.RefreshMain()
  return row
end

function GT.Ledger.RevertOverride(mergeKey)
  local s = GoldTrackCharDB and GoldTrackCharDB.session
  local row = s and s.rows and s.rows[mergeKey]
  if not row or row.origMethod == nil then return end
  local old = (row.count or 0) * (row.unitCopper or 0)
  bump(s.byMethod, row.method, -old)
  s.copper = (s.copper or 0) - old
  row.method = row.origMethod
  row.unitCopper = row.origUnit
  if row.origCount then row.count = row.origCount end
  row.manual = nil
  row.why = "reverted to loot-time"
  local neu = (row.count or 0) * (row.unitCopper or 0)
  s.copper = s.copper + neu
  bump(s.byMethod, row.method, neu)
  GT.RefreshHUD()
  GT.RefreshMain()
  return row
end

function GT.Ledger.ApplyPending(mergeKey, val)
  local s = GoldTrackCharDB.session
  local row = s.rows[mergeKey]
  if not row or row.method ~= "PENDING" then return end
  local old = row.count * row.unitCopper
  bump(s.byMethod, row.method, -old)
  s.copper = s.copper - old
  row.unitCopper = val.unitCopper or 0
  row.method = val.method or "NONE"
  row.vendor = val.vendor or 0
  row.de = val.de or 0
  row.ahRaw = val.ahRaw or 0
  row.ahNet = val.ahNet or 0
  row.deposit = val.deposit or 0
  row.expectedLostDep = val.expectedLostDep or 0
  row.sellRate = val.sellRate or 0
  row.sellRateSource = val.sellRateSource or "none"
  row.why = val.why
  row.name = val.name or row.name
  row.link = val.link or row.link
  row.quality = val.quality or row.quality
  row.texture = val.texture or row.texture
  local neu = row.count * row.unitCopper
  s.copper = s.copper + neu
  bump(s.byMethod, row.method, neu)
  GT.RefreshHUD()
  GT.RefreshMain()
end

function GT.Ledger.ArchiveCurrent()
  local s = GoldTrackCharDB.session
  local t = GoldTrackCharDB.total
  GT.FoldSegment()
  local ms = s.activeMs or 0
  t.copper = (t.copper or 0) + (s.copper or 0)
  t.items = (t.items or 0) + (s.items or 0)
  t.activeMs = (t.activeMs or 0) + ms
  t.sessionsCompleted = (t.sessionsCompleted or 0) + 1
  for i = 1, #METHODS do
    local m = METHODS[i]
    t.byMethod[m] = (t.byMethod[m] or 0) + (s.byMethod[m] or 0)
  end
  local gh = GT.GPerHour(s.copper, ms)
  if (s.copper or 0) > (t.bestSessionCopper or 0) then
    t.bestSessionCopper = s.copper
  end
  if gh and gh > (t.bestSessionGh or 0) then
    t.bestSessionGh = gh
  end
  local arch = t.archives
  if not arch then arch = {}; t.archives = arch end
  arch[#arch + 1] = {
    t = s.startedAt or time(),
    zone = s.zone or "",
    ms = ms,
    copper = s.copper or 0,
    items = s.items or 0,
    gh = gh or 0,
    byMethod = {
      AH = s.byMethod.AH or 0, DE = s.byMethod.DE or 0,
      VENDOR = s.byMethod.VENDOR or 0, GOLD = s.byMethod.GOLD or 0,
    },
  }
  while #arch > GT.ARCHIVE_MAX do
    table.remove(arch, 1)
  end
end

function GT.Ledger.SortedKeys(sortKey)
  local s = GoldTrackCharDB.session
  ensure(s)
  local keys = {}
  local n = 0
  for i = 1, #s.order do
    local k = s.order[i]
    if s.rows[k] then
      n = n + 1
      keys[n] = k
    end
  end
  if sortKey == "name" then
    table.sort(keys, function(a, b)
      return (s.rows[a].name or "") < (s.rows[b].name or "")
    end)
  elseif sortKey == "qty" then
    table.sort(keys, function(a, b)
      return (s.rows[a].count or 0) > (s.rows[b].count or 0)
    end)
  elseif sortKey == "method" then
    table.sort(keys, function(a, b)
      return (s.rows[a].method or "") < (s.rows[b].method or "")
    end)
  else
    table.sort(keys, function(a, b)
      if a == "gold" then return true end
      if b == "gold" then return false end
      local va = (s.rows[a].count or 0) * (s.rows[a].unitCopper or 0)
      local vb = (s.rows[b].count or 0) * (s.rows[b].unitCopper or 0)
      if va == vb then return (s.rows[a].name or "") < (s.rows[b].name or "") end
      return va > vb
    end)
  end
  return keys
end
