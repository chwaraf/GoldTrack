--[[ GoldTrack — loot classifier. Cheap early-outs; bags only for OPEN. ]]
local GT = GoldTrack

local GetTime = GetTime
local tonumber, floor = tonumber, math.floor
GT.Events = {}

local deName, prospectName
local encWindowUntil = 0
local destroyUntil = 0

-- Vanilla + TBC disenchant / prospect outputs. Never credit these while
-- DEing or while the Enchanting trade skill is open.
local DE_REAGENT = {
  -- dust
  [10940] = true, [11083] = true, [11137] = true, [11176] = true, [16204] = true,
  [22445] = true, -- Arcane Dust
  -- essence
  [10938] = true, [10939] = true, [10998] = true, [11082] = true,
  [11134] = true, [11135] = true, [11174] = true, [11175] = true,
  [16202] = true, [16203] = true, -- Lesser/Greater Eternal
  [22447] = true, [22446] = true, -- Lesser/Greater Planar
  -- shards
  [10978] = true, [11084] = true, [11138] = true, [11139] = true,
  [11177] = true, [11178] = true, [14343] = true, [14344] = true, -- Small/Large Brilliant
  [22448] = true, [22449] = true, -- Small/Large Prismatic
  -- crystals
  [20725] = true, -- Nexus Crystal
  [22450] = true, -- Void Crystal
  -- common TBC prospect gems (ignore after prospect spell only; also listed)
  [21929] = true, [23077] = true, [23079] = true, [23107] = true,
  [23112] = true, [23117] = true, [23436] = true, [23437] = true,
  [23438] = true, [23439] = true, [23440] = true, [23441] = true,
}

GT.DE_REAGENT = DE_REAGENT

local function markDestroy(why)
  destroyUntil = GetTime() + (GT.DESTROY_SUPPRESS or 5)
  GT.Log("destroy suppress (%s)", why or "?")
end

local function enchantingWindowOpen()
  if GetTime() < encWindowUntil then return true end
  if not GetTradeSkillLine then return false end
  local line = GetTradeSkillLine()
  if not line or line == "UNKNOWN" then return false end
  local enc = GetSpellInfo(7411)
  return enc and line == enc
end

local function isDestroyOutput(itemID)
  return itemID and DE_REAGENT[itemID]
end

-- Known TBC openables (itemID set)
local OPENABLE = {
  [5523] = true, [5524] = true, [7973] = true, [15874] = true, [24476] = true,
  [20766] = true, [20767] = true, [20768] = true,
  [16882] = true, [16883] = true, [16884] = true, [16885] = true,
  [4632] = true, [4633] = true, [4634] = true, [4636] = true, [4637] = true, [4638] = true,
  [5758] = true, [5759] = true, [5760] = true, [31952] = true,
  [6351] = true, [6352] = true, [6353] = true, [6354] = true, [6355] = true, [6356] = true, [6357] = true,
  [13874] = true, [20708] = true, [21113] = true, [21150] = true, [21228] = true,
  [27511] = true, [27513] = true, [11018] = true,
  [21746] = true, -- lucky red envelope (harmless if unused)
}

local openableCache = {} -- [itemID] = true/false
local openableCacheN = 0

local PAT = {}
local moneyPat = {}

local transfer = 0
local transferUntil = 0
local lootFrameUntil = 0
local gatherUntil = 0
local questUntil = 0

local pendingOpen = {} -- array of {itemID, key, t, hadLootFrame, ownsFrame, decremented}
local pendingN = 0

local pendingInfo = {} -- [mergeKey] = {count, source, link, itemID}
local pendingInfoN = 0

-- openable qty + farmed DE-able gear qty (bags 0-4 + keyring only)
local openQty = {}
local farmGearQty = {}
local bagDirty = false
local bagDirtyAt = 0

-- circular dedup
local dedupKey = {}
local dedupT = {}
local dedupI = 0

