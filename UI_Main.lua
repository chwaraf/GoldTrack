--[[ GoldTrack — main window: Total / Session / Loot / Config ]]
local GT = GoldTrack

GT.UI = GT.UI or {}

local main, tabs, pages, histWin
local lootRows = {}
local LOOT_VISIBLE = 14
local lootSort = "value"
local lootHideZero = false
local lootFilter = ""
local currentTab = "session"

-- Value inspector ------------------------------------------------------------
-- Prints every price source + the final valuation for one item to chat.
function GT.UI.PrintValuation(link)
  local itemID = GT.ParseItemID(link)
  if not itemID then return end
  local info = GT.Prices.Resolve(itemID, link)
  if not info then
    GT.Print("|cffff6060Item data not loaded yet - hover the item once, then click again.|r")
    return
  end
  info.itemID = itemID
  local d = GT.Prices.DebugSources(itemID, link) or {}
  local soulbound = (info.bindType or 0) == 1
  local val = GT.ValueItem(info, soulbound)
  local F = GT.FormatCopper
  local fl = math.floor
  GT.Print(("Value %s"):format(link))
  GT.Print(("  vendor=%s  DE=%s  q%d  bind=%d  stack=%d"):format(
    F(info.vendor or 0), F(info.de or 0), info.quality or 0,
    info.bindType or 0, info.stackCount or 1))
  GT.Print(("  TSM minbuyout=%s  recent=%s  market=%s  hist=%s  saleAvg=%s"):format(
    F(d.minbuyout or 0), F(d.recent or 0), F(d.market or 0),
    F(d.historical or 0), F(d.regionsaleavg or 0)))
  local ageTxt = "?"
  if d.atrAgeSec then
    local m = fl(d.atrAgeSec / 60)
    ageTxt = m >= 60 and format("%dh", fl(m / 60)) or format("%dm", m)
  end
  GT.Print(("  Auctionator=%s  fresh=%s  age=%s"):format(
    F(d.atr or 0), tostring(d.atrFresh == true), ageTxt))
  GT.Print(("  AHraw=%s src=%s [priceSource=%s, tsmField=%s]"):format(
    F(info.ahRaw or 0), info.ahSource or "-",
    GoldTrackDB.priceSource or "-", GoldTrackDB.tsmPriceField or "-"))
  GT.Print(("  sellRate=%.0f%% (%s)%s  mode=%s  cut=%s  dep=%s  lostDep=%s  AHnet=%s"):format(
    (val.sellRate or 0) * 100, val.sellRateSource or "-",
    info.soldPerDay and format("  sold/day=%.2f", info.soldPerDay) or "",
    val.ahMode or "-", F(val.cut or 0), F(val.deposit or 0),
    F(val.expectedLostDep or 0), F(val.ahNet or 0)))
  GT.Print(("  => |cffffff60%s %s|r  (%s)"):format(
    val.method or "?", F(val.unitCopper or 0), val.why or ""))
end


local TAB_IDS = { "total", "session", "loot", "config" }
local TAB_LABEL = { total = "Total", session = "Session", loot = "Loot", config = "Config" }
local TAB_TIP = {
  total = "Lifetime totals across all archived sessions.",
  session = "Current session summary, Start/Pause and Reset.",
  loot = "Loot rows for this session. Click a row to edit its value.",
  config = "Settings.",
}

local QCOL = {
  [0] = { 0.62, 0.62, 0.62 },
  [1] = { 1, 1, 1 },
  [2] = { 0.12, 1, 0 },
  [3] = { 0, 0.44, 0.87 },
  [4] = { 0.64, 0.21, 0.93 },
  [5] = { 1, 0.5, 0 },
}

local METHCOL = {
  AH = { 1, 0.82, 0 },
  DE = { 0.70, 0.30, 0.90 },
  VENDOR = { 0.65, 0.65, 0.65 },
  NONE = { 0.4, 0.4, 0.4 },
  GOLD = { 1, 0.85, 0.2 },
  PENDING = { 0.5, 0.5, 0.8 },
}

local function fontPath()
  if STANDARD_TEXT_FONT then return STANDARD_TEXT_FONT end
  local p = GameFontNormal:GetFont()
  return p or "Fonts\\FRIZQT__.TTF"
end

local COL_MUTED = { 0.722, 0.722, 0.722 }
local COL_GOLD = { 1, 0.820, 0 }

local function tipW(f, content)
  f:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    if type(content) == "function" then
      content(GameTooltip)
    else
      GameTooltip:AddLine(content, 1, 1, 1, true)
    end
    GameTooltip:Show()
  end)
  f:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function applyPoint(frame, p, defx, defy)
  frame:ClearAllPoints()
  if p and p[1] then
    frame:SetPoint(p[1], _G[p[2]] or UIParent, p[3], p[4] or 0, p[5] or 0)
  else
    frame:SetPoint("CENTER", UIParent, "CENTER", defx or 0, defy or 0)
  end
end

