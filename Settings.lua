-- Options panel (Esc > Options > AddOns > EscortReady). All settings are per character.
local _, ER = ...

local category

local function Check(parent, anchor, label, tip, key)
  local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  c:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -8)
  local text = c.Text or c.text
  if text then text:SetText(label); text:SetFontObject("GameFontHighlight") end
  c:SetScript("OnShow", function(self) self:SetChecked(ER.char[key]) end)
  c:SetScript("OnClick", function(self) ER.char[key] = self:GetChecked() and true or false end)
  c:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(label, 1, 0.82, 0)
    GameTooltip:AddLine(tip, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  c:SetScript("OnLeave", GameTooltip_Hide)
  return c
end

local function Button(parent, text, w)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w or 180, 24)
  b:SetText(text)
  return b
end

-- A dropdown box: shows the current choice, click opens a list under it, a pick closes it.
-- Same look as CraftRoute's CR.CreateDropdown. options: { {value, text}, ... } or a function
-- returning that (rebuilt on every open).
local FLAT = { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 }

function ER.CreateDropdown(parent, width, options, getter, setter)
  local dd = CreateFrame("Button", nil, parent, "BackdropTemplate")
  dd:SetSize(width, 22)
  dd:SetBackdrop(FLAT)
  dd:SetBackdropColor(0.08, 0.08, 0.08, 0.9)
  dd:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.9)
  dd.text = dd:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  dd.text:SetPoint("LEFT", 6, 0)
  dd.text:SetPoint("RIGHT", -18, 0)
  dd.text:SetJustifyH("LEFT")
  dd.text:SetWordWrap(false)
  local arrow = dd:CreateTexture(nil, "OVERLAY")
  arrow:SetSize(14, 14)
  arrow:SetPoint("RIGHT", -3, 0)
  arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
  local hl = dd:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.08)

  local function Opts() return type(options) == "function" and options() or options end

  local menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  menu:SetFrameStrata("FULLSCREEN_DIALOG")
  menu:SetClampedToScreen(true)
  menu:SetBackdrop(FLAT)
  menu:SetBackdropColor(0.05, 0.05, 0.05, 0.97)
  menu:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.9)
  menu:Hide()
  menu.buttons = {}
  -- any click outside the list closes it
  menu:SetScript("OnShow", function(self) self:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
  menu:SetScript("OnHide", function(self) self:UnregisterEvent("GLOBAL_MOUSE_DOWN") end)
  menu:SetScript("OnEvent", function(self)
    if not self:IsMouseOver() and not dd:IsMouseOver() then self:Hide() end
  end)

  function dd:Sync()
    local cur = getter()
    for _, o in ipairs(Opts()) do
      if o.value == cur then self.text:SetText(o.text); return end
    end
    self.text:SetText(tostring(cur))
  end

  local ROW = 20
  local function Open()
    local opts = Opts()
    local cur = getter()
    for i, o in ipairs(opts) do
      local b = menu.buttons[i]
      if not b then
        b = CreateFrame("Button", nil, menu)
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.text:SetPoint("LEFT", 8, 0)
        local bhl = b:CreateTexture(nil, "HIGHLIGHT")
        bhl:SetAllPoints()
        bhl:SetColorTexture(0.2, 0.6, 1, 0.3)
        menu.buttons[i] = b
        ER.NoteThemeFonts(b)
      end
      b:SetHeight(ROW)
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", 2, -2 - (i - 1) * ROW)
      b:SetPoint("RIGHT", -2, 0)
      b.text:SetText((o.value == cur and "|cffffd100> |r" or "   ") .. o.text)
      b:SetScript("OnClick", function()
        menu:Hide()
        setter(o.value)
        dd:Sync()
      end)
      b:Show()
    end
    for i = #opts + 1, #menu.buttons do menu.buttons[i]:Hide() end
    menu:SetScale(dd:GetEffectiveScale() / UIParent:GetEffectiveScale())
    menu:SetWidth(dd:GetWidth())
    menu:SetHeight(#opts * ROW + 4)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 0, -2)
    menu:Show()
  end

  dd:SetScript("OnClick", function()
    if menu:IsShown() then menu:Hide() else Open() end
  end)
  dd:SetScript("OnHide", function() menu:Hide() end)
  dd:SetScript("OnEnter", function(self)
    if not self.tip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(self.tip, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  dd:SetScript("OnLeave", GameTooltip_Hide)
  ER.NoteThemeFonts(dd)
  dd:Sync()
  return dd
end

function ER.BuildSettings()
  local p = CreateFrame("Frame")
  p.name = "EscortReady"

  local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("EscortReady")

  local sub = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  sub:SetWidth(560)
  sub:SetJustifyH("LEFT")
  sub:SetText("In a group, a party event quest's Accept button (escorts, fights and other events that tie up the NPC) becomes a party ready check. "
    .. "These settings are for this character.")

  local c1 = Check(p, sub, "Ready-check party event quests in a group",
    "Covers the Accept button on party event quests while you're in a group. Shift-click it to accept without a check.", "enabled")
  local c2 = Check(p, c1, "Join the quest when I'm ready",
    "When the starter accepts, the game asks the group to join. Says yes for you if you ticked ready.", "autoJoin")
  local c3 = Check(p, c2, "Pick the NPC's start line after accepting",
    "Some of these quests need you to talk to the NPC again. If exactly one line looks like \"I'm ready\" or \"Let's go\", it's picked for you.", "autoGossip")

  local scale = CreateFrame("Slider", "EscortReadyScale", p, "OptionsSliderTemplate")
  scale:SetPoint("TOPLEFT", c3, "BOTTOMLEFT", 4, -28)
  scale:SetWidth(240)
  scale:SetMinMaxValues(0.5, 3)
  scale:SetValueStep(0.05)
  scale:SetObeyStepOnDrag(true)
  local low, high, label = _G.EscortReadyScaleLow, _G.EscortReadyScaleHigh, _G.EscortReadyScaleText
  if low then low:SetText("0.5") end
  if high then high:SetText("3") end
  local function SetLabel(v) if label then label:SetText(("Window size: %.2f"):format(v)) end end
  scale:SetScript("OnShow", function(self) self:SetValue(ER.char.scale); SetLabel(ER.char.scale) end)
  scale:SetScript("OnValueChanged", function(_, v)
    ER.char.scale = v
    SetLabel(v)
    ER.ApplyScale()
  end)

  -- window look dropdown (only with EllesmereUI loaded; without it there's one look)
  local lookRow = CreateFrame("Frame", nil, p)
  lookRow:SetPoint("TOPLEFT", scale, "BOTTOMLEFT", -4, -24)
  lookRow:SetSize(400, 22)
  local lookLabel = lookRow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  lookLabel:SetPoint("LEFT", 0, 0)
  lookLabel:SetText("Window look")
  local look = ER.CreateDropdown(lookRow, 240, ER.LookOptions,
    function() return ER.db.theme or "auto" end, ER.SetLook)
  look:SetPoint("LEFT", lookLabel, "RIGHT", 10, 0)
  look.tip = "Match EllesmereUI follows whatever look EllesmereUI uses. The text uses EllesmereUI's font either way."
  lookRow:SetScript("OnShow", function(self)
    self:SetShown(ER.HasEllesmere())
    look:Sync()
  end)

  local dev = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  dev:SetPoint("TOPLEFT", lookRow, "BOTTOMLEFT", 0, -20)
  dev:SetText("Testing")

  local devNote = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  devNote:SetPoint("TOPLEFT", dev, "BOTTOMLEFT", 0, -4)
  devNote:SetWidth(560)
  devNote:SetJustifyH("LEFT")
  devNote:SetText("No quest is ever accepted. As the starter in a group, a [Test] check goes to your group "
    .. "like a ready check: anyone with the addon gets the window and can tick ready. Solo, or as a "
    .. "party member, it opens locally with made-up members who tick ready over a few seconds.")

  local t1 = Button(p, "Test as the starter")
  t1:SetPoint("TOPLEFT", devNote, "BOTTOMLEFT", 0, -8)
  t1:SetScript("OnClick", function() ER.Test(true) end)
  local t2 = Button(p, "Test as a party member")
  t2:SetPoint("LEFT", t1, "RIGHT", 8, 0)
  t2:SetScript("OnClick", function() ER.Test(false) end)

  if Settings and Settings.RegisterCanvasLayoutCategory then
    category = Settings.RegisterCanvasLayoutCategory(p, "EscortReady")
    Settings.RegisterAddOnCategory(category)
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(p)
    category = p
  end
end

function ER.OpenSettings()
  if not category then return end
  if Settings and Settings.OpenToCategory and category.GetID then
    Settings.OpenToCategory(category:GetID())
  elseif InterfaceOptionsFrame_OpenToCategory then
    InterfaceOptionsFrame_OpenToCategory(category)
  end
end
