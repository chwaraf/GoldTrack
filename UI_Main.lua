--[[ GoldTrack — main window: Total / Session / Loot / Config ]]
local GT = GoldTrack

GT.UI = GT.UI or {}

local main, tabs, pages
local lootRows = {}
local LOOT_VISIBLE = 14
local lootSort = "value"
local lootHideZero = false
local lootFilter = ""
local currentTab = "session"

local TAB_IDS = { "total", "session", "loot", "config" }
local TAB_LABEL = { total = "Total", session = "Session", loot = "Loot", config = "Config" }

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

local COL_MUTED = { 0.722, 0.722, 0.722 } -- #b8b8b8
local COL_GOLD = { 1, 0.820, 0 } -- #ffd100

local function applyPoint(frame, p, defx, defy)
  frame:ClearAllPoints()
  if p and p[1] then
    frame:SetPoint(p[1], _G[p[2]] or UIParent, p[3], p[4] or 0, p[5] or 0)
  else
    frame:SetPoint("CENTER", UIParent, "CENTER", defx or 0, defy or 0)
  end
end

-- One row per stat, centered on a minus:  name  -  value
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
  close:SetPoint("TOPRIGHT", 2, 2)
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
    tabs[id] = b

    local p = CreateFrame("Frame", nil, main)
    p:SetPoint("TOPLEFT", 6, -32)
    p:SetPoint("BOTTOMRIGHT", -6, 6)
    p:Hide()
    pages[id] = p
  end

  -- Total: stats fill the top; history list uses the rest of the pane
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
    p.meth = prev

    local wipe = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    wipe:SetSize(120, 22)
    wipe:SetPoint("BOTTOMLEFT", 4, 4)
    wipe:SetText("Clear lifetime")
    wipe:SetScript("OnClick", function() StaticPopup_Show("GOLDTRACK_WIPE") end)

    local hist = p:CreateFontString(nil, "OVERLAY")
    hist:SetFont(fontPath(), 17, "")
    hist:SetPoint("TOPLEFT", p.meth, "BOTTOMLEFT", 0, -10)
    hist:SetText("History")
    hist:SetTextColor(COL_GOLD[1], COL_GOLD[2], COL_GOLD[3])

    p.list = CreateFrame("ScrollFrame", "GoldTrackArchScroll", p, "FauxScrollFrameTemplate")
    p.list:SetPoint("TOPLEFT", hist, "BOTTOMLEFT", -2, -4)
    p.list:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -28, 30)
    p.ARCH_N = 12
    p.arch = {}
    for i = 1, p.ARCH_N do
      local r = CreateFrame("Button", nil, p)
      r:SetHeight(18)
      r:SetPoint("TOPLEFT", p.list, "TOPLEFT", 0, -(i - 1) * 18)
      r:SetPoint("TOPRIGHT", p.list, "TOPRIGHT", 0, -(i - 1) * 18)
      r.fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      r.fs:SetAllPoints()
      r.fs:SetJustifyH("LEFT")
      r.fs:SetWordWrap(false)
      p.arch[i] = r
    end
    p.list:SetScript("OnVerticalScroll", function(self, off)
      FauxScrollFrame_OnVerticalScroll(self, off, 18, GT.UI.UpdateArchive)
    end)
  end

  -- Session: large gold / g/h, then details; buttons at the bottom
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
    p.start = start
    local rst = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    rst:SetSize(80, 24)
    rst:SetPoint("LEFT", start, "RIGHT", 8, 0)
    rst:SetText("Reset")
    rst:SetScript("OnClick", function() StaticPopup_Show("GOLDTRACK_RESET") end)
  end

  -- Loot
  do
    local p = pages.loot
    -- Filter on row 1, column headers on row 2, list below. Nothing shares a line.
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
    local cb = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
    cb:SetPoint("LEFT", eb, "RIGHT", 8, 0)
    cb:SetSize(20, 20)
    local cbl = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cbl:SetPoint("LEFT", cb, "RIGHT", 0, 0)
    cbl:SetText("Hide 0")
    cb:SetScript("OnClick", function(self)
      lootHideZero = self:GetChecked()
      GT.UI.UpdateLoot()
    end)

    local hm = CreateFrame("Button", nil, p)
    hm:SetSize(COL_METH, 16)
    hm:SetPoint("TOPRIGHT", -6, -30)
    hm:SetNormalFontObject(GameFontNormal)
    hm:SetText("Src")
    hm:SetScript("OnClick", function() lootSort = "method"; GT.UI.UpdateLoot() end)
    local hv = CreateFrame("Button", nil, p)
    hv:SetSize(COL_VAL, 16)
    hv:SetPoint("RIGHT", hm, "LEFT", -4, 0)
    hv:SetNormalFontObject(GameFontNormal)
    hv:SetText("Gold")
    hv:SetScript("OnClick", function() lootSort = "value"; GT.UI.UpdateLoot() end)
    local hq = CreateFrame("Button", nil, p)
    hq:SetSize(COL_QTY, 16)
    hq:SetPoint("RIGHT", hv, "LEFT", -4, 0)
    hq:SetNormalFontObject(GameFontNormal)
    hq:SetText("Qty")
    hq:SetScript("OnClick", function() lootSort = "qty"; GT.UI.UpdateLoot() end)
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
        GameTooltip:AddLine(rw.why or "", 0.5, 0.8, 1, true)
        GameTooltip:Show()
      end)
      r:SetScript("OnLeave", function() GameTooltip:Hide() end)
      lootRows[i] = r
    end
    p.empty = p:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    p.empty:SetPoint("CENTER", p.scroll, "CENTER")
    p.empty:SetText("Start a session and loot something.")
  end

  GT.UI.main = main
  GT.UI.pages = pages
  if GT.UI.BuildConfig then GT.UI.BuildConfig(pages.config) end
  return main
end

function GT.UI.UpdateArchive()
  local p = pages and pages.total
  if not p or not p:IsShown() then return end
  local arch = GoldTrackCharDB.total.archives or {}
  local n = #arch
  local vis = p.ARCH_N or 12
  FauxScrollFrame_Update(p.list, n, vis, 18)
  local off = FauxScrollFrame_GetOffset(p.list)
  for i = 1, vis do
    local idx = n - off - i + 1 -- newest first
    local r = p.arch[i]
    local a = arch[idx]
    if a then
      r.fs:SetText(format("%s  %s  %s  %s",
        date("%m-%d %H:%M", a.t or 0),
        a.zone or "",
        GT.FormatElapsed(a.ms or 0),
        GT.FormatCopper(a.copper or 0)))
      r:Show()
    else
      r:Hide()
    end
  end
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
  -- Total includes current live
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
    GT.UI.UpdateArchive()
  end

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
    local ps = GT.Prices.status
    p.health:SetText(format("TSM: %s   Auctionator: %s   sellrate: %s",
      ps.tsm and "yes" or "no",
      (ps.atr or ps.atrLegacy) and "yes" or "no",
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
  -- main is lazy-built on first open
  GT.UI.UpdateHUD()
end
