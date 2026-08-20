--[[ GoldTrack — compact HUD (XP-tracker layout) ]]
local GT = GoldTrack
local abs, floor, format = math.abs, math.floor, string.format

GT.UI = GT.UI or {}

local hud, pauseBtn, resetBtn
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

function GT.UI.SaveHUDPoint()
  local a, rel, b, x, y = hud:GetPoint(1)
  GoldTrackDB.hudPoint = { a, rel and rel:GetName() or "UIParent", b, x, y }
end

function GT.UI.UpdateHUD()
  if not hud then return end
  local s = GoldTrackCharDB and GoldTrackCharDB.session
  if not s then return end
  local ms = GT.NowMs()
  hud.time:SetText(fmtTime(ms))
  hud.gold:SetText(commaNum(copperGold(s.copper or 0), 2))

  local ghCop = GT.GPerHour(s.copper or 0, ms)
  if ghCop == nil then
    local minSec = (GoldTrackDB and GoldTrackDB.minGhSeconds) or 30
    local left = math.ceil(minSec - (ms or 0) / 1000)
    if left < 0 then left = 0 end
    hud.gph:SetText(tostring(left) .. "s")
    hud.gpm:SetText("-")
  else
    hud.gph:SetText(commaNum(copperGold(ghCop), 1))
    hud.gpm:SetText(commaNum(copperGold(ghCop) / 60, 1))
  end

  local run = s.state == "RUNNING" and not GT.afkPaused
  if pauseBtn then
    if GT.afkPaused then
      pauseBtn:SetText("Resume")
    elseif run then
      pauseBtn:SetText("Pause")
    else
      pauseBtn:SetText("Start")
    end
  end

  if GT.afkPaused then
    hud.time:SetTextColor(1, 0.8, 0.2)
  else
    hud.time:SetTextColor(1, 1, 1)
  end
end

function GT.UI.ApplyHUDVisibility()
  if not hud then return end
  if GoldTrackDB.showHUD then hud:Show() else hud:Hide() end
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

function GT.UI.BuildHUD()
  if hud then return hud end
  local tmpl = BackdropTemplateMixin and "BackdropTemplate" or nil
  hud = CreateFrame("Frame", "GoldTrackHUD", UIParent, tmpl)
  hud:SetSize(158, 150)
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

  -- Top: TIME | GOLD, each half of the frame
  local timeLab = makeLabel(hud, "TIME", 10)
  timeLab:SetPoint("TOPLEFT", 4, -6)
  timeLab:SetPoint("TOPRIGHT", hud, "TOP", -2, -6)

  local timeVal = makeValue(hud, 13, 1, 1, 1)
  timeVal:SetPoint("TOPLEFT", timeLab, "BOTTOMLEFT", 0, -1)
  timeVal:SetPoint("TOPRIGHT", timeLab, "BOTTOMRIGHT", 0, -1)
  hud.time = timeVal

  local goldLab = makeLabel(hud, "GOLD", 10)
  goldLab:SetPoint("TOPLEFT", hud, "TOP", 2, -6)
  goldLab:SetPoint("TOPRIGHT", -4, -6)

  local goldVal = makeValue(hud, 13, 1, 1, 1)
  goldVal:SetPoint("TOPLEFT", goldLab, "BOTTOMLEFT", 0, -1)
  goldVal:SetPoint("TOPRIGHT", goldLab, "BOTTOMRIGHT", 0, -1)
  hud.gold = goldVal

  local gphLab = makeLabel(hud, "G/h", 10)
  gphLab:SetPoint("TOP", hud, "TOP", 0, -44)

  local gph = makeValue(hud, 28, 1, 0.820, 0)
  gph:SetPoint("TOP", gphLab, "BOTTOM", 0, 0)
  gph:SetWidth(150)
  hud.gph = gph

  local gpmLab = makeLabel(hud, "G/m", 10)
  gpmLab:SetPoint("TOPLEFT", 10, -86)
  gpmLab:SetJustifyH("LEFT")

  local gpm = makeValue(hud, 14, 1, 0.820, 0)
  gpm:SetPoint("TOPLEFT", gpmLab, "BOTTOMLEFT", 0, -1)
  gpm:SetJustifyH("LEFT")
  hud.gpm = gpm

  pauseBtn = CreateFrame("Button", nil, hud, "UIPanelButtonTemplate")
  pauseBtn:SetHeight(29)
  pauseBtn:SetPoint("BOTTOMLEFT", hud, "BOTTOMLEFT", 4, 5)
  pauseBtn:SetPoint("BOTTOMRIGHT", hud, "BOTTOMRIGHT", -4, 5)
  pauseBtn:SetText("Start")
  pauseBtn:SetScript("OnClick", function()
    local s = GoldTrackCharDB.session
    if s.state == "RUNNING" and not GT.afkPaused then
      GT.SessionStop()
    else
      GT.SessionStart()
    end
  end)

  resetBtn = CreateFrame("Button", nil, hud, "UIPanelButtonTemplate")
  resetBtn:SetSize(54, 18)
  resetBtn:SetPoint("BOTTOMRIGHT", pauseBtn, "TOPRIGHT", 0, 4)
  resetBtn:SetText("Reset")
  resetBtn:SetScript("OnClick", function()
    StaticPopup_Show("GOLDTRACK_RESET")
  end)

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

  hud:SetScript("OnUpdate", function(self, elapsed)
    local s = GoldTrackCharDB and GoldTrackCharDB.session
    if not s or s.state ~= "RUNNING" then
      acc = 0
      return
    end
    acc = acc + elapsed
    if acc < GT.HUD_INTERVAL then return end
    acc = 0
    GT.UI.UpdateHUD()
  end)

  GT.UI.hud = hud
  GT.UI.ApplyHUDVisibility()
  GT.UI.UpdateHUD()
  return hud
end

function GT.UI.HUDMenu()
  if not GT.UI.ctx then
    local tmpl = BackdropTemplateMixin and "BackdropTemplate" or nil
    local m = CreateFrame("Frame", "GoldTrackCtx", UIParent, tmpl)
    m:SetFrameStrata("TOOLTIP")
    m:SetSize(140, 88)
    GT.UI.Backdrop(m)
    m:Hide()
    m:SetScript("OnLeave", function(self)
      if not self:IsMouseOver() then self:Hide() end
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
  m:ClearAllPoints()
  m:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / sc, y / sc)
  m:Show()
end

function GT.UI.SetHUDScale(sc)
  if hud then hud:SetScale(sc) end
end
