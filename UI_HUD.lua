--[[ GoldTrack — compact HUD (XP-tracker layout) ]]
local GT = GoldTrack
local abs, floor, format = math.abs, math.floor, string.format

GT.UI = GT.UI or {}

local hud, pauseBtn, resetBtn, mini
local miniText -- fwd decl (used by pulse while collapsed)
local acc = 0

local BD = {
  bgFile = "Interface\\Buttons\\WHITE8x8",
  edgeFile = "Interface\\Buttons\\WHITE8x8",
  edgeSize = 1,
  insets = { l = 1, r = 1, t = 1, b = 1 },
}

function GT.UI.Backdrop(frame)
  if frame.SetBackdrop then
    frame:SetBackdrop(BD)
    frame:SetBackdropColor(0, 0, 0, 0.47)
    frame:SetBackdropBorderColor(0.122, 0.122, 0.122, 0.9)
  else
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    bg:SetVertexColor(0, 0, 0, 0.47)
  end
end

local function fontPath()
  if STANDARD_TEXT_FONT then return STANDARD_TEXT_FONT end
  local p = GameFontNormal:GetFont()
  return p or "Fonts\\FRIZQT__.TTF"
end

local function applyPoint(frame, p)
  frame:ClearAllPoints()
  if p and p[1] then
    frame:SetPoint(p[1], _G[p[2]] or UIParent, p[3], p[4] or 0, p[5] or 0)
    return
  end
  local cluster = _G.MinimapCluster or _G.Minimap
  if cluster then
    frame:SetPoint("TOP", cluster, "BOTTOM", 0, -8)
  else
    frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -24, -210)
  end
end

-- 71322.5 -> "71,322.5"
local function commaNum(n, decimals)
  if n == nil then return "-" end
  local s = format("%." .. (decimals or 0) .. "f", n)
  local sign, int, frac = s:match("^(%-?)(%d+)(%.?.*)$")
  int = int:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
  return (sign or "") .. int .. (frac or "")
end

local function copperGold(cop)
  return (cop or 0) / 10000
end

local function fmtTime(ms)
  ms = ms or 0
  if ms < 0 then ms = 0 end
  local sec = floor(ms / 1000)
  local h = floor(sec / 3600)
  local m = floor((sec % 3600) / 60)
  local s = sec % 60
  if h > 0 then
    return format("%d:%02d:%02d", h, m, s)
  end
  return format("%d:%02d", m, s)
end

function GT.UI.SaveHUDPoint(frame, key)
  local f = frame or hud
  local a, rel, b, x, y = f:GetPoint(1)
  GoldTrackDB[key or "hudPoint"] = { a, rel and rel:GetName() or "UIParent", b, x, y }
end

local function setText(fs, t)
  if not fs or fs._gt == t then return end
  fs._gt = t
  fs:SetText(t)
end

function GT.UI.HUDShouldPulse()
  if not hud then return false end
  if GoldTrackDB.hudCollapsed then
    if not (mini and mini:IsShown()) then return false end
  elseif not hud:IsShown() then
    return false
  end
  local s = GoldTrackCharDB and GoldTrackCharDB.session
  if s and s.state == "RUNNING" then return true end
  local _, _, left = GT.HourlyLockout()
  return left ~= nil
end

function GT.UI.SetHUDPulse()
  if not hud then return end
  local on = GT.UI.HUDShouldPulse()

  -- Collapsed: the square mini button carries the refresh pulse instead.
  if GoldTrackDB.hudCollapsed then
    if hud._pulse then
      hud._pulse = false
      hud:SetScript("OnUpdate", nil)
    end
    if mini and on and not mini._pulse then
      mini._pulse = true
      acc = 0
      mini:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc < (GT.HUD_INTERVAL or 1) then return end
        acc = 0
        miniText()
      end)
    elseif mini and mini._pulse and not on then
      mini._pulse = false
      mini:SetScript("OnUpdate", nil)
    end
    return
  end

  if mini and mini._pulse then
    mini._pulse = false
    mini:SetScript("OnUpdate", nil)
  end
  if on then
    if not hud._pulse then
      hud._pulse = true
      acc = 0
      hud:SetScript("OnUpdate", function(self, elapsed)
        acc = acc + elapsed
        if acc < (GT.HUD_INTERVAL or 1) then return end
        acc = 0
        GT.UI.UpdateHUD()
      end)
    end
  elseif hud._pulse then
    hud._pulse = false
    hud:SetScript("OnUpdate", nil)
  end
