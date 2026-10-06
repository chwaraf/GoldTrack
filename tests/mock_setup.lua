--[[ Minimal WoW UI/API mock so GoldTrack can be booted under lupa (Lua 5.5).

Two client modes, selected by setting FOREVER = true before this file runs:

  FOREVER = nil/false -> Classic-line client (Era / TBC Anniversary):
      GetItemInfo, GetSpellInfo, GetNumSkillLines, GetSkillLineInfo,
      GetTradeSkillLine, IsAddOnLoaded, GetContainerItemInfo present as globals;
      the FrameXML GLOBAL MouseIsOver() present; WOW_PROJECT_ID = 2;
      interface 11509; BAG_UPDATE exists, LOOT_READY does not.

  FOREVER = true -> WoW: Forever (Camelot, retail-engine fork, 12.1.5-era API):
      those Classic globals are ABSENT; C_Item / C_Spell / C_AddOns / C_Container
      / C_TradeSkillUI provide the same data; the global MouseIsOver is ABSENT
      (moved to InputUtil.IsMouseOver in retail 12.1.0); WOW_PROJECT_ID = 1
      (MAINLINE -- indistinguishable from retail by project id); interface 16001;
      BAG_UPDATE ABSENT (removed in retail 10.0), LOOT_READY exists.

Modelled deliberately, because each one caught (or would have caught) a real bug:

  * ScriptRegion:IsMouseOver() exists in BOTH modes (it has since patch 3.3.0),
    while the global exists only in Classic. Calling the global bare threw once
    per frame in the HUD context menu on Forever.
  * RegisterEvent THROWS on an event name the client does not define, as Forever
    does, so GT.Api.RegisterEvent's pcall guard is genuinely exercised.
  * SetBackdrop comes from BackdropTemplateMixin, not the base widget API, and is
    only present on frames created WITH "BackdropTemplate". The mixin itself
    exists on both families (retail since 9.0, backported to Classic); a Forever
    traceback confirms it, since GoldTrackCtx carried backdropInfo and NineSlice
    textures. Giving every widget SetBackdrop would hide GT.UI.Backdrop's
    texture-fallback branch from testing.
  * FauxScrollFrame_* are present, and a test nils them out to prove the Loot and
    History lists degrade to their first page instead of erroring per refresh.
]]

FOREVER = FOREVER or false

GoldTrack = {}
GT = GoldTrack
GT.UI = {}

GoldTrackDB = {}
GoldTrackCharDB = {}

ITEMS = {}             -- itemID -> fixture price/info row
SPELLS = {}            -- spellID -> localized name
SKILLS = {}            -- Classic skill lines
PROFS = {}             -- retail/Forever professions
KNOWN_SPELLS = {}      -- spellIDs the player knows
OPEN_TRADESKILL = nil  -- localized name of the open trade-skill window
ADDONS_LOADED = {}     -- addon name -> true
MOUSE_X, MOUSE_Y = 400, 300
CURSOR_ITEM, CURSOR_LINK = nil, nil
LAST_POPUP = nil
PENDING_TIMERS = {}
FAUX_OFFSET = 0
FAUX_CALLS = 0

-- ------------------------------------------------------------- client identity
if FOREVER then
  WOW_PROJECT_ID = 1              -- MAINLINE: same as live retail
  WOW_PROJECT_MAINLINE = 1
  BUILD_VERSION, BUILD_NUMBER, BUILD_DATE, BUILD_TOC = "1.60.1", "69893", "Sep 17 2026", 16001
else
  WOW_PROJECT_ID = 2              -- CLASSIC
  WOW_PROJECT_MAINLINE = 1
  BUILD_VERSION, BUILD_NUMBER, BUILD_DATE, BUILD_TOC = "1.15.9", "57212", "Aug  5 2025", 11509
end
function GetBuildInfo() return BUILD_VERSION, BUILD_NUMBER, BUILD_DATE, BUILD_TOC end

