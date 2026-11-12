-- Window looks matching EllesmereUI's, trimmed from CraftRoute's Theme.lua.
--   default  - EscortReady's own look (dark dialog box). The only look without EllesmereUI.
--   auto     - whatever look EllesmereUI is drawing (the default pick).
--   eui      - EllesmereUI Style: flat dark panel, thin border, the user's accent colour.
--   forever  - WoW Forever: Blizzard's frame art, which this client draws in Forever's bronze.
--   blizzard - Blizzard Style: the same art forced to retail's look via EllesmereUI.StockAtlas.
--   classic  - Classic WoW UI: the vanilla dialog border over the rock background.
-- The typeface follows EllesmereUI's global font while that addon is loaded.
local _, ER = ...

ER.THEMES = {
  { key = "auto",     text = "Match EllesmereUI" },
  { key = "default",  text = "EscortReady default" },
  { key = "eui",      text = "EllesmereUI Style" },
  { key = "forever",  text = "WoW Forever", foreverOnly = true },
  { key = "blizzard", text = "Blizzard Style" },
  { key = "classic",  text = "Classic WoW UI" },
}

function ER.HasEllesmere()
  return type(EllesmereUI) == "table" and EllesmereUI.ELLESMERE_GREEN ~= nil
end

function ER.ActiveTheme()
  if not ER.HasEllesmere() then return "default" end
  local pick = ER.db and ER.db.theme or "auto"
  if pick == "auto" then
    local ok, look = pcall(EllesmereUI.RenderedLook)
    pick = (ok and type(look) == "string") and look or "default"
  end
  if pick == "forever" and not EllesmereUI.IS_FOREVER then pick = "blizzard" end
  return pick
end

function ER.AccentColor()
  if ER.ActiveTheme() == "eui" then
    local eg = EllesmereUI.ELLESMERE_GREEN
    return eg.r, eg.g, eg.b
  end
  return 1, 0.82, 0
end

