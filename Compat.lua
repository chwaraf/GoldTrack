--[[ GoldTrack — client API compatibility layer.

GoldTrack started life on the Classic-line clients (Classic Era, TBC
Anniversary), which expose the pre-9.0 global API. World of Warcraft: Forever
(codename Camelot, build 1.60.x, interface 16001) is a *retail-engine* fork:
WOW_PROJECT_ID reports MAINLINE and the client ships the Retail 12.x API with
269 C_* namespaces — but WITHOUT Blizzard's deprecated global wrappers. So the
globals this addon was written against are simply nil there:

    GetItemInfo, GetSpellInfo, GetNumSkillLines, GetSkillLineInfo,
    GetTradeSkillLine, IsAddOnLoaded, GetContainerItemInfo, ...

Calling one aborts the whole file ("attempt to call a nil value"), and on
Forever RegisterEvent for an unknown event throws the same way.

Everything GoldTrack needs is resolved ONCE here, at load time, into GT.Api.
Call sites use GT.Api.* rather than the bare global, so the same code runs on
Era, TBC Anniversary and Forever. Each entry prefers the client's own global
when it exists and falls back to the modern C_* equivalent, so nothing changes
behaviour on the Classic clients.

References for the mapping: Blizzard's own Blizzard_Deprecated wrappers, and the
Forever beta's captured API surface (forever-addon-kit's Compat.lua, measured
against build 1.60.1.69893).
]]
local GT = GoldTrack

GT.Api = {}

-- Resolve a global, falling back to a C_* namespace function. Returns nil when
-- neither exists (callers must cope) unless `stub` asks for a safe no-op.
local function pick(globalFn, ns, field)
  if type(globalFn) == "function" then return globalFn end
  local t = ns and _G[ns]
  if t and type(t[field]) == "function" then return t[field] end
  return nil
end

-- Items -------------------------------------------------------------------
-- C_Item.GetItemInfo returns the SAME positional shape as the old global
-- (name, link, quality, ilvl, minLevel, type, subType, stackCount, equipLoc,
-- texture, sellPrice, classID, subclassID, bindType, ...), so it forwards
-- directly with no adapter.
GT.Api.GetItemInfo = pick(GetItemInfo, "C_Item", "GetItemInfo")
GT.Api.GetItemInfoInstant = pick(GetItemInfoInstant, "C_Item", "GetItemInfoInstant")
GT.Api.GetItemCount = pick(GetItemCount, "C_Item", "GetItemCount")

-- A stub rather than nil for the one call that sits on the hot loot path: the
-- price resolver already treats "no data" as a normal outcome (PENDING rows),
-- so an absent item API degrades instead of erroring every loot event.
GT.Api.hasItemInfo = GT.Api.GetItemInfo ~= nil
if not GT.Api.GetItemInfo then
  GT.Api.GetItemInfo = function() return nil end
end

-- AddOns ------------------------------------------------------------------
GT.Api.IsAddOnLoaded = pick(IsAddOnLoaded, "C_AddOns", "IsAddOnLoaded")
GT.Api.GetAddOnMetadata = pick(GetAddOnMetadata, "C_AddOns", "GetAddOnMetadata")

-- Spells ------------------------------------------------------------------
-- The old GetSpellInfo returned (name, rank, icon, castTime, minRange,
-- maxRange, spellID, originalIcon). C_Spell.GetSpellInfo returns ONE TABLE
-- {name, iconID, castTime, minRange, maxRange, spellID, originalIconID}, so the
-- two are not interchangeable positionally. GoldTrack only ever wanted the
-- localized NAME (to compare against a profession/skill-line name), so expose
-- exactly that instead of faking the old signature.
function GT.Api.SpellName(spellID)
  if not spellID then return nil end
  local C_Spell = _G.C_Spell
  if C_Spell then
    if type(C_Spell.GetSpellName) == "function" then
      local n = C_Spell.GetSpellName(spellID)
      if n then return n end
    end
    if type(C_Spell.GetSpellInfo) == "function" then
      local info = C_Spell.GetSpellInfo(spellID)
      if info and info.name then return info.name end
    end
  end
  if type(GetSpellInfo) == "function" then
    -- Classic multi-return: name first.
    local n = GetSpellInfo(spellID)
    if n then return n end
  end
  return nil
end

-- Professions -------------------------------------------------------------
-- Does this character have the profession that `spellID` represents
-- (Mining = 2575, Enchanting = 7411)?
--
-- Three strategies, most modern first, because the Classic skill-line walk does
-- not exist on Forever and the spellbook probe does not cover every client:
--   1. Spellbook: IsSpellKnown / IsPlayerSpell on the profession spell.
--   2. Retail professions: GetProfessions() returns INDICES (not IDs), and
--      GetProfessionInfo(index) returns the localized name first.
--   3. Classic skill lines: GetNumSkillLines / GetSkillLineInfo.
-- Strategies 2 and 3 compare localized names against the spell's localized name,
-- so they work on any client locale.
function GT.Api.KnowsProfession(spellID)
  if not spellID then return false end
  if type(IsSpellKnown) == "function" and IsSpellKnown(spellID) then return true end
  if type(IsPlayerSpell) == "function" and IsPlayerSpell(spellID) then return true end

  local want = GT.Api.SpellName(spellID)
  if not want then return false end

  if type(GetProfessions) == "function" and type(GetProfessionInfo) == "function" then
    local n = select("#", GetProfessions())
    for i = 1, n do
      local idx = select(i, GetProfessions())
      if idx then
        local name = GetProfessionInfo(idx)
        if name == want then return true end
      end
    end
  end

  if type(GetNumSkillLines) == "function" and type(GetSkillLineInfo) == "function" then
    for i = 1, (GetNumSkillLines() or 0) do
      local name = GetSkillLineInfo(i)
      if name == want then return true end
    end
  end

  return false
end

-- Events ------------------------------------------------------------------
-- On Forever, RegisterEvent for an event the client does not define THROWS and
-- aborts the rest of the file (e.g. a Classic-only event name). Every
-- registration in the addon goes through here so one unknown event can cost at
-- most that one event, never the whole module. Returns true when registered.
function GT.Api.RegisterEvent(frame, event)
  if not frame or not event or type(frame.RegisterEvent) ~= "function" then return false end
  local ok = pcall(frame.RegisterEvent, frame, event)
  return ok and true or false
end

-- True when the client lacks the Classic globals this addon was written for,
-- i.e. we are on the retail API (Forever, or actual retail). Used for messaging
-- only; behaviour is decided per-API by the resolvers above.
function GT.Api.IsRetailApi()
  return type(GetItemInfo) ~= "function"
end