-- ------------------------------------------------------------- lua-ish helpers
function wipe(t)
  if type(t) ~= 'table' then return t end
  for k in pairs(t) do t[k] = nil end
  return t
end
tinsert = table.insert
tremove = table.remove
format = string.format
floor = math.floor
abs = math.abs

TIME = 1000.0
function GetTime() return TIME end
function GetServerTime() return 1700000000 end
function time() return 1700000000 end
function date() return '2026-09-20' end

STANDARD_TEXT_FONT = 'Fonts\\FRIZQT__.TTF'
YES, NO, OKAY, CANCEL, ACCEPT = 'Yes', 'No', 'Okay', 'Cancel', 'Accept'
SlashCmdList = {}
StaticPopupDialogs = {}
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
UIErrorsFrame = { AddMessage = function() end }

UnitName = function() return 'Testchar' end
UnitFullName = function() return 'Testchar' end
UnitLevel = function() return 60 end
UnitClass = function() return 'Hunter', 'HUNTER' end
UnitIsAFK = function() return false end
GetRealmName = function() return FOREVER and '' or 'Testrealm' end
GetRealZoneText = function() return 'Elwynn Forest' end
GetZoneText = function() return 'Elwynn Forest' end
GetCursorPosition = function() return MOUSE_X, MOUSE_Y, 1 end
GetCoinTextureString = function(v) return tostring(v) end
PlaySound = function() end
StaticPopup_Show = function(name) LAST_POPUP = name end
hooksecurefunc = function() end
InCombatLockdown = function() return false end
C_Timer = { After = function(_, fn) PENDING_TIMERS[#PENDING_TIMERS + 1] = fn end,
            NewTicker = function() return { Cancel = function() end } end }
function RunPendingTimers()
  local t = PENDING_TIMERS; PENDING_TIMERS = {}
  for _, fn in ipairs(t) do fn() end
end

-- Cursor: retail has C_CursorInfo but keeps these globals too.
CursorHasItem = function() return CURSOR_ITEM ~= nil end
GetCursorInfo = function()
  if not CURSOR_ITEM then return nil end
  return 'item', CURSOR_ITEM, CURSOR_LINK
end
ClearCursor = function() CURSOR_ITEM, CURSOR_LINK = nil, nil end

IsPlayerSpell = function(id) return KNOWN_SPELLS[id] == true end
IsSpellKnown = function(id) return KNOWN_SPELLS[id] == true end

-- ------------------------------------------------- per-family item/spell/bag API
local function itemInfoById(idOrLink)
  local id = tonumber(idOrLink) or tonumber(tostring(idOrLink):match('item:(%d+)'))
  local it = id and ITEMS[id] or nil
  if not it then return nil end
  return it.name, it.link, it.quality, it.ilvl or 1, it.minLevel or 1, it.itemType,
         it.subType, it.stackCount, it.equipLoc, it.texture, it.vendor,
         it.classID, it.subclassID, it.bindType
end

if FOREVER then
  C_Item = {
    GetItemInfo = itemInfoById,
    GetItemIconByID = function(id) local it = ITEMS[id]; return it and it.texture end,
    GetItemCount = function() return 0 end,
  }
  C_Spell = {
    GetSpellName = function(id) return SPELLS[id] end,
    -- returns a TABLE, not the old positional list
    GetSpellInfo = function(id) local n = SPELLS[id]
      return n and { name = n, spellID = id, iconID = 0 } or nil end,
  }
  C_AddOns = {
    IsAddOnLoaded = function(n) return ADDONS_LOADED[n] == true end,
    GetAddOnMetadata = function() return '1.2.0' end,
  }
  C_Container = {
    GetContainerNumSlots = function() return 0 end,
    GetContainerItemLink = function() return nil end,
    GetContainerItemInfo = function() return nil end,
  }
  C_TradeSkillUI = {
    GetBaseProfessionInfo = function()
      return OPEN_TRADESKILL and { professionName = OPEN_TRADESKILL } or nil
    end,
  }
  GetProfessions = function() return (#PROFS > 0) and 1 or nil end
  GetProfessionInfo = function(idx) return PROFS[idx] end
  InputUtil = { IsMouseOver = function(r) return r and r._mouseOver == true end }
else
  GetItemInfo = itemInfoById
  function GetItemIcon(id) local it = ITEMS[tonumber(id) or 0]; return it and it.texture end
  function GetSpellInfo(id)
    local n = SPELLS[id]
    if not n then return nil end
    return n, nil, 0, 0, 0, 0, id, 0
  end
  function GetNumSkillLines() return #SKILLS end
  function GetSkillLineInfo(i) return SKILLS[i], nil, nil end
  function GetTradeSkillLine() return OPEN_TRADESKILL or 'UNKNOWN' end
  function IsAddOnLoaded(n) return ADDONS_LOADED[n] == true end
  function GetAddOnMetadata() return '1.2.0' end
  function GetContainerNumSlots() return 0 end
  function GetContainerItemLink() return nil end
  function GetContainerItemInfo() return nil end
  function MouseIsOver(r) return r and r._mouseOver == true end
end

-- Legacy FrameXML list helpers: present on Classic and on retail today. A test
-- nils them out to prove GoldTrack degrades instead of erroring every refresh.
function FauxScrollFrame_Update(frame, n, visible, rowH)
  FAUX_CALLS = FAUX_CALLS + 1
  frame._fauxItems, frame._fauxVisible, frame._fauxRowH = n, visible, rowH
end
function FauxScrollFrame_GetOffset(frame) return FAUX_OFFSET end
function FauxScrollFrame_OnVerticalScroll(frame, offset, rowH, fn)
  FAUX_OFFSET = floor((offset or 0) / (rowH or 1) + 0.5)
  if fn then fn() end
end

-- ------------------------------------------------------------- events per client
CLASSIC_EVENTS = {
  ADDON_LOADED=1, PLAYER_LOGIN=1, PLAYER_ENTERING_WORLD=1, PLAYER_LEAVING_WORLD=1,
  PLAYER_LOGOUT=1, PLAYER_FLAGS_CHANGED=1, PLAYER_LEVEL_UP=1,
  CHAT_MSG_LOOT=1, CHAT_MSG_MONEY=1, LOOT_OPENED=1, LOOT_CLOSED=1,
  BAG_UPDATE=1, BAG_UPDATE_DELAYED=1,
  UNIT_SPELLCAST_SUCCEEDED=1, UNIT_SPELLCAST_START=1, GET_ITEM_INFO_RECEIVED=1,
  MAIL_SHOW=1, MAIL_CLOSED=1, TRADE_SHOW=1, TRADE_CLOSED=1,
  MERCHANT_SHOW=1, MERCHANT_CLOSED=1, AUCTION_HOUSE_SHOW=1, AUCTION_HOUSE_CLOSED=1,
  BANKFRAME_OPENED=1, BANKFRAME_CLOSED=1, GUILDBANKFRAME_OPENED=1, GUILDBANKFRAME_CLOSED=1,
  TRAINER_SHOW=1, TRAINER_CLOSED=1, TAXIMAP_OPENED=1, TAXIMAP_CLOSED=1,
  QUEST_COMPLETE=1, QUEST_FINISHED=1, TRADE_SKILL_SHOW=1, TRADE_SKILL_CLOSE=1,
}
FOREVER_EVENTS = {
  ADDON_LOADED=1, PLAYER_LOGIN=1, PLAYER_ENTERING_WORLD=1, PLAYER_LEAVING_WORLD=1,
  PLAYER_LOGOUT=1, PLAYER_FLAGS_CHANGED=1, PLAYER_LEVEL_UP=1,
  CHAT_MSG_LOOT=1, CHAT_MSG_MONEY=1, LOOT_OPENED=1, LOOT_CLOSED=1, LOOT_READY=1,
  BAG_UPDATE_DELAYED=1,                      -- BAG_UPDATE removed in retail 10.0
  ITEM_DATA_LOAD_RESULT=1,
  UNIT_SPELLCAST_SUCCEEDED=1, UNIT_SPELLCAST_START=1, GET_ITEM_INFO_RECEIVED=1,
  MAIL_SHOW=1, MAIL_CLOSED=1, TRADE_SHOW=1, TRADE_CLOSED=1,
  MERCHANT_SHOW=1, MERCHANT_CLOSED=1, AUCTION_HOUSE_SHOW=1, AUCTION_HOUSE_CLOSED=1,
  BANKFRAME_OPENED=1, BANKFRAME_CLOSED=1, GUILDBANKFRAME_OPENED=1, GUILDBANKFRAME_CLOSED=1,
  TRAINER_SHOW=1, TRAINER_CLOSED=1, TAXIMAP_OPENED=1, TAXIMAP_CLOSED=1,
  QUEST_COMPLETE=1, QUEST_FINISHED=1, TRADE_SKILL_SHOW=1, TRADE_SKILL_CLOSE=1,
}
VALID_EVENTS = FOREVER and FOREVER_EVENTS or CLASSIC_EVENTS
REGISTERED_EVENTS = {}
EVENT_ERRORS = {}

-- ------------------------------------------------------------- widget
local _frames = {}
FRAMECOUNT = 0

local function MakeWidget(kind, name)
  local self = { _kind = kind, _name = name, _shown = true, _text = '', _w = 0, _h = 0,
                 _pts = {}, _scripts = {}, _kids = {}, _fs = {}, _tex = {}, _reg = {},
                 _mouseOver = false }
  function self:SetSize(w, h) self._w, self._h = w, h end
  function self:GetSize() return self._w, self._h end
  function self:SetWidth(w) self._w = w end
  function self:GetWidth() return self._w end
  function self:SetHeight(h) self._h = h end
  function self:GetHeight() return self._h end
  function self:SetPoint(...) self._pts[#self._pts + 1] = { ... } end
  function self:ClearAllPoints() self._pts = {} end
  function self:GetPoint(i) local p = self._pts[i or 1]
    if p then return p[1], p[2], p[3], p[4], p[5] end end
  function self:GetLeft() return 100 end
  function self:GetBottom() return 100 end
  function self:GetTop() return 200 end
  function self:GetRight() return 200 end
  function self:GetCenter() return 150, 150 end
  function self:SetParent(p) self._parent = p end
  function self:GetParent() return self._parent end
  function self:GetName() return self._name end
  function self:Show() self._shown = true end
  function self:Hide() self._shown = false end
  function self:SetShown(v) self._shown = v and true or false end
  function self:IsShown() return self._shown end
  function self:IsVisible() return self._shown end
  function self:SetText(t) self._text = t
    if self._fsObj then self._fsObj:SetText(t) end end
  function self:GetText() return self._text end
  -- A Button's label FontString (UIPanelButtonTemplate gives every button one).
  function self:GetFontString()
    if not self._fsObj then self._fsObj = MakeWidget('FontString', (self._name or 'btn') .. 'FS') end
    self._fsObj:SetText(self._text)
    return self._fsObj
  end
  -- ScriptRegion method: present on every client since patch 3.3.0.
  function self:IsMouseOver() return self._mouseOver == true end
  function self:SetFont(...) end
  function self:GetFont() return STANDARD_TEXT_FONT, 12, '' end
  function self:SetFontString(fs) self._fsobj = fs end
  function self:SetTextColor(...) end
  function self:SetJustifyH(...) end
  function self:SetJustifyV(...) end
  function self:SetWordWrap(...) end
  function self:GetStringWidth() return #(self._text or '') * 6 end
  function self:SetAllPoints(...) end
  function self:SetFrameStrata(...) end
  function self:SetFrameLevel(...) end
  function self:GetFrameLevel() return 1 end
  function self:SetClampedToScreen(...) end
  function self:SetMovable(...) end
  function self:SetResizable(...) end
  function self:SetResizeBounds(...) end
  function self:SetMinResize(...) end
  function self:EnableMouse(...) end
  function self:RegisterForDrag(...) end
  function self:RegisterForClicks(...) end
  function self:RegisterEvent(ev)
    if not VALID_EVENTS[ev] then
      EVENT_ERRORS[#EVENT_ERRORS + 1] = ev
      error(('Event "%s" does not exist'):format(tostring(ev)), 2)
    end
    self._reg[ev] = true
    REGISTERED_EVENTS[self._name or tostring(self)] = self._reg
    return true
  end
  function self:IsEventRegistered(ev) return self._reg[ev] == true end
  function self:UnregisterEvent(ev) self._reg[ev] = nil end
  function self:UnregisterAllEvents() for k in pairs(self._reg) do self._reg[k] = nil end end
  function self:SetScript(ev, fn) self._scripts[ev] = fn end
  function self:GetScript(ev) return self._scripts[ev] end
  function self:HookScript(ev, fn) self._scripts[ev] = fn end
  function self:StartMoving() end
  function self:StopMovingOrSizing() end
  function self:SetScale(...) end
  function self:GetScale() return 1 end
  function self:GetEffectiveScale() return 1 end
  function self:SetAlpha(...) end
  function self:SetVertexColor(...) end
  function self:SetColorTexture(...) end
  function self:SetTexture(...) end
  function self:SetTexCoord(...) end
  function self:SetDrawLayer(...) end
  function self:SetHitRectInsets(...) end
  function self:SetNormalTexture(...) end
  function self:GetNormalTexture() return MakeWidget('Texture', 'n') end
  function self:SetHighlightTexture(...) end
  function self:GetHighlightTexture() return MakeWidget('Texture', 'h') end
  function self:GetPushedTexture() return MakeWidget('Texture', 'p') end
  function self:GetDisabledTexture() return MakeWidget('Texture', 'd') end
  function self:SetNormalFontObject(...) end
  function self:SetHighlightFontObject(...) end
  function self:SetDisabled(...) end
  function self:Enable(...) end
  function self:Disable(...) end
  function self:SetChecked(...) end
  function self:GetChecked() return false end
  function self:SetValue(...) end
  function self:GetValue() return 0 end
  function self:SetMinMaxValues(...) end
  function self:SetOrientation(...) end
  function self:SetStatusBarColor(...) end
  function self:SetStatusBarTexture(...) end
  function self:AddLine(...) end
  function self:AddDoubleLine(...) end
  function self:ClearLines() end
  function self:SetOwner(...) end
  function self:NumLines() return 0 end
  function self:SetHyperlink(...) end
  function self:SetItem(...) end
  function self:SetInventoryItem(...) end
  function self:SetBagItem(...) end
  function self:SetID(...) end
  function self:GetID() return 0 end
  function self:SetAutoFocus(...) end
  function self:SetNumeric(...) end
  function self:SetMaxLetters(...) end
  function self:SetFocus() end
  function self:ClearFocus() end
  function self:HighlightText(...) end
  function self:SetCursorPosition(...) end
  function self:GetNumber() return tonumber(self._text) or 0 end
  function self:SetNumber(v) self._text = tostring(v) end
  function self:HasFocus() return false end
  function self:SetScrollChild(c) self._scrollChild = c end
  function self:GetScrollChild() return self._scrollChild end
  function self:SetVerticalScroll(v) self._vscroll = v end
  function self:GetVerticalScroll() return self._vscroll or 0 end
  function self:SetHorizontalScroll(v) self._hscroll = v end
  function self:GetHorizontalScroll() return self._hscroll or 0 end
  function self:UpdateScrollChildRect() end
  function self:LockHighlight() end
  function self:UnlockHighlight() end
  function self:SetButtonState(...) end
  function self:GetButtonState() return 'NORMAL' end
  function self:SetMotionScriptsWhileDisabled(...) end
  function self:CreateTitleRegion() return MakeWidget('Region', 'title') end
  function self:CreateFontString(n)
    local fs = MakeWidget('FontString', n or ('fs' .. #self._fs)); self._fs[#self._fs + 1] = fs; return fs
  end
  function self:CreateTexture(n)
    local t = MakeWidget('Texture', n or ('tex' .. #self._tex)); self._tex[#self._tex + 1] = t; return t
  end
  function self:GetRegions() return ipairs(self._fs) end
  function self:GetNumRegions() return #self._fs end
  function self:Click(...)
    local f = self._scripts['OnClick']; if f then f(self, 'LeftButton') end
  end
  return self
end

function CreateFrame(kind, name, parent, template)
  FRAMECOUNT = FRAMECOUNT + 1
  local f = MakeWidget(kind, name or ('anon' .. FRAMECOUNT))
  f._parent = parent
  f._template = template
  -- Only a frame created WITH BackdropTemplate gains the backdrop methods, which
  -- is what makes the addon's `if frame.SetBackdrop then` test meaningful.
  if type(template) == 'string' and template:find('BackdropTemplate') then
    f.SetBackdrop = function(self, bd) self.backdropInfo = bd end
    f.GetBackdrop = function(self) return self.backdropInfo end
    f.SetBackdropColor = function(self, ...) self._bdColor = { ... } end
    f.SetBackdropBorderColor = function(self, ...) self._bdBorder = { ... } end
  end
  if name then _frames[name] = f end
  if parent and parent._kids then parent._kids[#parent._kids + 1] = f end
  return f
end
function FindFrame(name) return _frames[name] end
function getglobal(n) return _G[n] end
function setglobal(n, v) _G[n] = v end

UISpecialFrames = {}
NUM_BAG_SLOTS = 4
NUM_BANKBAGSLOTS = 7
ChatFrame1 = DEFAULT_CHAT_FRAME
for _, fo in ipairs({ 'GameFontNormal', 'GameFontHighlight', 'GameFontNormalSmall',
                      'GameFontHighlightSmall', 'GameFontWhite', 'GameFontDisable',
                      'NumberFontNormal', 'ChatFontNormal' }) do
  _G[fo] = { GetFont = function() return 'Fonts\\FRIZQT__.TTF', 12 end, SetFont = function() end,
             GetTextColor = function() return 1, 1, 1 end, SetTextColor = function() end }
end
UIParent = CreateFrame('Frame', 'UIParent'); UIParent:SetSize(1920, 1080)
Minimap = CreateFrame('Frame', 'Minimap')
MinimapCluster = CreateFrame('Frame', 'MinimapCluster'); MinimapCluster._shown = true
GameTooltip = CreateFrame('GameTooltip', 'GameTooltip')
ItemRefTooltip = CreateFrame('GameTooltip', 'ItemRefTooltip')
UIPanelButtonTemplate = 'UIPanelButtonTemplate'
UIPanelDialogTemplate = 'UIPanelDialogTemplate'
UIPanelCloseButton = 'UIPanelCloseButton'
GameTooltipTemplate = 'GameTooltipTemplate'
InputBoxTemplate = 'InputBoxTemplate'
SecureActionButtonTemplate = 'SecureActionButtonTemplate'
UIPanelScrollBarTemplate = 'UIPanelScrollBarTemplate'
FauxScrollFrameTemplate = 'FauxScrollFrameTemplate'
BackdropTemplate = 'BackdropTemplate'
BackdropTemplateMixin = { SetBackdrop = function() end }