end

-- Whole-digit gold/hour for the collapsed square button.
function miniText()
  if not mini or not mini:IsShown() then return end
  local s = GoldTrackCharDB and GoldTrackCharDB.session
  if not s then return end
  local ms = GT.NowMs()
  local t
  if s.state == "RUNNING" and not GT.afkPaused then
    local ghCop = GT.GPerHour(s.copper or 0, ms)
    if ghCop == nil then
      local minSec = (GoldTrackDB and GoldTrackDB.minGhSeconds) or 30
      local left = math.ceil(minSec - (ms or 0) / 1000)
      if left < 0 then left = 0 end
      t = tostring(left) .. "s"
    else
      t = commaNum(copperGold(ghCop), 0)
    end
  elseif GT.afkPaused or s.startedAt then
    t = "P" -- paused: clock folded, session kept
  else
    t = "S" -- not started: fresh or just reset
  end
  setText(mini.text, t)
  -- Shrink until it fits inside the square (min readable size).
  local fp = fontPath()
  local size = floor(mini:GetHeight() * 0.42) -- scales with the square
  mini.text:SetFont(fp, size, "OUTLINE")
  while size > 6 and mini.text:GetStringWidth() > mini:GetWidth() - 4 do
    size = size - 1
    mini.text:SetFont(fp, size, "OUTLINE")
  end
end

function GT.UI.ToggleHUDCollapsed()
  if not hud or not mini then return end
  if not GoldTrackDB.hudCollapsed then
    -- Collapse onto the middle of the Start/Pause bar's last position.
    if hud:IsShown() and pauseBtn then
      local sc = hud:GetEffectiveScale() / UIParent:GetEffectiveScale()
      local cx, cy = pauseBtn:GetCenter() -- parent space, origin BOTTOMLEFT
      if cx and cy then
        GoldTrackDB.miniPoint =
          { "CENTER", "UIParent", "BOTTOMLEFT", cx * sc, cy * sc }
      end
    end
  end
  GoldTrackDB.hudCollapsed = not GoldTrackDB.hudCollapsed
  GT.UI.ApplyHUDVisibility()
  if not GoldTrackDB.hudCollapsed then
    GT.UI.UpdateHUD() -- refresh labels that froze while collapsed
  end
end

function GT.UI.UpdateHUD()
  if GoldTrackDB.hudCollapsed then
    miniText()
    return
  end
  if not hud or not hud:IsShown() then return end
  local s = GoldTrackCharDB and GoldTrackCharDB.session
  if not s then return end
  local ms = GT.NowMs()
  setText(hud.time, fmtTime(ms))
  setText(hud.gold, commaNum(copperGold(s.copper or 0), 2))

  if hud.lock then
    local used, maxn, left = GT.HourlyLockout()
    hud._lockUsed, hud._lockMax, hud._lockLeft = used, maxn, left
    if used == nil then
      setText(hud.lock, "-")
      hud.lock:SetTextColor(0.55, 0.55, 0.55)
    elseif left then
      local sec = floor(left)
      setText(hud.lock, format("%d:%02d", floor(sec / 60), sec % 60))
      hud.lock:SetTextColor(1, 0.2, 0.2)
    else
      setText(hud.lock, format("%d/%d", used, maxn or 5))
      hud.lock:SetTextColor(1, 1, 1)
    end
  end
  if hud.letT then
    local tsm, atr, nit = GT.AddonsOn()
    local function col(fs, on)
      if on then fs:SetTextColor(0.12, 1, 0.12) else fs:SetTextColor(1, 0.22, 0.22) end
    end
    col(hud.letT, tsm)
    col(hud.letA, atr)
    col(hud.letN, nit)
  end

  local ghCop = GT.GPerHour(s.copper or 0, ms)
  if ghCop == nil then
    local minSec = (GoldTrackDB and GoldTrackDB.minGhSeconds) or 30
    local left = math.ceil(minSec - (ms or 0) / 1000)
    if left < 0 then left = 0 end
    setText(hud.gph, tostring(left) .. "s")
    setText(hud.gpm, "-")
  else
    setText(hud.gph, commaNum(copperGold(ghCop), 1))
    setText(hud.gpm, commaNum(copperGold(ghCop) / 60, 1))
  end

  local run = s.state == "RUNNING" and not GT.afkPaused
  if pauseBtn then
    local lab = GT.afkPaused and "Resume" or (run and "Pause" or "Start")
    if pauseBtn._gt ~= lab then
      pauseBtn._gt = lab
      pauseBtn:SetText(lab)
    end
  end

  if GT.afkPaused then
    hud.time:SetTextColor(1, 0.8, 0.2)
  else
    hud.time:SetTextColor(1, 1, 1)
  end
  GT.UI.SetHUDPulse()