-- The looks offered in the options (the ones this client can draw), "auto" naming what it resolves to.
function ER.LookOptions()
  local opts = {}
  for _, t in ipairs(ER.THEMES) do
    if not t.foreverOnly or (EllesmereUI and EllesmereUI.IS_FOREVER) then
      local text = t.text
      if t.key == "auto" and ER.HasEllesmere() then
        local ok, look = pcall(EllesmereUI.RenderedLook)
        for _, x in ipairs(ER.THEMES) do
          if ok and x.key == look then text = text .. " (" .. x.text .. ")" end
        end
      end
      opts[#opts + 1] = { value = t.key, text = text }
    end
  end
  return opts
end

---------------------------------------------------------------------------
-- Window shell
---------------------------------------------------------------------------
local DEFAULT_BACKDROP = {
  bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
  edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
  tile = true, tileSize = 32, edgeSize = 32,
  insets = { left = 11, right = 12, top = 12, bottom = 11 },
}
local CLASSIC_BACKDROP = {
  bgFile = "Interface\\FrameGeneral\\UI-Background-Rock",
  edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
  tile = true, tileSize = 256, edgeSize = 32,
  insets = { left = 11, right = 12, top = 12, bottom = 11 },
}
local FLAT_BACKDROP = {
  bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1,
}
ER.DEFAULT_BACKDROP = DEFAULT_BACKDROP

local function NineSlice(frame)
  if frame.erNineSlice ~= nil then return frame.erNineSlice or nil end
  local ok, ns = pcall(function()
    local f = CreateFrame("Frame", nil, frame, "NineSlicePanelTemplate")
    f:SetAllPoints()
    f:SetFrameLevel(frame:GetFrameLevel())
    NineSliceUtil.ApplyLayoutByName(f, "ButtonFrameTemplateNoPortrait")
    local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    bg:SetPoint("TOPLEFT", 6, -22)
    bg:SetPoint("BOTTOMRIGHT", -4, 4)
    bg:SetTexture("Interface\\FrameGeneral\\UI-Background-Rock", "REPEAT", "REPEAT")
    bg:SetHorizTile(true)
    bg:SetVertTile(true)
    local shade = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
    shade:SetAllPoints(bg)
    shade:SetColorTexture(0, 0, 0, 0.55)
    f.erBg, f.erShade = bg, shade
    return f
  end)
  frame.erNineSlice = ok and ns or false
  return ok and ns or nil
end

local function RetailPieces(ns, retail)
  if not (EllesmereUI and EllesmereUI.StockAtlas) then return end
  for _, region in ipairs({ ns:GetRegions() }) do
    if region.GetAtlas then
      local atlas = region.erAtlas or region:GetAtlas()
      if atlas then
        region.erAtlas = atlas
        if retail then pcall(EllesmereUI.StockAtlas, region, atlas, false)
        else region:SetTexCoord(0, 1, 0, 1); region:SetAtlas(atlas, false) end
      end
    end
  end
end

local function ApplyShell(frame, theme)
  local art = theme == "forever" or theme == "blizzard"
  local ns = art and NineSlice(frame) or frame.erNineSlice
  if ns then
    ns:SetShown(art)
    ns.erBg:SetShown(art)
    ns.erShade:SetShown(art)
    if art then RetailPieces(ns, theme == "blizzard") end
  end
  frame.erTopBar = frame.erTopBar or frame:CreateTexture(nil, "BACKGROUND", nil, 1)
  frame.erTopBar:Hide()

  if art then
    frame:SetBackdrop(ns and nil or DEFAULT_BACKDROP)
  elseif theme == "classic" then
    frame:SetBackdrop(CLASSIC_BACKDROP)
  elseif theme == "eui" then
    frame:SetBackdrop(FLAT_BACKDROP)
    local bg = EllesmereUI.DARK_BG or { r = 0.069, g = 0.058, b = 0.047 }
    local bc = EllesmereUI.BORDER_COLOR or { r = 1, g = 1, b = 1, a = 0.05 }
    frame:SetBackdropColor(bg.r, bg.g, bg.b, 0.97)
    frame:SetBackdropBorderColor(bc.r, bc.g, bc.b, math.max(bc.a or 0.05, 0.12))
    frame.erTopBar:ClearAllPoints()
    frame.erTopBar:SetPoint("TOPLEFT", 1, -1)
    frame.erTopBar:SetPoint("TOPRIGHT", -1, -1)
    frame.erTopBar:SetHeight(40)
    frame.erTopBar:SetColorTexture(0, 0, 0, 0.3)
    frame.erTopBar:Show()
  else
    frame:SetBackdrop(DEFAULT_BACKDROP)
  end
end

---------------------------------------------------------------------------
-- Buttons: flat with an accent underline in EllesmereUI Style, template art otherwise
---------------------------------------------------------------------------
local buttons = setmetatable({}, { __mode = "k" })

local function TemplatePieces(btn)
  local out = {}
  for _, key in ipairs({ "Left", "Middle", "Right" }) do
    if btn[key] then out[#out + 1] = btn[key] end
  end
  for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture" }) do
    local t = btn[getter] and btn[getter](btn)
    if t then out[#out + 1] = t end
  end
  return out
end

local function ApplyButton(btn, theme)
  local flat = theme == "eui"
  for _, t in ipairs(TemplatePieces(btn)) do t:SetAlpha(flat and 0 or 1) end
  if flat and not btn.erFlat then
    local f = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    f:SetAllPoints()
    f:SetFrameLevel(math.max(0, btn:GetFrameLevel() - 1))
    f:SetBackdrop(FLAT_BACKDROP)
    local line = f:CreateTexture(nil, "OVERLAY")
    line:SetPoint("BOTTOMLEFT", 1, 1)
    line:SetPoint("BOTTOMRIGHT", -1, 1)
    line:SetHeight(2)
    f.erLine = line
    btn.erFlat = f
  end
  if btn.erFlat then
    btn.erFlat:SetShown(flat)
    if flat then
      local r, g, b = ER.AccentColor()
      btn.erFlat:SetBackdropColor(0.09, 0.09, 0.09, 0.95)
      btn.erFlat:SetBackdropBorderColor(1, 1, 1, 0.1)
      btn.erFlat.erLine:SetColorTexture(r, g, b, 1)
    end
  end
end

function ER.ThemeRegisterButton(b)
  buttons[b] = true
  pcall(ApplyButton, b, ER.ActiveTheme())
end

---------------------------------------------------------------------------
-- Fonts: EllesmereUI's global font (face, outline, shadow) at each string's own size
---------------------------------------------------------------------------
local origFonts = setmetatable({}, { __mode = "k" })
local fontApplied = setmetatable({}, { __mode = "k" })

local function EachFontString(root, fn, depth)
  depth = depth or 0
  if depth > 8 or not root.GetRegions then return end
  for _, region in ipairs({ root:GetRegions() }) do
    if region.GetObjectType and region:GetObjectType() == "FontString" then fn(region) end
  end
  if root.GetChildren then
    for _, child in ipairs({ root:GetChildren() }) do EachFontString(child, fn, depth + 1) end
  end
end

local function EllesmereFont()
  if not ER.HasEllesmere() or type(EllesmereUI.GetFontPath) ~= "function" then return nil end
  local ok, path = pcall(EllesmereUI.GetFontPath)
  if not ok or type(path) ~= "string" or path == "" then return nil end
  local flags = ""
  if type(EllesmereUI.GetFontOutlineFlag) == "function" then
    local okf, flag = pcall(EllesmereUI.GetFontOutlineFlag)
    if okf and type(flag) == "string" then flags = flag end
  end
  local shadow = false
  if type(EllesmereUI.GetFontUseShadow) == "function" then
    local oks, use = pcall(EllesmereUI.GetFontUseShadow)
    shadow = oks and use and true or false
  end
  return path, flags, shadow
end

local function ApplyOneFont(obj, path, flags, shadow, key)
  if path and fontApplied[obj] == key then return end
  local font, size, curFlags = obj:GetFont()
  if not font or not size or size <= 0 then return end
  if path then
    if not origFonts[obj] then origFonts[obj] = { font, size, curFlags } end
    if EllesmereUI.PrimeFontShadow then pcall(EllesmereUI.PrimeFontShadow, obj, shadow) end
    if pcall(obj.SetFont, obj, path, origFonts[obj][2], flags or "") then
      fontApplied[obj] = key
    end
  elseif origFonts[obj] then
    local o = origFonts[obj]
    pcall(obj.SetFont, obj, o[1], o[2], o[3])
    origFonts[obj], fontApplied[obj] = nil, nil
  end
end

local function FontKey()
  local path, flags, shadow = EllesmereFont()
  return path, flags, shadow, path and (path .. "|" .. (flags or "") .. "|" .. tostring(shadow)) or nil
end

-- A widget made after the window was themed (rows, the gate).
function ER.NoteThemeFonts(obj)
  if not obj then return end
  local path, flags, shadow, key = FontKey()
  if obj.GetObjectType and obj:GetObjectType() == "FontString" then
    ApplyOneFont(obj, path, flags, shadow, key)
  else
    EachFontString(obj, function(fs) ApplyOneFont(fs, path, flags, shadow, key) end)
  end
end

---------------------------------------------------------------------------
-- Apply everything to a window
---------------------------------------------------------------------------
function ER.ApplyTheme(frame)
  if not frame then return end
  local theme = ER.ActiveTheme()
  local ok, err = pcall(function()
    ApplyShell(frame, theme)
    for btn in pairs(buttons) do ApplyButton(btn, theme) end
    if frame.erTitle then
      if theme == "eui" then frame.erTitle:SetTextColor(1, 1, 1) else frame.erTitle:SetTextColor(1, 0.82, 0) end
    end
    local path, flags, shadow, key = FontKey()
    EachFontString(frame, function(fs) ApplyOneFont(fs, path, flags, shadow, key) end)
  end)
  if not ok then
    pcall(ApplyShell, frame, "default")
    ER.Print("|cffff4040theme error, using the default look:|r " .. tostring(err))
  end
end

function ER.SetLook(key)
  ER.db.theme = key
  if EscortReadyFrame then ER.ApplyTheme(EscortReadyFrame) end
end