local function statRow(parent, prev, label, big)
  local row = CreateFrame("Frame", nil, parent)
  local sz = big and 20 or 13
  row:SetHeight(big and 28 or 22)
  if prev then
    row:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -4)
    row:SetPoint("TOPRIGHT", prev, "BOTTOMRIGHT", 0, -4)
  else
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -8)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, -8)
  end
  local dash = row:CreateFontString(nil, "OVERLAY")
  dash:SetFont(fontPath(), sz, "")
  dash:SetPoint("CENTER", 0, 0)
  dash:SetText("-")
  dash:SetTextColor(0.55, 0.55, 0.55)
  local l = row:CreateFontString(nil, "OVERLAY")
  l:SetFont(fontPath(), sz, "")
  l:SetPoint("RIGHT", dash, "LEFT", -8, 0)
  l:SetText(label)
  l:SetTextColor(COL_MUTED[1], COL_MUTED[2], COL_MUTED[3])
  l:SetJustifyH("RIGHT")
  l:SetWordWrap(false)
  local v = row:CreateFontString(nil, "OVERLAY")
  v:SetFont(fontPath(), sz, "")
  v:SetPoint("LEFT", dash, "RIGHT", 8, 0)
  v:SetJustifyH("LEFT")
  v:SetWordWrap(false)
  v:SetText("-")
  v:SetTextColor(1, 1, 1)
  row.v = v
  return row
end

function GT.UI.ShowTab(id)
  currentTab = id
  if not main then GT.UI.BuildMain() end
  main:Show()
  if id == "loot" then
    GT.RefreshTSMRows(true)
  end
  for i = 1, #TAB_IDS do
    local t = TAB_IDS[i]
    if pages[t] then
      if t == id then pages[t]:Show() else pages[t]:Hide() end
    end
    if tabs[t] then
      if t == id then
        tabs[t]:LockHighlight()
      else
        tabs[t]:UnlockHighlight()
      end
    end
  end
  GT.UI.UpdateMain()
end

function GT.UI.ToggleMain()
  if not main then GT.UI.BuildMain() end
  if main:IsShown() then main:Hide() else GT.UI.ShowTab(currentTab or "session") end
end