end

function GT.UI.ApplyHUDVisibility()
  if not hud then return end
  local visible = true
  if not GoldTrackDB.showHUD then
    visible = false
  elseif GoldTrackDB.hudMinLevelOn ~= false then
    local need = GoldTrackDB.hudMinLevel or 70
    local lvl = UnitLevel and UnitLevel("player") or 1
    if lvl < need then visible = false end
  end

  if GoldTrackDB.hudCollapsed and mini then
    hud:Hide()
    if visible then
      applyPoint(mini, GoldTrackDB.miniPoint or GoldTrackDB.hudPoint)
      mini:SetScale(GoldTrackDB.hudScale or 1)
      mini:Show()
      miniText()
    else
      mini:Hide()
    end
  else
    if mini then mini:Hide() end
    if visible then
      hud:Show()
    else
      hud:Hide()
    end
  end
  GT.UI.SetHUDPulse()
end

local function makeLabel(parent, text, size)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFont(fontPath(), size or 10, "")
  fs:SetText(text)
  fs:SetTextColor(0.820, 0.722, 0.322)
  fs:SetJustifyH("CENTER")
  fs:SetWordWrap(false)
  return fs
end

local function makeValue(parent, size, r, g, b)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFont(fontPath(), size or 14, "OUTLINE")
  fs:SetTextColor(r or 1, g or 1, b or 1)
  fs:SetJustifyH("CENTER")
  fs:SetWordWrap(false)
  fs:SetText("-")
  return fs
end

-- Tooltip plumbing ---------------------------------------------------------
local function attachTip(f, content)
  f:EnableMouse(true)
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
  return f
end

-- Invisible catcher laid over label+value pairs (FontStrings take no mouse).
local function hitOver(top, bottom, content)
  local f = CreateFrame("Frame", nil, top:GetParent())
  f:SetPoint("TOPLEFT", top, "TOPLEFT", -2, 2)
  f:SetPoint("BOTTOMRIGHT", bottom, "BOTTOMRIGHT", 2, -2)
  return attachTip(f, content)
end