local GetBagSlots, GetBagLink
local KEYRING = KEYRING_CONTAINER or -2
local BAGS = { 0, 1, 2, 3, 4, KEYRING }

local GATHER_SPELL = {
  [2366] = true, [2368] = true, [3570] = true, [11993] = true, [28695] = true, -- herb
  [2575] = true, [2576] = true, [3564] = true, [10248] = true, [29354] = true, -- mine
  [8613] = true, [8617] = true, [8618] = true, [10768] = true, [32678] = true, -- skin
  [7620] = true, [7731] = true, [7732] = true, [18248] = true, [33095] = true, -- fish
  [30427] = true, -- extract gas
}

local function esc(s)
  return (s:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"))
end

local function compile(globalName)
  local s = _G[globalName]
  if not s then return nil end
  s = esc(s)
  s = s:gsub("%%%%s", "(.+)")
  s = s:gsub("%%%%d", "(%%d+)")
  return "^" .. s
end

local function compileAll()
  PAT.self = compile("LOOT_ITEM_SELF")
  PAT.selfN = compile("LOOT_ITEM_SELF_MULTIPLE")
  PAT.push = compile("LOOT_ITEM_PUSHED_SELF")
  PAT.pushN = compile("LOOT_ITEM_PUSHED_SELF_MULTIPLE")
  PAT.created = compile("LOOT_ITEM_CREATED_SELF")
  PAT.createdN = compile("LOOT_ITEM_CREATED_SELF_MULTIPLE")
  moneyPat.you = compile("YOU_LOOT_MONEY")
  moneyPat.split = compile("LOOT_MONEY_SPLIT")
  GT.MoneyInit()
end

local function inTransfer()
  return transfer > 0 or GetTime() < transferUntil
end

local function lootRecent()
  return GetTime() < lootFrameUntil
end

local function seen(key)
  local now = GetTime()
  local n = GT.DEDUP_SIZE
  for i = 1, n do
    local k = dedupKey[i]
    if k == key and dedupT[i] and (now - dedupT[i]) < GT.DEDUP_TTL then
      return true
    end
  end
  dedupI = dedupI + 1
  if dedupI > n then dedupI = 1 end
  dedupKey[dedupI] = key
  dedupT[dedupI] = now
  return false
end

local function initBags()
  if C_Container and C_Container.GetContainerNumSlots then
    GetBagSlots = C_Container.GetContainerNumSlots
    GetBagLink = C_Container.GetContainerItemLink
  else
    GetBagSlots = GetContainerNumSlots
    GetBagLink = GetContainerItemLink
  end
end

local scanTip
local function isOpenable(itemID, link)
  if not itemID then return false end
  if OPENABLE[itemID] then return true end
  local c = openableCache[itemID]
  if c ~= nil then return c end
  if not link then return false end
  if not scanTip then
    scanTip = CreateFrame("GameTooltip", "GoldTrackScanTip", nil, "GameTooltipTemplate")
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
  end
  scanTip:ClearLines()
  scanTip:SetHyperlink(link)
  local yes = false
  local needle = _G.ITEM_OPENABLE
  for i = 2, scanTip:NumLines() do
    local fs = _G["GoldTrackScanTipTextLeft" .. i]
    local t = fs and fs:GetText()
    if t then
      if needle and t:find(needle, 1, true) then yes = true; break end
      if t:find("Open", 1, true) and t:find("Use:", 1, true) then yes = true; break end
    end
  end
  if openableCacheN >= GT.OPENABLE_CACHE_MAX then
    wipe(openableCache)
    openableCacheN = 0
  end
  openableCache[itemID] = yes
  openableCacheN = openableCacheN + 1
  return yes
end

local function slotCount(bag, slot)
  if GetContainerItemInfo then
    local _, c = GetContainerItemInfo(bag, slot)
    return c or 1
  elseif C_Container and C_Container.GetContainerItemInfo then
    local info = C_Container.GetContainerItemInfo(bag, slot)
    return info and info.stackCount or 1
  end
  return 1
end

local function sessionGearIDs()
  local ids = {}
  local s = GoldTrackCharDB and GoldTrackCharDB.session
  if not s or not s.rows then return ids end
  for _, row in pairs(s.rows) do
    if row.itemID and row.itemID > 0 and not DE_REAGENT[row.itemID]
      and (row.quality or 0) >= 2
      and row.method ~= "GOLD" and row.method ~= "PENDING" then
      ids[row.itemID] = true
    end
  end
  return ids
end

local function recountOpenables()
  wipe(openQty)
  wipe(farmGearQty)
  if not GetBagSlots then initBags() end
  local gear = sessionGearIDs()
  for i = 1, #BAGS do
    local bag = BAGS[i]
    local slots = GetBagSlots(bag)
    if slots and slots > 0 then
      for slot = 1, slots do
        local link = GetBagLink(bag, slot)
        if link then
          local id = GT.ParseItemID(link)
          if id then
            local count = slotCount(bag, slot)
            if OPENABLE[id] or openableCache[id] then
              openQty[id] = (openQty[id] or 0) + count
            end
            if gear[id] then
              farmGearQty[id] = (farmGearQty[id] or 0) + count
            end
          end
        end
      end
    end
  end
end

local function pushOpen(itemID, n, hadFrame)
  local key = select(1, GT.Ledger.FindOpenableRow(itemID))
  for _ = 1, n do
    if pendingN >= 8 then break end
    pendingN = pendingN + 1
    pendingOpen[pendingN] = {
      itemID = itemID,
      key = key,
      t = GetTime(),
      hadLootFrame = hadFrame,
      ownsFrame = false,
      decremented = false,
    }
  end
  if GT.Events.NeedPoll then GT.Events.NeedPoll() end
end

local function oldestPending(now)
  local best, idx
  for i = 1, pendingN do
    local p = pendingOpen[i]
    if p and (now - p.t) < GT.OPEN_TTL then
      if not best or p.t < best.t then
        best, idx = p, i
      end
    end
  end
  return best, idx
end

local function popPending(idx)
  table.remove(pendingOpen, idx)
  pendingN = pendingN - 1
end

local function expirePending()
  local now = GetTime()
  local i = 1
  while i <= pendingN do
    local p = pendingOpen[i]
    if (now - p.t) >= GT.OPEN_TTL then
      if p.key and not p.decremented then
        GT.Ledger.Decrement(p.key, 1)
        p.decremented = true
      end
      popPending(i)
    else
      i = i + 1
    end
  end
end

local function replacePath(p)
  if p.key and not p.decremented then
    GT.Ledger.Decrement(p.key, 1)
    p.decremented = true
  end
  return p.key ~= nil -- false → swallow
end

local function valueAndCredit(link, count, source)
  local itemID = GT.ParseItemID(link)
  if not itemID then return end
  local merge = GT.MergeKey(link)
  local info = GT.Prices.Resolve(itemID, link)
  if not info then
    if pendingInfoN >= GT.PENDING_MAX then return end
    pendingInfo[merge] = { count = (pendingInfo[merge] and pendingInfo[merge].count or 0) + count, source = source, link = link, itemID = itemID }
    pendingInfoN = pendingInfoN + 1
    GT.Ledger.CreditItem(merge, count, {
      itemID = itemID, name = "...", link = link, quality = 0,
      unitCopper = 0, method = "PENDING", vendor = 0, de = 0,
      ahRaw = 0, ahNet = 0, why = "waiting GetItemInfo",
    }, source)
    return
  end
  info.itemID = itemID
  local val = GT.ValueItem(info, false)
  val.itemID = itemID
  GT.Ledger.CreditItem(merge, count, val, source)
end

local function handleItemChat(msg)
  if not GT.IsSessionLive() then return end

  expirePending()
  local now = GetTime()
  local p = oldestPending(now)
  local openReplace = p and (p.ownsFrame or not p.hadLootFrame)

  -- created
  if PAT.createdN and msg:find(PAT.createdN) then
    GT.Log("ignore created %s", msg)
    return
  end
  if PAT.created and msg:find(PAT.created) then
    GT.Log("ignore created %s", msg)
    return
  end

  local link, count

  local function takeSelf()
    if PAT.selfN then
      local l, n = msg:match(PAT.selfN)
      if l then return l, tonumber(n) or 1, true end
    end
    if PAT.self then
      local l = msg:match(PAT.self)
      if l then return l, 1, true end
    end
    return nil
  end

  local function takePush()
    if PAT.pushN then
      local l, n = msg:match(PAT.pushN)
      if l then return l, tonumber(n) or 1 end
    end
    if PAT.push then
      local l = msg:match(PAT.push)
      if l then return l, 1 end
    end
    return nil
  end

  local isSelf
  link, count, isSelf = takeSelf()
  local isPush = false
  if not link then
    link, count = takePush()
    isPush = link ~= nil
  end
  if not link then return end

  -- extract real item link
  local real = link:match("(|c%x+|Hitem:.+|h%[.-%]|h|r)") or link:match("(|Hitem:.+|h%[.-%]|h)")
  if real then link = real end
  count = count or 1
  local itemID = GT.ParseItemID(link)
  if isDestroyOutput(itemID) then
    if GetTime() < destroyUntil or GetTime() < encWindowUntil or enchantingWindowOpen() then
      GT.Log("ignore DE reagent %s", link)
      return
    end
  end

  if openReplace then
    local credit = replacePath(p)
    GT.Log("open-replace %s credit=%s", link, tostring(credit))
    if credit then
      local mk = "open:" .. (p.itemID or 0) .. ":" .. (GT.MergeKey(link) or "")
      if not seen(mk .. ":" .. count) then
        valueAndCredit(link, count, "open:" .. (p.itemID or 0))
      end
    end
    return
  end

  if isPush then
    local questOK = GoldTrackDB.countQuestRewards and GetTime() < (questUntil or 0)
    if not (lootRecent() or GetTime() < gatherUntil or questOK) then
      GT.Log("ignore push (no loot/gather) %s", link)
      return
    end
    if inTransfer() and not lootRecent() then
      GT.Log("ignore push transfer %s", link)
      return
    end
  end

  local mk = (GT.MergeKey(link) or link) .. ":" .. count
  if seen(mk) then return end
  valueAndCredit(link, count, "loot")
end

local function handleMoneyChat(msg)
  if not GT.IsSessionLive() then return end
  expirePending()
  local now = GetTime()
  local p = oldestPending(now)
  local openReplace = p and (p.ownsFrame or not p.hadLootFrame)

  local blob
  if moneyPat.you then blob = msg:match(moneyPat.you) end
  local isSplit = false
  if not blob and moneyPat.split then
    blob = msg:match(moneyPat.split)
    isSplit = blob ~= nil
  end
  if not blob then return end

  local copper = GT.ParseCoinBlob(blob)
  if copper <= 0 then return end

  if openReplace then
    -- clam coin is vanishingly rare; treat as contents only if we already own the frame
    if p.ownsFrame then
      if p.key then replacePath(p) end
      return
    end
  end

  if not GT.IsSessionLive() then return end
  -- splits do not require loot frame
  if not isSplit and inTransfer() then
    GT.Log("ignore money transfer")
    return
  end
  local key = "gold:" .. copper .. ":" .. floor(now * 2)
  if seen(key) then return end
  GT.Ledger.CreditGold(copper, isSplit and "split" or "loot")
end

function GT.Events.OnLootOpened()
  lootFrameUntil = GetTime() + GT.LOOT_FRAME_RECENT
  local now = GetTime()
  local p = oldestPending(now)
  if p and not p.hadLootFrame then
    p.ownsFrame = true
  end
end

function GT.Events.OnLootClosed()
  lootFrameUntil = GetTime() + 0.4
  local i = 1
  while i <= pendingN do
    local p = pendingOpen[i]
    if p.ownsFrame then
      if p.key and not p.decremented then
        GT.Ledger.Decrement(p.key, 1)
      end
      popPending(i)
    else
      i = i + 1
    end
  end
end

function GT.Events.OnSpell(unit, _, spellId)
  if unit ~= "player" then return end
  if not spellId then return end
  if spellId == 13262 or spellId == 31252 then
    markDestroy("spell " .. spellId)
  elseif GATHER_SPELL[spellId] then
    gatherUntil = GetTime() + 3
  end
end

-- Classic UNIT_SPELLCAST_SUCCEEDED: (unit, spellName, rank) — no spellId on some builds
function GT.Events.OnSpellClassic(unit, spellName)
  if unit ~= "player" or not spellName then return end
  -- locale-proof fallback only for DE/prospect via known English is bad;
  -- we also listen for CLEU. This is last resort for gather names? skip.
end

function GT.Events.Transfer(open)
  if open then
    transfer = transfer + 1
  else
    transfer = transfer - 1
    if transfer < 0 then transfer = 0 end
    if transfer == 0 then
      transferUntil = GetTime() + GT.TRANSFER_GRACE
    end
  end
end

function GT.Events.OnBag()
  if not GT.IsSessionLive() then return end
  bagDirty = true
  bagDirtyAt = GetTime()
  GT.Events.NeedPoll()
end

local function flushBags()
  if not bagDirty then return end
  if GetTime() - bagDirtyAt < GT.BAG_DEBOUNCE then return end
  bagDirty = false
  local beforeOpen = {}
  for id, n in pairs(openQty) do beforeOpen[id] = n end
  local beforeGear = {}
  for id, n in pairs(farmGearQty) do beforeGear[id] = n end
  recountOpenables()
  local had = lootRecent()
  for id, prev in pairs(beforeOpen) do
    local now = openQty[id] or 0
    if now < prev then
      pushOpen(id, prev - now, had)
      GT.Log("openable -%d item %d", prev - now, id)
    end
  end
  for id, prev in pairs(beforeGear) do
    local now = farmGearQty[id] or 0
    if now < prev then
      markDestroy("farmed gear left bags " .. id)
      break
    end
  end
end

function GT.Events.OnItemInfo(itemID)
  if pendingInfoN <= 0 then return end
  -- scan a few pending keys
  local cleared = 0
  for key, p in pairs(pendingInfo) do
    if p.itemID == itemID then
      local info = GT.Prices.Resolve(itemID, p.link)
      if info then
        info.itemID = itemID
        local val = GT.ValueItem(info, false)
        val.itemID = itemID
        GT.Ledger.ApplyPending(key, val)
        pendingInfo[key] = nil
        cleared = cleared + 1
      end
    end
  end
  if cleared > 0 then
    pendingInfoN = pendingInfoN - cleared
    if pendingInfoN < 0 then pendingInfoN = 0 end
  end
end

function GT.Events.ResetRuntime()
  wipe(pendingOpen)
  pendingN = 0
  wipe(pendingInfo)
  pendingInfoN = 0
end

function GT.Events.OnSessionStart()
  bagDirty = false
  recountOpenables()
  GT.Events.SetListen(true)
end

local evFrame
local listenOn = false
local pollAcc = 0
local opens = {
  MAIL_SHOW = true, TRADE_SHOW = true, MERCHANT_SHOW = true,
  AUCTION_HOUSE_SHOW = true, BANKFRAME_OPENED = true,
  GUILDBANKFRAME_OPENED = true, TRAINER_SHOW = true,
  TAXIMAP_OPENED = true, QUEST_COMPLETE = true, QUEST_FINISHED = true,
  TRADE_SKILL_SHOW = true,
}
local closes = {
  MAIL_CLOSED = true, TRADE_CLOSED = true, MERCHANT_CLOSED = true,
  AUCTION_HOUSE_CLOSED = true, BANKFRAME_CLOSED = true,
  GUILDBANKFRAME_CLOSED = true, TRAINER_CLOSED = true,
  TAXIMAP_CLOSED = true, TRADE_SKILL_CLOSE = true,
}

local function poll(_, e)
  pollAcc = pollAcc + e
  if pollAcc < 0.05 then return end
  pollAcc = 0
  if bagDirty then flushBags() end
  if pendingN > 0 then expirePending() end
  if not bagDirty and pendingN == 0 and evFrame then
    evFrame:SetScript("OnUpdate", nil)
  end
end

function GT.Events.NeedPoll()
  if evFrame and not evFrame:GetScript("OnUpdate") then
    pollAcc = 0
    evFrame:SetScript("OnUpdate", poll)
  end
end

function GT.Events.SetListen(on)
  if not evFrame or listenOn == on then return end
  listenOn = on
  local f = evFrame
  if on then
    f:RegisterEvent("CHAT_MSG_LOOT")
    f:RegisterEvent("CHAT_MSG_MONEY")
    f:RegisterEvent("LOOT_OPENED")
    f:RegisterEvent("LOOT_CLOSED")
    if LOOT_READY then f:RegisterEvent("LOOT_READY") end
    if _G.BAG_UPDATE_DELAYED then
      f:RegisterEvent("BAG_UPDATE_DELAYED")
    else
      f:RegisterEvent("BAG_UPDATE")
    end
    f:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    f:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    for ev in pairs(opens) do f:RegisterEvent(ev) end
    for ev in pairs(closes) do f:RegisterEvent(ev) end
  else
    f:UnregisterAllEvents()
    f:SetScript("OnUpdate", nil)
    bagDirty = false
  end
end

function GT.Events.Init()
  compileAll()
  initBags()
  deName = GetSpellInfo(13262)
  prospectName = GetSpellInfo(31252)

  evFrame = CreateFrame("Frame")
  evFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_LOOT" then
      handleItemChat(...)
    elseif event == "CHAT_MSG_MONEY" then
      handleMoneyChat(...)
    elseif event == "LOOT_OPENED" or event == "LOOT_READY" then
      GT.Events.OnLootOpened()
    elseif event == "LOOT_CLOSED" then
      GT.Events.OnLootClosed()
    elseif event == "BAG_UPDATE" or event == "BAG_UPDATE_DELAYED" then
      GT.Events.OnBag()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
      local unit, a, b, c = ...
      if unit ~= "player" then
        -- skip
      elseif type(c) == "number" then
        GT.Events.OnSpell(unit, nil, c)
      elseif type(a) == "number" then
        GT.Events.OnSpell(unit, nil, a)
      elseif type(b) == "number" then
        GT.Events.OnSpell(unit, nil, b)
      elseif type(a) == "string" then
        deName = deName or GetSpellInfo(13262)
        prospectName = prospectName or GetSpellInfo(31252)
        if a == deName or a == prospectName then
          markDestroy(a)
        end
      end
    elseif event == "TRADE_SKILL_SHOW" then
      GT.Events.Transfer(true)
      if enchantingWindowOpen() or (GetTradeSkillLine and GetSpellInfo(7411) and GetTradeSkillLine() == GetSpellInfo(7411)) then
        encWindowUntil = GetTime() + 3600
      end
    elseif event == "TRADE_SKILL_CLOSE" then
      GT.Events.Transfer(false)
      if encWindowUntil > GetTime() then
        encWindowUntil = GetTime() + 6
      end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
      GT.Events.OnItemInfo(...)
    elseif opens[event] then
      GT.Events.Transfer(true)
    elseif closes[event] then
      GT.Events.Transfer(false)
    end
  end)

  if GT.IsSessionLive() then
    GT.Events.SetListen(true)
    recountOpenables()
  end
end