function GT.UI.BuildMain()
  if main then return main end
  local tmpl = BackdropTemplateMixin and "BackdropTemplate" or nil
  main = CreateFrame("Frame", "GoldTrackMain", UIParent, tmpl)
  main:SetSize(GoldTrackDB.mainW or 422, GoldTrackDB.mainH or 351)
  main:SetFrameStrata("HIGH")
  main:SetMovable(true)
  main:SetResizable(true)
  if main.SetResizeBounds then
    main:SetResizeBounds(380, 280)
  elseif main.SetMinResize then
    main:SetMinResize(380, 280)
  end
  main:EnableMouse(true)
  main:RegisterForDrag("LeftButton")
  main:SetClampedToScreen(true)
  GT.UI.Backdrop(main)
  applyPoint(main, GoldTrackDB.mainPoint, 0, 0)
  main:SetScale(GoldTrackDB.mainScale or 1)
  main:SetScript("OnDragStart", function(self) self:StartMoving() end)
  main:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local a, rel, b, x, y = self:GetPoint(1)
    GoldTrackDB.mainPoint = { a, rel and rel:GetName() or "UIParent", b, x, y }
  end)
  main:Hide()
  tinsert(UISpecialFrames, "GoldTrackMain")

  local close = CreateFrame("Button", nil, main, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 4)
  close:SetFrameLevel(main:GetFrameLevel() + 10)
  close:SetScript("OnClick", function() main:Hide() end)

  tabs, pages = {}, {}
  local tw = 80
  for i = 1, #TAB_IDS do
    local id = TAB_IDS[i]
    local b = CreateFrame("Button", nil, main)
    b:SetSize(tw, 22)
    b:SetPoint("TOPLEFT", 8 + (i - 1) * (tw + 2), -8)
    b:SetNormalFontObject(GameFontHighlight)
    b:SetHighlightFontObject(GameFontHighlight)
    b:SetText(TAB_LABEL[id])
    local tfs = b:GetFontString()
    if tfs then tfs:SetFont(fontPath(), 16, "") end
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    b:GetHighlightTexture():SetAlpha(0.4)
    b:SetScript("OnClick", function() GT.UI.ShowTab(id) end)
    tipW(b, TAB_TIP[id] or TAB_LABEL[id])
    tabs[id] = b

    local p = CreateFrame("Frame", nil, main)
    p:SetPoint("TOPLEFT", 6, -32)
    p:SetPoint("BOTTOMRIGHT", -6, 6)
    p:Hide()
    pages[id] = p
  end

  do
    local p = pages.total
    p.vals = {}
    local spec = {
      { "copper", "Lifetime est.", true },
      { "gh", "Lifetime g/h", true },
      { "ms", "Active time", false },
      { "n", "Sessions", false },
      { "best", "Best session", false },
      { "bestgh", "Best g/h", false },
    }
    local prev
    for i = 1, #spec do
      local row = statRow(p, prev, spec[i][2], spec[i][3])
      p.vals[spec[i][1]] = row.v
      prev = row
    end
    local src = {
      { "srcAH", "AH" },
      { "srcDE", "Disenchant" },
      { "srcVEN", "Vendor" },
      { "srcGOLD", "Coin" },
    }
    for i = 1, #src do
      local row = statRow(p, prev, src[i][2], false)
      p.vals[src[i][1]] = row.v
      prev = row
    end

    local wipe = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    wipe:SetSize(120, 22)
    wipe:SetPoint("BOTTOMLEFT", 4, 4)
    wipe:SetText("Clear lifetime")
    wipe:SetScript("OnClick", function() StaticPopup_Show("GOLDTRACK_WIPE") end)
    tipW(wipe, function(tt)
      tt:AddLine("Clear lifetime", 1, 0.82, 0)
      tt:AddLine("Wipe lifetime totals and archives for this character.", 0.8, 0.8, 0.8, true)
      tt:AddLine("You must type DELETE to confirm.", 0.55, 0.55, 0.55, true)
    end)

    local histBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    histBtn:SetSize(80, 22)
    histBtn:SetPoint("BOTTOMRIGHT", -4, 4)
    histBtn:SetText("History")
    histBtn:SetScript("OnClick", function() GT.UI.ToggleHistory() end)
    tipW(histBtn, "Show the last archived sessions (compact list, hover a row for details).")
  end

  do
    local p = pages.session
    p.vals = {}
    local spec = {
      { "copper", "Session est.", true },
      { "gph", "Gold / hour", true },
      { "elapsed", "Active time", false },
      { "state", "State", false },
      { "items", "Items", false },
    }
    local prev
    for i = 1, #spec do
      local row = statRow(p, prev, spec[i][2], spec[i][3])
      p.vals[spec[i][1]] = row.v
      prev = row
    end
    local src = {
      { "srcAH", "AH" },
      { "srcDE", "Disenchant" },
      { "srcVEN", "Vendor" },
      { "srcGOLD", "Coin" },
    }
    for i = 1, #src do
      local row = statRow(p, prev, src[i][2], false)
      p.vals[src[i][1]] = row.v
      prev = row
    end

    p.health = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    p.health:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -10)
    p.health:SetPoint("TOPRIGHT", prev, "BOTTOMRIGHT", 0, -10)
    p.health:SetJustifyH("LEFT")
    p.health:SetWordWrap(false)
    p.health:SetTextColor(0.65, 0.65, 0.65)

    local start = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    start:SetSize(80, 24)
    start:SetPoint("BOTTOMLEFT", 8, 8)
    start:SetText("Start")
    start:SetScript("OnClick", function()
      if GoldTrackCharDB.session.state == "RUNNING" then GT.SessionStop() else GT.SessionStart() end
    end)
    tipW(start, function(tt)
      if GoldTrackCharDB.session.state == "RUNNING" then
        tt:AddLine("Pause", 1, 0.82, 0)
        tt:AddLine("Fold the session clock. Loot rows are kept.", 0.8, 0.8, 0.8, true)
      else
        tt:AddLine("Start", 1, 0.82, 0)
        tt:AddLine("Run the session clock and count world-loot value from now on.",
          0.8, 0.8, 0.8, true)
      end
    end)
    p.start = start
    local rst = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    rst:SetSize(80, 24)
    rst:SetPoint("LEFT", start, "RIGHT", 8, 0)
    rst:SetText("Reset")
    rst:SetScript("OnClick", function() StaticPopup_Show("GOLDTRACK_RESET") end)
    tipW(rst, "Archive this session into Total, then clear it. Asks to confirm.")
  end

  do
    local p = pages.loot
    local COL_METH, COL_VAL, COL_QTY = 36, 88, 36

    local fl = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fl:SetPoint("TOPLEFT", 8, -6)
    fl:SetText("Filter")
    fl:SetTextColor(0.72, 0.72, 0.72)
    local eb = CreateFrame("EditBox", "GoldTrackFilter", p, "InputBoxTemplate")
    eb:SetSize(160, 20)
    eb:SetPoint("LEFT", fl, "RIGHT", 10, 0)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(40)
    eb:SetScript("OnTextChanged", function(self)
      lootFilter = self:GetText() or ""
      GT.UI.UpdateLoot()
    end)
    eb:SetScript("OnEnterPressed", function(self)
      lootFilter = self:GetText() or ""
      GT.UI.UpdateLoot()
      self:ClearFocus()
    end)
    eb:SetScript("OnEscapePressed", function(self)
      self:ClearFocus()
    end)
    tipW(eb, function(tt)
      tt:AddLine("Filter loot rows by name (applies as you type).", 1, 1, 1, true)
      tt:AddLine("Esc releases keyboard focus.", 0.7, 0.7, 0.7, true)
    end)
    local cb = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
    cb:SetPoint("LEFT", eb, "RIGHT", 8, 0)
    cb:SetSize(20, 20)
    local cbl = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cbl:SetPoint("LEFT", cb, "RIGHT", 0, 0)
    cbl:SetText("Hide 0")
    local function hide0Tip(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText("Hide 0", 1, 1, 1)
      GameTooltip:AddLine("Hide loot rows whose estimated gold is 0.", 0.8, 0.8, 0.8, true)
      GameTooltip:AddLine("Coin rows still show. Uncheck to see vendor-0 / NONE items.", 0.8, 0.8, 0.8, true)
      GameTooltip:Show()
    end
    cb:SetScript("OnEnter", hide0Tip)
    cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    cb:SetScript("OnClick", function(self)
      lootHideZero = self:GetChecked()
      GT.UI.UpdateLoot()
    end)

    -- Value inspector drop target: drag an item from your bags onto it.
    local ib = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    ib:SetSize(58, 20)
    ib:SetPoint("LEFT", cbl, "RIGHT", 12, -1)
    ib:SetText("Value")
    local function dropHandler(self)
      if not CursorHasItem() then return end
      -- GetCursorItem is retail-only; GetCursorInfo is classic-safe.
      local ctype, _, itemLink = GetCursorInfo()
      ClearCursor()
      if ctype == "item" and itemLink then
        GT.UI.PrintValuation(itemLink)
      end
    end
    ib:SetScript("OnReceiveDrag", dropHandler)
    ib:SetScript("OnMouseUp", function(self)
      -- Some drops on buttons only fire MouseUp; CursorHasItem guards
      -- against double-printing when OnReceiveDrag already handled it.
      dropHandler(self)
    end)
    ib:SetScript("OnEnter", function(self)
      if CursorHasItem() then self:LockHighlight() end
      tipW(self, function(tt)
        tt:AddLine("Value inspector", 1, 0.82, 0)
        tt:AddLine("Drag an item from your bags onto this button to print every price source and the final valuation to chat.",
          0.8, 0.8, 0.8, true)
      end)
    end)
    ib:SetScript("OnLeave", function(self)
      self:UnlockHighlight()
      GameTooltip:Hide()
    end)

    local hm = CreateFrame("Button", nil, p)
    hm:SetSize(COL_METH, 16)
    hm:SetPoint("TOPRIGHT", -6, -30)
    hm:SetNormalFontObject(GameFontNormal)
    hm:SetText("Src")
    hm:SetScript("OnClick", function() lootSort = "method"; GT.UI.UpdateLoot() end)
    tipW(hm, "Click to sort by value source (AH / DE / VEN / G).")
    local hv = CreateFrame("Button", nil, p)
    hv:SetSize(COL_VAL, 16)
    hv:SetPoint("RIGHT", hm, "LEFT", -4, 0)
    hv:SetNormalFontObject(GameFontNormal)
    hv:SetText("Gold")
    hv:SetScript("OnClick", function() lootSort = "value"; GT.UI.UpdateLoot() end)
    tipW(hv, "Click to sort by estimated gold.")
    local hq = CreateFrame("Button", nil, p)
    hq:SetSize(COL_QTY, 16)
    hq:SetPoint("RIGHT", hv, "LEFT", -4, 0)
    hq:SetNormalFontObject(GameFontNormal)
    hq:SetText("Qty")
    hq:SetScript("OnClick", function() lootSort = "qty"; GT.UI.UpdateLoot() end)
    tipW(hq, "Click to sort by quantity.")
    local hdr = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hdr:SetPoint("TOPLEFT", 28, -30)
    hdr:SetPoint("RIGHT", hq, "LEFT", -8, 0)
    hdr:SetJustifyH("LEFT")
    hdr:SetWordWrap(false)
    hdr:SetText("Item")

    p.scroll = CreateFrame("ScrollFrame", "GoldTrackLootScroll", p, "FauxScrollFrameTemplate")
    p.scroll:SetPoint("TOPLEFT", 2, -50)
    p.scroll:SetPoint("BOTTOMRIGHT", -28, 4)
    p.scroll:SetScript("OnVerticalScroll", function(self, off)
      FauxScrollFrame_OnVerticalScroll(self, off, 20, GT.UI.UpdateLoot)
    end)

    for i = 1, LOOT_VISIBLE do
      local r = CreateFrame("Button", nil, p)
      r:SetHeight(20)
      r:SetPoint("TOPLEFT", p.scroll, "TOPLEFT", 0, -(i - 1) * 20)
      r:SetPoint("TOPRIGHT", p.scroll, "TOPRIGHT", 0, -(i - 1) * 20)
      r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
      r.icon = r:CreateTexture(nil, "ARTWORK")
      r.icon:SetSize(16, 16)
      r.icon:SetPoint("LEFT", 2, 0)
      r.meth = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      r.meth:SetWidth(COL_METH)
      r.meth:SetPoint("RIGHT", -2, 0)
      r.meth:SetJustifyH("RIGHT")
      r.meth:SetWordWrap(false)
      r.val = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      r.val:SetWidth(COL_VAL)
      r.val:SetPoint("RIGHT", r.meth, "LEFT", -4, 0)
      r.val:SetJustifyH("RIGHT")
      r.val:SetWordWrap(false)
      r.qty = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      r.qty:SetWidth(COL_QTY)
      r.qty:SetPoint("RIGHT", r.val, "LEFT", -4, 0)
      r.qty:SetJustifyH("RIGHT")
      r.qty:SetWordWrap(false)
      r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      r.name:SetPoint("LEFT", r.icon, "RIGHT", 4, 0)
      r.name:SetPoint("RIGHT", r.qty, "LEFT", -8, 0)
      r.name:SetJustifyH("LEFT")
      r.name:SetWordWrap(false)
      r:SetScript("OnEnter", function(self)
        if not self.row then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.row.link then
          GameTooltip:SetHyperlink(self.row.link)
        else
          GameTooltip:SetText(self.row.name or "?")
        end
        local rw = self.row
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Vendor", GT.FormatCopper(rw.vendor or 0), 0.7, 0.7, 0.7, 1, 1, 1)
        GameTooltip:AddDoubleLine("DE", GT.FormatCopper(rw.de or 0), 0.7, 0.7, 0.7, 1, 1, 1)
        GameTooltip:AddDoubleLine("AH raw", GT.FormatCopper(rw.ahRaw or 0), 0.7, 0.7, 0.7, 1, 1, 1)
        GameTooltip:AddDoubleLine("AH 5% cut", GT.FormatCopper(rw.cut or math.floor((rw.ahRaw or 0) * 0.05)), 0.7, 0.7, 0.7, 1, 1, 1)
        GameTooltip:AddDoubleLine("Deposit / expected lost",
          GT.FormatCopper(rw.deposit or 0) .. " / " .. GT.FormatCopper(rw.expectedLostDep or 0),
          0.7, 0.7, 0.7, 1, 1, 1)
        GameTooltip:AddDoubleLine("Sell rate",
          format("%.0f%% (%s)", (rw.sellRate or 0) * 100, rw.sellRateSource or "?"),
          0.7, 0.7, 0.7, 1, 1, 1)
        if rw.soldPerDay then
          GameTooltip:AddDoubleLine("Sold / day", format("%.2f", rw.soldPerDay), 0.7, 0.7, 0.7, 1, 1, 1)
        end
        GameTooltip:AddDoubleLine("AH net", GT.FormatCopper(rw.ahNet or 0), 0.7, 0.7, 0.7, 1, 1, 1)
        GameTooltip:AddLine("Net = raw - 5% cut - expected lost deposit", 0.5, 0.5, 0.5, true)
        if rw.ahMode == "expected_single" then
          GameTooltip:AddLine("One-post EV also multiplies payout by sell rate.", 1, 0.4, 0.3, true)
        end
        if rw.manual then
          GameTooltip:AddLine("Manual override. Click to edit.", 1, 0.82, 0, true)
        else
          GameTooltip:AddLine("Click to edit value.", 0.6, 0.6, 0.6, true)
        end
        GameTooltip:AddLine(rw.why or "", 0.5, 0.8, 1, true)
        GameTooltip:Show()
      end)
      r:SetScript("OnLeave", function() GameTooltip:Hide() end)
      r:SetScript("OnClick", function(self)
        if self.row then GT.UI.OpenLootEdit(self.row) end
      end)
      lootRows[i] = r
    end
    p.empty = p:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    p.empty:SetPoint("CENTER", p.scroll, "CENTER")
    p.empty:SetText("Start a session and loot something. Click a row to edit value.")
  end

  GT.UI.main = main
  GT.UI.pages = pages
  if GT.UI.BuildConfig then GT.UI.BuildConfig(pages.config) end
  return main
end

local editFrame, editRow
local METH_CYCLE = { "AH", "DE", "VENDOR", "NONE" }

local function refreshEdit()
  if not editFrame or not editRow then return end
  editFrame.title:SetText(editRow.name or "?")
  local pill = editRow.method == "VENDOR" and "VEN" or (editRow.method or "-")
  if editRow.manual then pill = pill .. "*" end
  editFrame.meth:SetText(pill)
  editFrame.qty:SetText("qty " .. tostring(editRow.count or 0))
  if editRow.method == "GOLD" then
    editFrame.gold:SetText(GT.FmtNumber((editRow.count or 0) / 10000))
    editFrame.goldLab:SetText("Total gold")
  else
    editFrame.gold:SetText(GT.FmtNumber(GT.CopperToGold(editRow.unitCopper or 0)))
    editFrame.goldLab:SetText("Gold / item")
  end
  local tot = (editRow.count or 0) * (editRow.unitCopper or 0)
  editFrame.sum:SetText("Row = " .. GT.FormatCopper(tot))
end

local function dockBesideMain(frame)
  if not main then return end
  if not main:IsShown() then main:Show() end
  frame:ClearAllPoints()
  local need = frame:GetWidth() or 240
  local left = main:GetLeft()
  if left and left > need + 8 then
    frame:SetPoint("TOPRIGHT", main, "TOPLEFT", -4, 0)
  else
    frame:SetPoint("TOPLEFT", main, "TOPRIGHT", 4, 0)
  end
end

function GT.UI.OpenLootEdit(row)
  if not row or not row.key then return end
  if not editFrame then
    local tmpl = BackdropTemplateMixin and "BackdropTemplate" or nil
    local f = CreateFrame("Frame", "GoldTrackLootEdit", UIParent, tmpl)
    f:SetSize(240, 168)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetClampedToScreen(true)
    GT.UI.Backdrop(f)
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    local x = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    x:SetPoint("TOPRIGHT", 2, 4)
    x:SetScript("OnClick", function() f:Hide() end)

    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFont(fontPath(), 13, "")
    title:SetPoint("TOPLEFT", 10, -10)
    title:SetPoint("RIGHT", x, "LEFT", -4, 0)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    title:SetTextColor(1, 0.820, 0)
    f.title = title

    local qty = f:CreateFontString(nil, "OVERLAY")
    qty:SetFont(fontPath(), 11, "")
    qty:SetPoint("TOPLEFT", 10, -28)
    qty:SetTextColor(0.722, 0.722, 0.722)
    f.qty = qty

    local ml = f:CreateFontString(nil, "OVERLAY")
    ml:SetFont(fontPath(), 12, "")
    ml:SetPoint("TOPLEFT", 10, -50)
    ml:SetText("Src")
    ml:SetTextColor(0.722, 0.722, 0.722)
    local mb = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    mb:SetSize(72, 20)
    mb:SetPoint("LEFT", ml, "RIGHT", 10, 0)
    mb:SetScript("OnClick", function()
      if not editRow or editRow.method == "GOLD" then return end
      local cur, idx = editRow.method, 1
      for i = 1, #METH_CYCLE do
        if METH_CYCLE[i] == cur then idx = i; break end
      end
      idx = idx + 1
      if idx > #METH_CYCLE then idx = 1 end
      GT.Ledger.Override(editRow.key, METH_CYCLE[idx], nil)
      refreshEdit()
    end)
    f.meth = mb

    local gl = f:CreateFontString(nil, "OVERLAY")
    gl:SetFont(fontPath(), 12, "")
    gl:SetPoint("TOPLEFT", 10, -78)
    gl:SetText("Gold / item")
    gl:SetTextColor(0.722, 0.722, 0.722)
    f.goldLab = gl
    local ge = CreateFrame("EditBox", "GoldTrackLootGold", f, "InputBoxTemplate")
    ge:SetSize(72, 20)
    ge:SetPoint("LEFT", gl, "RIGHT", 10, 0)
    ge:SetAutoFocus(false)
    ge:SetMaxLetters(12)
    local function applyGold()
      if not editRow then return end
      local n = GT.ParseNumber(ge:GetText())
      if not n then return end
      GT.Ledger.Override(editRow.key, nil, GT.GoldToCopper(n))
      refreshEdit()
    end
    ge:SetScript("OnEnterPressed", function(self) applyGold(); self:ClearFocus() end)
    ge:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    ge:SetScript("OnEditFocusLost", applyGold)
    f.gold = ge

    local function use(cop)
      return function()
        if not editRow or editRow.method == "GOLD" then return end
        GT.Ledger.Override(editRow.key, nil, cop())
        refreshEdit()
      end
    end
    local bv = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    bv:SetSize(56, 18)
    bv:SetPoint("TOPLEFT", 10, -106)
    bv:SetText("Vendor")
    bv:SetScript("OnClick", use(function() return editRow.vendor or 0 end))
    local bd = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    bd:SetSize(40, 18)
    bd:SetPoint("LEFT", bv, "RIGHT", 4, 0)
    bd:SetText("DE")
    bd:SetScript("OnClick", use(function() return editRow.de or 0 end))
    local ba = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    ba:SetSize(56, 18)
    ba:SetPoint("LEFT", bd, "RIGHT", 4, 0)
    ba:SetText("AH net")
    ba:SetScript("OnClick", use(function() return editRow.ahNet or 0 end))
    local br = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    br:SetSize(52, 18)
    br:SetPoint("LEFT", ba, "RIGHT", 4, 0)
    br:SetText("Undo")
    br:SetScript("OnClick", function()
      if not editRow then return end
      GT.Ledger.RevertOverride(editRow.key)
      refreshEdit()
    end)

    local sum = f:CreateFontString(nil, "OVERLAY")
    sum:SetFont(fontPath(), 12, "")
    sum:SetPoint("BOTTOMLEFT", 10, 10)
    sum:SetPoint("BOTTOMRIGHT", -10, 10)
    sum:SetJustifyH("LEFT")
    sum:SetTextColor(1, 1, 1)
    f.sum = sum

    -- tooltips for the edit popup
    tipW(mb, function(tt)
      tt:AddLine("Value source", 1, 0.82, 0)
      tt:AddLine("Cycle: AH -> DE -> VENDOR -> NONE.", 0.8, 0.8, 0.8, true)
      tt:AddLine("AH = auction-house net. DE = disenchant value.", 0.55, 0.55, 0.55, true)
      tt:AddLine("Rows marked * use a manual override.", 0.55, 0.55, 0.55, true)
    end)
    tipW(ge, "Value per item in gold. Enter or clicking away applies it.")
    tipW(bv, "Use the vendor sell price as unit value.")
    tipW(bd, "Use the disenchant value as unit value.")
    tipW(ba, "Use AH net (raw minus 5% cut minus expected lost deposit) as unit value.")
    tipW(br, "Revert this row to the automatic valuation.")

    editFrame = f
  end
  editRow = row
  refreshEdit()
  if main then
    if not main:IsShown() then main:Show() end
    dockBesideMain(editFrame)
  end
  editFrame:Show()
end

function GT.UI.ToggleHistory()
  if not histWin then GT.UI.BuildHistory() end
  if histWin:IsShown() then
    histWin:Hide()
  else
    if main and not main:IsShown() then main:Show() end
    dockBesideMain(histWin)
    histWin:Show()
    GT.UI.UpdateArchive()
  end
end

function GT.UI.BuildHistory()
  if histWin then return histWin end
  local tmpl = BackdropTemplateMixin and "BackdropTemplate" or nil
  local f = CreateFrame("Frame", "GoldTrackHistory", UIParent, tmpl)
  f:SetSize(380, 320)
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetClampedToScreen(true)
  GT.UI.Backdrop(f)
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  f:Hide()
  tinsert(UISpecialFrames, "GoldTrackHistory")

  local title = f:CreateFontString(nil, "OVERLAY")
  title:SetFont(fontPath(), 17, "")
  title:SetPoint("TOPLEFT", 12, -10)
  title:SetText("Session history")
  title:SetTextColor(COL_GOLD[1], COL_GOLD[2], COL_GOLD[3])

  local x = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  x:SetPoint("TOPRIGHT", 2, 4)
  x:SetScript("OnClick", function() f:Hide() end)

  local hdr = f:CreateFontString(nil, "OVERLAY")
  hdr:SetFont(fontPath(), 11, "")
  hdr:SetPoint("TOPLEFT", 12, -32)
  hdr:SetPoint("RIGHT", -28, 0)
  hdr:SetJustifyH("LEFT")
  hdr:SetText("When            Zone                 Time       Gold")
  hdr:SetTextColor(COL_MUTED[1], COL_MUTED[2], COL_MUTED[3])

  local ARCH_N = 14
  f.ARCH_N = ARCH_N
  f.list = CreateFrame("ScrollFrame", "GoldTrackArchScroll", f, "FauxScrollFrameTemplate")
  f.list:SetPoint("TOPLEFT", 8, -48)
  f.list:SetPoint("BOTTOMRIGHT", -28, 10)
  f.arch = {}
  for i = 1, ARCH_N do
    local r = CreateFrame("Button", nil, f)
    r:SetHeight(18)
    r:SetPoint("TOPLEFT", f.list, "TOPLEFT", 4, -(i - 1) * 18)
    r:SetPoint("TOPRIGHT", f.list, "TOPRIGHT", 0, -(i - 1) * 18)
    r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    r.fs = r:CreateFontString(nil, "OVERLAY")
    r.fs:SetFont(fontPath(), 12, "")
    r.fs:SetAllPoints()
    r.fs:SetJustifyH("LEFT")
    r.fs:SetWordWrap(false)
    r:SetScript("OnEnter", function(self)
      if not self.a then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(self.a.zone or "Session", 1, 0.82, 0)
      GameTooltip:AddDoubleLine("Gold", GT.FormatCopper(self.a.copper or 0), 0.7, 0.7, 0.7, 1, 1, 1)
      GameTooltip:AddDoubleLine("Time", GT.FormatElapsed(self.a.ms or 0), 0.7, 0.7, 0.7, 1, 1, 1)
      if self.a.gh and self.a.gh > 0 then
        GameTooltip:AddDoubleLine("g/h", GT.FormatGPH(self.a.gh), 0.7, 0.7, 0.7, 1, 1, 1)
      end
      local bm = self.a.byMethod
      if bm then
        GameTooltip:AddDoubleLine("AH", GT.FormatCopper(bm.AH or 0), 0.7, 0.7, 0.7, 1, 1, 1)
        GameTooltip:AddDoubleLine("DE", GT.FormatCopper(bm.DE or 0), 0.7, 0.7, 0.7, 1, 1, 1)
        GameTooltip:AddDoubleLine("Vendor", GT.FormatCopper(bm.VENDOR or 0), 0.7, 0.7, 0.7, 1, 1, 1)
        GameTooltip:AddDoubleLine("Coin", GT.FormatCopper(bm.GOLD or 0), 0.7, 0.7, 0.7, 1, 1, 1)
      end
      GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.arch[i] = r
  end
  f.list:SetScript("OnVerticalScroll", function(self, off)
    FauxScrollFrame_OnVerticalScroll(self, off, 18, GT.UI.UpdateArchive)
  end)
  f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  f.empty:SetPoint("CENTER", f.list, "CENTER")
  f.empty:SetText("No archived sessions yet. Reset a session to store one.")

  histWin = f
  GT.UI.hist = f
  return f
end

function GT.UI.UpdateArchive()
  if not histWin or not histWin:IsShown() then return end
  local arch = GoldTrackCharDB.total.archives or {}
  local n = #arch
  local vis = histWin.ARCH_N or 14
  FauxScrollFrame_Update(histWin.list, n, vis, 18)
  local off = FauxScrollFrame_GetOffset(histWin.list)
  for i = 1, vis do
    local idx = n - off - i + 1
    local r = histWin.arch[i]
    local a = arch[idx]
    if a then
      r.a = a
      r.fs:SetText(format("%s  %s  %s  %s",
        date("%m-%d %H:%M", a.t or 0),
        a.zone or "",
        GT.FormatElapsed(a.ms or 0),
        GT.FormatCopper(a.copper or 0)))
      r:Show()
    else
      r.a = nil
      r:Hide()
    end
  end
  if n == 0 then histWin.empty:Show() else histWin.empty:Hide() end
end

function GT.UI.UpdateLoot()
  local p = pages and pages.loot
  if not p or not p:IsShown() then return end
  local keys = GT.Ledger.SortedKeys(lootSort)
  local s = GoldTrackCharDB.session
  local filt = lootFilter:lower()
  local shown = {}
  local n = 0
  for i = 1, #keys do
    local row = s.rows[keys[i]]
    if row then
      local total = (row.count or 0) * (row.unitCopper or 0)
      local skip = lootHideZero and total == 0 and row.method ~= "GOLD"
      if filt ~= "" and not (row.name or ""):lower():find(filt, 1, true) then
        skip = true
      end
      if not skip then
        n = n + 1
        shown[n] = row
      end
    end
  end
  FauxScrollFrame_Update(p.scroll, n, LOOT_VISIBLE, 20)
  local off = FauxScrollFrame_GetOffset(p.scroll)
  for i = 1, LOOT_VISIBLE do
    local row = shown[off + i]
    local r = lootRows[i]
    if row then
      r.row = row
      r.icon:SetTexture(row.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
      r.name:SetText(row.name or "?")
      local qc = QCOL[row.quality or 0] or QCOL[1]
      r.name:SetTextColor(qc[1], qc[2], qc[3])
      r.qty:SetText(row.method == "GOLD" and "" or tostring(row.count))
      r.val:SetText(GT.FormatCopper((row.count or 0) * (row.unitCopper or 0)))
      local pill = row.method == "VENDOR" and "VEN" or (row.method == "GOLD" and "G" or (row.method or "-"))
      if row.manual then pill = pill .. "*" end
      r.meth:SetText(pill)
      local mc = METHCOL[row.method] or METHCOL.NONE
      r.meth:SetTextColor(mc[1], mc[2], mc[3])
      r:Show()
    else
      r.row = nil
      r:Hide()
    end
  end
  if n == 0 then p.empty:Show() else p.empty:Hide() end
end

function GT.UI.UpdateMain()
  if not main or not main:IsShown() then return end
  local s = GoldTrackCharDB.session
  local t = GoldTrackCharDB.total
  local cms = GT.NowMs()
  local tms = (t.activeMs or 0) + (s.state == "RUNNING" and cms or (s.activeMs or 0))
  local tcop = (t.copper or 0) + (s.copper or 0)

  if pages.total:IsShown() then
    local p = pages.total
    p.vals.copper:SetText(GT.FormatCopper(tcop))
    p.vals.ms:SetText(GT.FormatElapsed(tms))
    p.vals.gh:SetText(GT.FormatGPH(GT.GPerHour(tcop, tms)))
    p.vals.n:SetText(tostring(t.sessionsCompleted or 0))
    p.vals.best:SetText(GT.FormatCopper(t.bestSessionCopper or 0))
    p.vals.bestgh:SetText(GT.FormatGPH((t.bestSessionGh or 0) > 0 and t.bestSessionGh or nil))
    local bm = t.byMethod
    p.vals.srcAH:SetText(GT.FormatCopper((bm.AH or 0) + (s.byMethod.AH or 0)))
    p.vals.srcDE:SetText(GT.FormatCopper((bm.DE or 0) + (s.byMethod.DE or 0)))
    p.vals.srcVEN:SetText(GT.FormatCopper((bm.VENDOR or 0) + (s.byMethod.VENDOR or 0)))
    p.vals.srcGOLD:SetText(GT.FormatCopper((bm.GOLD or 0) + (s.byMethod.GOLD or 0)))
  end
  if histWin and histWin:IsShown() then GT.UI.UpdateArchive() end

  if pages.session:IsShown() then
    local p = pages.session
    local st = s.state .. (GT.afkPaused and " (AFK paused)" or "")
    p.vals.state:SetText(st)
    p.vals.elapsed:SetText(GT.FormatElapsed(cms))
    p.vals.copper:SetText(GT.FormatCopper(s.copper or 0))
    p.vals.gph:SetText(GT.FormatGPH(GT.GPerHour(s.copper or 0, cms)))
    p.vals.items:SetText(tostring(s.items or 0))
    local tot = (s.copper and s.copper > 0) and s.copper or 1
    local function src(v)
      return format("%s   (%.0f%%)", GT.FormatCopper(v or 0), 100 * (v or 0) / tot)
    end
    p.vals.srcAH:SetText(src(s.byMethod.AH))
    p.vals.srcDE:SetText(src(s.byMethod.DE))
    p.vals.srcVEN:SetText(src(s.byMethod.VENDOR))
    p.vals.srcGOLD:SetText(src(s.byMethod.GOLD))
    local tsmOn, atrOn, nitOn = GT.AddonsOn()
    local function yn(on)
      return on and "|cff20ff20yes|r" or "|cffff3030no|r"
    end
    local ps = GT.Prices and GT.Prices.status or {}
    p.health:SetText(format("TSM: %s   Auctionator: %s   NIT: %s   sellrate: |cffb8b8b8%s|r",
      yn(tsmOn),
      yn(atrOn or ps.atr or ps.atrLegacy),
      yn(nitOn),
      ps.sellrate or "none"))
    p.start:SetText(s.state == "RUNNING" and "Stop" or "Start")
  end

  if pages.loot:IsShown() then
    GT.UI.UpdateLoot()
  end
end

function GT.UI.SetMainScale(sc)
  if main then main:SetScale(sc) end
end

function GT.UI.Init()
  GT.UI.BuildHUD()
  GT.UI.UpdateHUD()
end