function GT.UI.BuildHUD()
  if hud then return hud end
  local tmpl = BackdropTemplateMixin and "BackdropTemplate" or nil
  hud = CreateFrame("Frame", "GoldTrackHUD", UIParent, tmpl)
  hud:SetSize(158, 164)
  hud:SetFrameStrata("MEDIUM")
  hud:SetMovable(true)
  hud:EnableMouse(true)
  hud:RegisterForDrag("LeftButton")
  hud:SetClampedToScreen(true)
  GT.UI.Backdrop(hud)
  applyPoint(hud, GoldTrackDB.hudPoint)
  hud:SetScale(GoldTrackDB.hudScale or 1)

  hud:SetScript("OnDragStart", function(self)
    if GoldTrackDB.hudLocked then return end
    self:StartMoving()
  end)
  hud:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    GT.UI.SaveHUDPoint()
  end)

  local lootBtn = CreateFrame("Button", nil, hud, "UIPanelButtonTemplate")
  lootBtn:SetSize(40, 16)
  lootBtn:SetPoint("TOPLEFT", 3, -3)
  lootBtn:SetText("Loot")
  lootBtn:SetScript("OnClick", function()
    if GT.UI and GT.UI.ShowTab then GT.UI.ShowTab("loot") end
  end)
  attachTip(lootBtn, "Open the loot list (current session rows).")

  local hideBtn = CreateFrame("Button", nil, hud, "UIPanelButtonTemplate")
  hideBtn:SetSize(16, 16)
  hideBtn:SetPoint("TOPRIGHT", -3, -3)
  hideBtn:SetText("x")
  hideBtn:SetScript("OnClick", function()
    GoldTrackDB.showHUD = false
    GT.UI.ApplyHUDVisibility()
  end)
  attachTip(hideBtn, "Hide the HUD. Bring it back with /gt hud or the right-click menu.")

  local letA = hud:CreateFontString(nil, "OVERLAY")
  letA:SetFont(fontPath(), 10, "OUTLINE")
  letA:SetPoint("TOP", hud, "TOP", 0, -4)
  letA:SetText("A")
  local letT = hud:CreateFontString(nil, "OVERLAY")
  letT:SetFont(fontPath(), 10, "OUTLINE")
  letT:SetPoint("RIGHT", letA, "LEFT", -4, 0)
  letT:SetText("T")
  local letN = hud:CreateFontString(nil, "OVERLAY")
  letN:SetFont(fontPath(), 10, "OUTLINE")
  letN:SetPoint("LEFT", letA, "RIGHT", 4, 0)
  letN:SetText("N")
  hud.letT, hud.letA, hud.letN = letT, letA, letN

  do
    local srcHit = CreateFrame("Frame", nil, hud)
    srcHit:SetPoint("TOPLEFT", letT, "TOPLEFT", -2, 2)
    srcHit:SetPoint("BOTTOMRIGHT", letN, "BOTTOMRIGHT", 2, -2)
    attachTip(srcHit, function(tt)
      local tsm, atr, nit = GT.AddonsOn()
      local function yn(on) return on and "|cff20ff20loaded|r" or "|cffff3030missing|r" end
      tt:AddLine("Source addons", 1, 0.82, 0)
      tt:AddDoubleLine("T  TradeSkillMaster", yn(tsm), 0.8, 0.8, 0.8, 1, 1, 1)
      tt:AddDoubleLine("A  Auctionator", yn(atr), 0.8, 0.8, 0.8, 1, 1, 1)
      tt:AddDoubleLine("N  NovaInstanceTracker", yn(nit), 0.8, 0.8, 0.8, 1, 1, 1)
      tt:AddLine("Green = loaded, red = missing.", 0.55, 0.55, 0.55, true)
    end)
  end

  -- Top: TIME | (hourly count, no label) | GOLD
  local timeLab = makeLabel(hud, "TIME", 10)
  timeLab:SetPoint("TOPLEFT", 4, -22)
  timeLab:SetWidth(48)
  timeLab:SetJustifyH("CENTER")

  local timeVal = makeValue(hud, 13, 1, 1, 1)
  timeVal:SetPoint("TOPLEFT", timeLab, "BOTTOMLEFT", 0, -1)
  timeVal:SetWidth(48)
  timeVal:SetJustifyH("CENTER")
  hud.time = timeVal

  local goldLab = makeLabel(hud, "GOLD", 10)
  goldLab:SetPoint("TOPRIGHT", -4, -22)
  goldLab:SetWidth(48)
  goldLab:SetJustifyH("CENTER")

  local goldVal = makeValue(hud, 13, 1, 1, 1)
  goldVal:SetPoint("TOPRIGHT", goldLab, "BOTTOMRIGHT", 0, -1)
  goldVal:SetWidth(52)
  goldVal:SetJustifyH("CENTER")
  hud.gold = goldVal

  hitOver(timeLab, timeVal,
    "Active session time. Pauses while AFK (if enabled) and while the session is stopped.")
  hitOver(goldLab, goldVal,
    "Session estimate: disposition value of loot at the moment it dropped. Vendoring, mailing or auctioning it later never counts twice.")

  local lockVal = makeValue(hud, 13, 1, 1, 1)
  lockVal:SetPoint("LEFT", timeVal, "RIGHT", 0, 0)
  lockVal:SetPoint("RIGHT", goldVal, "LEFT", 0, 0)
  hud.lock = lockVal

  local lockHit = CreateFrame("Frame", nil, hud)
  lockHit:SetPoint("TOPLEFT", timeVal, "TOPRIGHT", -2, 6)
  lockHit:SetPoint("BOTTOMRIGHT", goldVal, "BOTTOMLEFT", 2, -6)
  lockHit:EnableMouse(true)
  lockHit:SetScript("OnEnter", function(self) GT.UI.LockTooltip(self) end)
  lockHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
  hud.lockHit = lockHit

  local gphLab = makeLabel(hud, "G/h", 10)
  gphLab:SetPoint("TOP", hud, "TOP", 0, -58)

  local gph = makeValue(hud, 28, 1, 0.820, 0)
  gph:SetPoint("TOP", gphLab, "BOTTOM", 0, 0)
  gph:SetWidth(150)
  hud.gph = gph

  hitOver(gphLab, gph, function(tt)
    tt:AddLine("Gold per hour", 1, 0.82, 0)
    local minSec = (GoldTrackDB and GoldTrackDB.minGhSeconds) or 30
    local ms = GT.NowMs()
    if ms < minSec * 1000 then
      tt:AddLine(format("Shows a countdown for the first %ds so early numbers cannot mislead.",
        minSec), 0.8, 0.8, 0.8, true)
    end
    tt:AddLine("Session gold divided by active time. Raw ratio, no smoothing.", 0.55, 0.55, 0.55, true)
  end)

  pauseBtn = CreateFrame("Button", nil, hud, "UIPanelButtonTemplate")
  pauseBtn:SetHeight(29)
  pauseBtn:SetPoint("BOTTOMLEFT", hud, "BOTTOMLEFT", 4, 5)
  pauseBtn:SetPoint("BOTTOMRIGHT", hud, "BOTTOMRIGHT", -4, 5)
  pauseBtn:SetText("Start")
  pauseBtn:RegisterForClicks("AnyUp")
  pauseBtn:SetScript("OnClick", function(_, btn)
    if btn == "RightButton" then
      GT.UI.ToggleHUDCollapsed() -- collapse HUD to the gold/h square
      return
    end
    local s = GoldTrackCharDB.session
    if s.state == "RUNNING" and not GT.afkPaused then
      GT.SessionStop()
    else
      GT.SessionStart()
    end
  end)
  attachTip(pauseBtn, function(tt)
    if GT.afkPaused then
      tt:AddLine("Resume", 1, 0.82, 0)
      tt:AddLine("Continue the session clock after an AFK pause.", 0.8, 0.8, 0.8, true)
    elseif GoldTrackCharDB.session.state == "RUNNING" then
      tt:AddLine("Pause", 1, 0.82, 0)
      tt:AddLine("Fold the session clock. Loot rows are kept; Reset archives and clears.",
        0.8, 0.8, 0.8, true)
    else
      tt:AddLine("Start", 1, 0.82, 0)
      tt:AddLine("Run the session clock and count world-loot value from now on.",
        0.8, 0.8, 0.8, true)
    end
    tt:AddLine("Right-click: collapse the HUD to a gold/h square.", 0.55, 0.55, 0.55, true)
  end)

  resetBtn = CreateFrame("Button", nil, hud, "UIPanelButtonTemplate")
  resetBtn:SetSize(54, 18)
  resetBtn:SetPoint("BOTTOMRIGHT", pauseBtn, "TOPRIGHT", 0, 4)
  resetBtn:SetText("Reset")
  resetBtn:SetScript("OnClick", function()
    StaticPopup_Show("GOLDTRACK_RESET")
  end)
  attachTip(resetBtn, "Archive this session into Total, then clear it. Asks to confirm.")

  -- Collapsed square: side = 2x Start/Pause button height. Same button chrome
  -- as Start but tinted red (so it reads as a button, not stray text). Shows
  -- gold/h (whole digits). Right-click expands back to the full HUD.
  mini = CreateFrame("Button", "GoldTrackHUDMini", UIParent, "UIPanelButtonTemplate")
  local mside = (pauseBtn:GetHeight() or 29) * 2
  mini:SetSize(mside, mside)
  mini:SetFrameStrata("MEDIUM")
  mini:SetMovable(true)
  mini:EnableMouse(true)
  mini:RegisterForDrag("LeftButton")
  mini:SetClampedToScreen(true)
  do -- red tint on the panel-button textures (border stays from the template)
    local nt = mini:GetNormalTexture()
    if nt then nt:SetVertexColor(0.75, 0.12, 0.12) end
    local pt = mini:GetPushedTexture()
    if pt then pt:SetVertexColor(0.55, 0.08, 0.08) end
    local ht = mini:GetHighlightTexture()
    if ht then ht:SetVertexColor(1, 0.55, 0.55) end
  end
  applyPoint(mini, GoldTrackDB.miniPoint or GoldTrackDB.hudPoint)
  mini:SetScale(GoldTrackDB.hudScale or 1)
  mini:Hide()

  mini.text = mini:CreateFontString(nil, "OVERLAY")
  mini.text:SetFont(fontPath(), 10, "OUTLINE")
  mini.text:SetPoint("CENTER")
  mini.text:SetTextColor(1, 0.820, 0)
  mini.text:SetJustifyH("CENTER")
  mini.text:SetWordWrap(false)
  mini.text:SetText("-")

  mini:RegisterForClicks("AnyUp")
  mini:SetScript("OnClick", function(_, btn)
    if btn == "RightButton" then
      GT.UI.ToggleHUDCollapsed() -- restore the full HUD
      return
    end
    local s = GoldTrackCharDB.session
    if s.state == "RUNNING" and not GT.afkPaused then
      GT.SessionStop()
    else
      GT.SessionStart()
    end
  end)
  mini:SetScript("OnDragStart", function(self)
    if GoldTrackDB.hudLocked then return end
    self:StartMoving()
  end)
  mini:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    GT.UI.SaveHUDPoint(self, "miniPoint") -- keep the full HUD's own anchor
  end)
  attachTip(mini, function(tt)
    tt:AddLine("Gold per hour (collapsed HUD)", 1, 0.82, 0)
    tt:AddLine("P = paused   S = not started", 0.72, 0.72, 0.72)
    tt:AddLine("Left-click: Start / Pause the session.", 0.8, 0.8, 0.8, true)
    tt:AddLine("Right-click: restore the full HUD.", 0.8, 0.8, 0.8, true)
  end)

  -- Same 4px gap above Start as Reset uses.
  local gpmLab = makeLabel(hud, "G/m", 10)
  gpmLab:SetJustifyH("LEFT")
  local gpm = makeValue(hud, 14, 1, 0.820, 0)
  gpm:SetJustifyH("LEFT")
  gpm:SetPoint("BOTTOMLEFT", pauseBtn, "TOPLEFT", 6, 4)
  gpmLab:SetPoint("BOTTOMLEFT", gpm, "TOPLEFT", 0, 1)
  hud.gpm = gpm

  hitOver(gpmLab, gpm, "Gold per minute for the active session.")

  -- click empty area (not the buttons) toggles main
  hud:SetScript("OnMouseDown", function(self, btn)
    if btn == "LeftButton" and not GoldTrackDB.hudLocked then
      self._sx, self._sy = GetCursorPosition()
    end
  end)
  hud:SetScript("OnMouseUp", function(self, btn)
    if btn == "RightButton" then
      GT.UI.HUDMenu()
      return
    end
    if btn == "LeftButton" then
      local x, y = GetCursorPosition()
      if self._sx and (abs(x - self._sx) + abs(y - self._sy)) < 4 then
        GT.UI.ToggleMain()
      end
    end
  end)

  GT.UI.hud = hud
  GT.UI.ApplyHUDVisibility()
  GT.UI.UpdateHUD()
  return hud
