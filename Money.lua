--[[ GoldTrack — copper parse / format (localized) ]]
local GT = GoldTrack

local floor = math.floor
local gsub, gmatch, format = string.gsub, string.gmatch, string.format

local goldPat, silverPat, copperPat

local function esc(s)
  return (s:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"))
end

local function numPat(global, fallback)
  local s = _G[global]
  if not s then return fallback end
  s = esc(s)
  s = s:gsub("%%%%d", "(%%d+)")
  s = s:gsub("%%%%s", "(%%d+)")
  return s
end

function GT.MoneyInit()
  goldPat = numPat("GOLD_AMOUNT", "(%d+)%s*[Gg]")
  silverPat = numPat("SILVER_AMOUNT", "(%d+)%s*[Ss]")
  copperPat = numPat("COPPER_AMOUNT", "(%d+)%s*[Cc]")
end

function GT.ParseCoinBlob(text)
  if not text then return 0 end
  if not goldPat then GT.MoneyInit() end
  local g = tonumber(text:match(goldPat)) or 0
  local s = tonumber(text:match(silverPat)) or 0
  local c = tonumber(text:match(copperPat)) or 0
  -- bare number fallback (some locales / split messages)
  if g == 0 and s == 0 and c == 0 then
    local n = tonumber((text:match("(%d+)")))
    if n then c = n end
  end
  return g * 10000 + s * 100 + c
end

function GT.FormatCopper(cop, short)
  -- Always one line, no coin textures (those wrap and collide in lists).
  cop = floor((cop or 0) + 0.5)
  local neg = cop < 0
  if cop < 0 then cop = -cop end
  local g = floor(cop / 10000)
  local s = floor((cop % 10000) / 100)
  local c = cop % 100
  local t
  if g > 0 then
    if short then
      t = format("|cffffd700%d g|r", g)
    else
      t = format("|cffffd700%dg|r |cffc7c7cf%ds|r", g, s)
    end
  elseif s > 0 then
    t = format("|cffc7c7cf%ds|r |cffeda55f%dc|r", s, c)
  else
    t = format("|cffeda55f%dc|r", c)
  end
  if neg then t = "-" .. t end
  return t
end

function GT.FormatGPH(copPerHour)
  if copPerHour == nil then return "-/hr" end
  return GT.FormatCopper(copPerHour, true) .. "/hr"
end

function GT.FormatElapsed(ms)
  ms = ms or 0
  if ms < 0 then ms = 0 end
  local sec = floor(ms / 1000)
  local h = floor(sec / 3600)
  local m = floor((sec % 3600) / 60)
  local s = sec % 60
  return format("%d:%02d:%02d", h, m, s)
end

-- Accepts 8.5 and 8,5 (EU). Nil if unparseable.
function GT.ParseNumber(t)
  if type(t) == "number" then return t end
  if t == nil or t == "" then return nil end
  t = tostring(t):gsub("%s+", ""):gsub(",", ".")
  return tonumber(t)
end

function GT.FmtNumber(n, maxDec)
  n = tonumber(n)
  if not n then return "" end
  if n == floor(n) then return tostring(n) end
  local s = format("%." .. (maxDec or 4) .. "f", n)
  s = s:gsub("0+$", ""):gsub("%.$", "")
  return s
end

function GT.GoldToCopper(g)
  return floor((GT.ParseNumber(g) or 0) * 10000 + 0.5)
end

function GT.CopperToGold(c)
  return (c or 0) / 10000
end
