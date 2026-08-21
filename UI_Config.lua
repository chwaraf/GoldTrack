--[[ GoldTrack — config tab: short labels, scroll, nothing clips ]]
local GT = GoldTrack

GT.UI = GT.UI or {}

local function tipOn(frame, text)
  if not text then return end
  frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(text, 1, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function row(parent, y)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(22)
  f:SetPoint("TOPLEFT", 8, y)
  f:SetPoint("TOPRIGHT", -24, y)
  local dash = f:CreateFontString(nil, "OVERLAY")
  dash:SetFont((STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"), 13, "")
  dash:SetPoint("CENTER", 0, 0)
  dash:SetText("-")
  dash:SetTextColor(0.55, 0.55, 0.55)
  f.dash = dash
  return f, y - 24
end

local function nameLabel(r, label)
  local fs = r:CreateFontString(nil, "OVERLAY")
  fs:SetFont((STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"), 13, "")
  fs:SetPoint("RIGHT", r.dash, "LEFT", -8, 0)
  fs:SetJustifyH("RIGHT")
  fs:SetWordWrap(false)
  fs:SetText(label)
  fs:SetTextColor(0.722, 0.722, 0.722)
  return fs
end

local function check(parent, y, label, get, set, tip)
  local r, ny = row(parent, y)
  nameLabel(r, label)
  local cb = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
  cb:SetPoint("LEFT", r.dash, "RIGHT", 8, 0)
  cb:SetSize(24, 24)
  cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
  tipOn(cb, tip)
  tipOn(r, tip)
  cb._refresh = function() cb:SetChecked(get()) end
  return cb, ny
end

local function edit(parent, y, label, get, set, tip)
  local r, ny = row(parent, y)
  nameLabel(r, label)
  local eb = CreateFrame("EditBox", nil, r, "InputBoxTemplate")
  eb:SetSize(76, 20)
  eb:SetPoint("LEFT", r.dash, "RIGHT", 8, 0)
  eb:SetAutoFocus(false)
  eb:SetMaxLetters(16)
  eb:SetNumeric(false)
  eb:SetScript("OnEnterPressed", function(self)
    set(self:GetText())
    self:ClearFocus()
  end)
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  eb:SetScript("OnEditFocusLost", function(self) set(self:GetText()) end)
  tipOn(r, tip)
  tipOn(eb, tip)
  eb._refresh = function() eb:SetText(tostring(get())) end
  return eb, ny
end

local function cycle(parent, y, label, options, get, set, tip)
  local r, ny = row(parent, y)
  nameLabel(r, label)
  local b = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
  b:SetSize(138, 20)
  b:SetPoint("LEFT", r.dash, "RIGHT", 8, 0)
  b:SetScript("OnClick", function()
    local cur = get()
    local idx = 1
    for i = 1, #options do
      if options[i][1] == cur then idx = i; break end
    end
    idx = idx + 1
    if idx > #options then idx = 1 end
    set(options[idx][1])
    b:SetText(options[idx][2])
  end)
  tipOn(r, tip)
  tipOn(b, tip)
  b._refresh = function()
    local cur = get()
    local text = cur
    for i = 1, #options do
      if options[i][1] == cur then text = options[i][2]; break end
    end
    b:SetText(text)
  end
  return b, ny
end

local function header(parent, y, text)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFont((STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"), 17, "")
  fs:SetPoint("TOPLEFT", 8, y)
  fs:SetPoint("TOPRIGHT", -24, y)
  fs:SetJustifyH("CENTER")
  fs:SetText(text)
  fs:SetTextColor(1, 0.820, 0)
  return y - 22
end

function GT.UI.BuildConfig(p)
  if p._built then return end
  p._built = true

  local scroll = CreateFrame("ScrollFrame", "GoldTrackCfgScroll", p, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 2, -4)
  scroll:SetPoint("BOTTOMRIGHT", -28, 4)
  local child = CreateFrame("Frame", nil, scroll)
  child:SetWidth(460)
  child:SetHeight(620)
  scroll:SetScrollChild(child)
  p.ctrls = {}
  local y = -4
  local c

  y = header(child, y, "Valuation")
  c, y = edit(child, y, "Gear: AH beats vendor by (g)",
    function() return GT.FmtNumber(GT.CopperToGold(GoldTrackDB.ahMinVsVendor)) end,
    function(t) GoldTrackDB.ahMinVsVendor = GT.GoldToCopper(t) end,
    "DE-able gear only. Default 10g. Decimals ok (8.5 or 8,5).")
  p.ctrls[#p.ctrls + 1] = c
  c, y = edit(child, y, "Gear: AH beats DE by (g)",
    function() return GT.FmtNumber(GT.CopperToGold(GoldTrackDB.ahMinVsDE)) end,
    function(t) GoldTrackDB.ahMinVsDE = GT.GoldToCopper(t) end,
    "AH must also beat disenchant by this much. Default 8g.")
  p.ctrls[#p.ctrls + 1] = c
  c, y = edit(child, y, "DE beats vendor by (g)",
    function() return GT.FmtNumber(GT.CopperToGold(GoldTrackDB.deMinVsVendor)) end,
    function(t) GoldTrackDB.deMinVsVendor = GT.GoldToCopper(t) end)
  p.ctrls[#p.ctrls + 1] = c
  c, y = edit(child, y, "Mats: AH >= vendor x",
    function() return GT.FmtNumber(GoldTrackDB.commonAhMult) end,
    function(t) GoldTrackDB.commonAhMult = GT.ParseNumber(t) or 3 end,
    "Stackables and recipes. Default 3. Decimals ok.")
  p.ctrls[#p.ctrls + 1] = c
  c, y = edit(child, y, "Mats: or vendor + (g)",
    function() return GT.FmtNumber(GT.CopperToGold(GoldTrackDB.commonAhFlat)) end,
    function(t) GoldTrackDB.commonAhFlat = GT.GoldToCopper(t) end,
    "If vendor is 0, only this test is used. Default 1g.")
  p.ctrls[#p.ctrls + 1] = c
  c, y = edit(child, y, "Min sell rate (0-1)",
    function() return GT.FmtNumber(GoldTrackDB.ahMinSellRate) end,
    function(t) GoldTrackDB.ahMinSellRate = GT.ParseNumber(t) or 0.1 end,
    "Below this, AH is skipped. Auctionator has no sell rate.")
  p.ctrls[#p.ctrls + 1] = c
  c, y = edit(child, y, "Fallback sell rate",
    function() return GT.FmtNumber(GoldTrackDB.ahUnknownSellRate) end,
    function(t) GoldTrackDB.ahUnknownSellRate = GT.ParseNumber(t) or 0.5 end,
    "Used when TSM has no DBRegionSaleRate.")
  p.ctrls[#p.ctrls + 1] = c
  c, y = check(child, y, "Subtract expected AH deposit",
    function() return GoldTrackDB.subtractDeposit end,
    function(v) GoldTrackDB.subtractDeposit = v end,
    "Deposit comes back if it sells. We subtract deposit x (1 - sell rate).")
  p.ctrls[#p.ctrls + 1] = c

  y = y - 6
  y = header(child, y, "Sources")
  c, y = cycle(child, y, "Price source", {
      { "atr_fresh_tsm", "Atr <2h else TSM" },
      { "tsm_then_atr", "TSM then Atr" },
      { "atr_then_tsm", "Atr then TSM" },
      { "tsm_only", "TSM only" },
      { "atr_only", "Atr only" },
    },
    function() return GoldTrackDB.priceSource end,
    function(v)
      GoldTrackDB.priceSource = v
      if GT.Prices and GT.Prices.Invalidate then GT.Prices.Invalidate() end
    end,
    "Default: Auctionator if last scan is under 2 hours, else TSM.")
  p.ctrls[#p.ctrls + 1] = c
  c, y = cycle(child, y, "TSM price", {
      { "market", "Market" },
      { "minbuyout", "Min buyout" },
      { "recent", "Recent" },
      { "historical", "Historical" },
      { "regionsaleavg", "Region sale avg" },
    },
    function() return GoldTrackDB.tsmPriceField end,
    function(v)
      GoldTrackDB.tsmPriceField = v
      if GT.Prices and GT.Prices.Invalidate then GT.Prices.Invalidate() end
    end,
    "Which TSM AuctionDB field to read. Frozen at loot time for g/h.")
  p.ctrls[#p.ctrls + 1] = c
  c, y = cycle(child, y, "AH price field", {
      { "conservative", "Conservative" },
      { "market", "Market" },
      { "minbuyout", "Min buyout" },
    },
    function() return GoldTrackDB.ahPriceField end,
    function(v) GoldTrackDB.ahPriceField = v end,
    "Conservative prefers market and drops bait min-buyouts.")
  p.ctrls[#p.ctrls + 1] = c
  c, y = cycle(child, y, "AH value mode", {
      { "if_sold", "If sold" },
      { "expected_single", "One-post EV" },
      { "expected_relist", "Relist until sold" },
    },
    function() return GoldTrackDB.ahValueMode end,
    function(v) GoldTrackDB.ahValueMode = v end)
  p.ctrls[#p.ctrls + 1] = c
  c, y = cycle(child, y, "Deposit preset", {
      { "24h_30", "24h / 30%" },
      { "12h_15", "12h / 15%" },
      { "48h_60", "48h / 60%" },
      { "ignore", "Ignore" },
      { "custom", "Custom" },
    },
    function() return GoldTrackDB.ahDepositPreset end,
    function(v) GoldTrackDB.ahDepositPreset = v end)
  p.ctrls[#p.ctrls + 1] = c

  y = y - 6
  y = header(child, y, "Session / UI")
  c, y = edit(child, y, "Seconds before g/h",
    function() return GT.FmtNumber(GoldTrackDB.minGhSeconds) end,
    function(t) GoldTrackDB.minGhSeconds = GT.ParseNumber(t) or 30 end,
    "HUD shows remaining seconds in the g/h slot until this. Default 30.")
  p.ctrls[#p.ctrls + 1] = c
  c, y = edit(child, y, "HUD scale",
    function() return GT.FmtNumber(GoldTrackDB.hudScale) end,
    function(t)
      local n = GT.ParseNumber(t) or 1
      GoldTrackDB.hudScale = n
      GT.UI.SetHUDScale(n)
    end)
  p.ctrls[#p.ctrls + 1] = c
  c, y = edit(child, y, "Window scale",
    function() return GT.FmtNumber(GoldTrackDB.mainScale) end,
    function(t)
      local n = GT.ParseNumber(t) or 1
      GoldTrackDB.mainScale = n
      GT.UI.SetMainScale(n)
    end)
  p.ctrls[#p.ctrls + 1] = c
  c, y = check(child, y, "Pause clock while AFK",
    function() return GoldTrackDB.pauseWhenAFK end,
    function(v) GoldTrackDB.pauseWhenAFK = v end)
  p.ctrls[#p.ctrls + 1] = c
  c, y = check(child, y, "Resume after /reload",
    function() return GoldTrackDB.resumeAfterReload end,
    function(v) GoldTrackDB.resumeAfterReload = v end)
  p.ctrls[#p.ctrls + 1] = c
  c, y = check(child, y, "Resume after logout",
    function() return GoldTrackDB.resumeAfterLogout end,
    function(v) GoldTrackDB.resumeAfterLogout = v end,
    "Off by default so overnight logout does not wreck g/h.")
  p.ctrls[#p.ctrls + 1] = c
  c, y = check(child, y, "Count quest rewards",
    function() return GoldTrackDB.countQuestRewards end,
    function(v) GoldTrackDB.countQuestRewards = v end)
  p.ctrls[#p.ctrls + 1] = c
  c, y = check(child, y, "Show HUD",
    function() return GoldTrackDB.showHUD end,
    function(v) GoldTrackDB.showHUD = v; GT.UI.ApplyHUDVisibility() end)
  p.ctrls[#p.ctrls + 1] = c
  c, y = check(child, y, "HUD min level",
    function() return GoldTrackDB.hudMinLevelOn ~= false end,
    function(v) GoldTrackDB.hudMinLevelOn = v; GT.UI.ApplyHUDVisibility() end,
    "Hide HUD below this character level. Default on.")
  p.ctrls[#p.ctrls + 1] = c
  c, y = edit(child, y, "HUD min level value",
    function() return GT.FmtNumber(GoldTrackDB.hudMinLevel or 70) end,
    function(t)
      GoldTrackDB.hudMinLevel = math.floor(GT.ParseNumber(t) or 70)
      GT.UI.ApplyHUDVisibility()
    end,
    "Default 70. HUD stays hidden until you reach this level.")
  p.ctrls[#p.ctrls + 1] = c
  c, y = check(child, y, "Lock HUD",
    function() return GoldTrackDB.hudLocked end,
    function(v) GoldTrackDB.hudLocked = v end)
  p.ctrls[#p.ctrls + 1] = c

  child:SetHeight(-y + 16)

  p:SetScript("OnShow", function()
    for i = 1, #p.ctrls do
      if p.ctrls[i]._refresh then p.ctrls[i]._refresh() end
    end
  end)
end