end

function GT.UI.LockTooltip(owner)
  if not owner or not GameTooltip then return end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:ClearLines()
  GameTooltip:AddLine("Hourly instances", 1, 0.82, 0)
  local used = hud and hud._lockUsed
  local maxn = (hud and hud._lockMax) or 5
  local left = hud and hud._lockLeft
  if used == nil then
    GameTooltip:AddLine("NovaInstanceTracker is not loaded.", 0.8, 0.8, 0.8, true)
    GameTooltip:AddLine("HUD count matches the NIT minimap button.", 0.55, 0.55, 0.55, true)
    GameTooltip:Show()
    return
  end
  GameTooltip:AddLine(format("%d of %d in the last hour", used, maxn), 1, 1, 1)
  if left then
    local sec = floor(left)
    GameTooltip:AddLine(format("Oldest frees in %d:%02d", floor(sec / 60), sec % 60), 1, 0.2, 0.2)
  else
    local rest = maxn - used
    if rest < 0 then rest = 0 end
    GameTooltip:AddLine(format("%d slot%s remaining", rest, rest == 1 and "" or "s"), 0.12, 1, 0.12)
  end
  local NIT = _G.NIT
  if NIT and type(NIT.getMinimapButtonNextExpires) == "function" then
    local ok, extra = pcall(NIT.getMinimapButtonNextExpires, NIT)
    if ok and type(extra) == "string" then
      for line in extra:gmatch("[^\n]+") do
        local plain = line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        if plain ~= "" then
          GameTooltip:AddLine(plain, 0.72, 0.72, 0.72)
        end
      end
    end
  end
  GameTooltip:AddLine("From NovaInstanceTracker (same as NIT minimap). NIT counts when you leave.", 0.55, 0.55, 0.55, true)
  GameTooltip:Show()
end

function GT.UI.HUDMenu()
  if not GT.UI.ctx then
    local tmpl = BackdropTemplateMixin and "BackdropTemplate" or nil
    local m = CreateFrame("Frame", "GoldTrackCtx", UIParent, tmpl)
    m:SetFrameStrata("TOOLTIP")
    m:SetSize(140, 88)
    GT.UI.Backdrop(m)
    m:EnableMouse(true)
    m:Hide()
    m._life = 0
    m:SetScript("OnUpdate", function(self, elapsed)
      if not self:IsShown() then return end
      if MouseIsOver(self) then
        self._life = 0
        return
      end
      self._life = (self._life or 0) + elapsed
      if self._life >= 3 then
        self:Hide()
        self._life = 0
      end
    end)
    local labels = { "Lock HUD", "Reset session", "Hide HUD", "Config" }
    for i = 1, 4 do
      local b = CreateFrame("Button", nil, m)
      b:SetSize(132, 20)
      b:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 21)
      b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      b.text:SetPoint("LEFT", 4, 0)
      b.text:SetText(labels[i])
      b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
      b:SetScript("OnClick", function()
        if i == 1 then
          GoldTrackDB.hudLocked = not GoldTrackDB.hudLocked
        elseif i == 2 then
          StaticPopup_Show("GOLDTRACK_RESET")
        elseif i == 3 then
          GoldTrackDB.showHUD = not GoldTrackDB.showHUD
          GT.UI.ApplyHUDVisibility()
        else
          GT.UI.ShowTab("config")
        end
        m:Hide()
      end)
      m[i] = b
    end
    GT.UI.ctx = m
  end
  local m = GT.UI.ctx
  m[1].text:SetText(GoldTrackDB.hudLocked and "Unlock HUD" or "Lock HUD")
  m[3].text:SetText(GoldTrackDB.showHUD and "Hide HUD" or "Show HUD")
  local x, y = GetCursorPosition()
  local sc = UIParent:GetEffectiveScale()
  local px, py = x / sc, y / sc
  local mw, mh = m:GetWidth(), m:GetHeight()
  local uiw, uih = UIParent:GetWidth(), UIParent:GetHeight()
  -- TOPLEFT of menu at cursor; keep fully on screen
  if px + mw > uiw then px = uiw - mw end
  if py > uih then py = uih end
  if px < 0 then px = 0 end
  if py - mh < 0 then py = mh end
  m:ClearAllPoints()
  m:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", px, py)
  m:SetClampedToScreen(true)
  m:Show()
  m._life = 0
end

function GT.UI.SetHUDScale(sc)
  if hud then hud:SetScale(sc) end
  if mini then mini:SetScale(sc) end
end
