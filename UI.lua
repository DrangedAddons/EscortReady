-- The gate over the quest frame's Accept button, and the ready window.
local _, ER = ...

local function Plain(v)
  if v == nil then return nil end
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end

local GREEN, RED, GOLD, GREY = "|cff40ff40", "|cffff4040", "|cffffd100", "|cff909090"

---------------------------------------------------------------------------
-- Gate: our button sits on top of Accept while an escort page is open in a group
---------------------------------------------------------------------------
local gate

local function AcceptNormally()
  ER.bypass = true
  AcceptQuest()
  ER.bypass = nil
end

local function BuildGate()
  local accept = QuestFrameAcceptButton
  if not accept then return nil end
  local b = CreateFrame("Button", "EscortReadyGate", accept:GetParent(), "UIPanelButtonTemplate")
  b:SetAllPoints(accept)
  b:SetFrameLevel(accept:GetFrameLevel() + 10)
  b:RegisterForClicks("LeftButtonUp")

  local note = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  note:SetPoint("BOTTOMLEFT", b, "TOPLEFT", 0, 4)
  note:SetJustifyH("LEFT")
  b.note = note

  b:SetScript("OnClick", function(self)
    if IsShiftKeyDown() then AcceptNormally(); return end
    local qid, s = self.qid, ER.session
    if s and s.qid == qid then
      ER.ShowWindow()
    else
      if s and s.mine then ER.Cancel() end
      local title = Plain(GetTitleText())
      ER.Begin(qid, type(title) == "string" and title ~= "" and title or nil)
    end
  end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Escort quest", 1, 0.82, 0)
    GameTooltip:AddLine("Once the escort starts, the NPC won't talk to anyone until it's over. "
      .. "Ready-check the group so everyone can hand in or pick up first.", 1, 1, 1, true)
    if self.why then GameTooltip:AddLine("Detected by: " .. self.why, 0.6, 0.6, 0.6, true) end
    GameTooltip:AddLine("Shift-click to accept without a check.", 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  ER.ThemeRegisterButton(b)
  ER.NoteThemeFonts(b)
  b:Hide()
  return b
end

local function UpdateGate()
  if not (gate and gate:IsShown()) then return end
  local s = ER.session
  if s and s.qid == gate.qid then
    if s.mine then
      local ready, _, total = ER.Counts()
      if ER.AllReady() or s.startOnOpen then
        gate:SetText(GREEN .. "Starting...|r")
        gate.note:SetText(GREEN .. "Starting the escort.|r")
      else
        gate:SetText(("Waiting %d/%d"):format(ready, total))
        gate.note:SetText(GOLD .. "Waiting for the group to tick ready.|r")
      end
    else
      gate:SetText("Ready check")
      gate.note:SetText(GOLD .. s.leader .. " is starting this escort.|r")
    end
  else
    gate:SetText("Check party")
    gate.note:SetText(GOLD .. "Escort quest: ready-check your group first.|r")
  end
end

function ER.OnQuestDetail()
  local qid = Plain(GetQuestID())
  local char = ER.char
  if not (char and char.enabled and type(qid) == "number" and ER.Channel()) then ER.HideGate(); return end
  local yes, why = ER.IsEscort(qid)
  if not yes then ER.HideGate(); return end
  gate = gate or BuildGate()
  if not gate then return end
  ER.detailQid = qid
  gate.qid, gate.why = qid, why
  gate:Show()
  ER.Refresh() -- starts at once if the group got ready while the page was closed
end

function ER.HideGate()
  ER.detailQid = nil
  if gate then gate:Hide(); gate.qid = nil end
end

---------------------------------------------------------------------------
-- Ready window
---------------------------------------------------------------------------
local win
local rows = {}
local ROW_H = 20

local STATE_TEXT = {
  ready = GREEN .. "Ready|r",
  notready = RED .. "Not ready|r",
  seen = GOLD .. "Getting ready...|r",
  wait = GREY .. "...|r",
  noaddon = GREY .. "No addon|r",
}
local STATUS_TEXT = { have = "on the quest", done = "done it before", none = "" }

local function MakeButton(parent, text, w)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w or 110, 24)
  b:SetText(text)
  return b
end

local function BuildWindow()
  local f = CreateFrame("Frame", "EscortReadyFrame", UIParent, "BackdropTemplate")
  f:SetSize(440, 200)
  f:SetPoint("CENTER", 0, 120)
  f:SetFrameStrata("DIALOG")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetBackdrop(ER.DEFAULT_BACKDROP) -- Theme.lua swaps it for the EllesmereUI look
  tinsert(UISpecialFrames, "EscortReadyFrame")

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -6, -6)

  f.header = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  f.header:SetPoint("TOP", 0, -18)
  f.header:SetText("Escort ready check")

  f.quest = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  f.quest:SetPoint("TOP", f.header, "BOTTOM", 0, -6)
  f.quest:SetWidth(400)

  f.by = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.by:SetPoint("TOP", f.quest, "BOTTOM", 0, -4)

  f.help = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.help:SetPoint("TOP", f.by, "BOTTOM", 0, -8)
  f.help:SetWidth(400)
  f.help:SetText("Hand in your earlier parts and pick up this quest if you want it. "
    .. "Once the escort starts the NPC won't talk to anyone.")

  f.list = CreateFrame("Frame", nil, f)
  f.list:SetPoint("TOPLEFT", f.help, "BOTTOMLEFT", 0, -10)
  f.list:SetPoint("RIGHT", f, "RIGHT", -20, 0)
  f.list:SetHeight(ROW_H)

  -- starter: it starts by itself once everyone is ready; Start anyway asks first
  f.anyway = MakeButton(f, "Start anyway", 130)
  f.anyway:SetScript("OnClick", function() ER.StartAnyway() end)
  f.cancel = MakeButton(f, "Cancel", 130)
  f.cancel:SetScript("OnClick", function() ER.Cancel() end)
  f.anyway:SetPoint("BOTTOMLEFT", 20, 18)
  f.cancel:SetPoint("BOTTOMRIGHT", -20, 18)

  -- everyone else
  f.ready = MakeButton(f, "Ready", 130)
  f.ready:SetScript("OnClick", function() ER.SetMyState("ready") end)
  f.notready = MakeButton(f, "Not ready", 130)
  f.notready:SetScript("OnClick", function() ER.SetMyState("notready") end)
  f.ready:SetPoint("BOTTOMLEFT", 20, 18)
  f.notready:SetPoint("BOTTOMRIGHT", -20, 18)

  f.foot = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.foot:SetPoint("BOTTOM", 0, 46)
  f.foot:SetWidth(400)

  f.erTitle = f.header
  for _, b in ipairs({ f.anyway, f.cancel, f.ready, f.notready }) do ER.ThemeRegisterButton(b) end

  f:Hide()
  return f
end

local function Row(i)
  local r = rows[i]
  if r then return r end
  r = {}
  r.name = win.list:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  r.name:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
  r.name:SetSize(190, ROW_H) -- Forever names can be two words: one line, cut with ... if still too long
  r.name:SetJustifyH("LEFT")
  r.name:SetWordWrap(false)
  r.state = win.list:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  r.state:SetPoint("LEFT", r.name, "RIGHT", 6, 0)
  r.state:SetWidth(100)
  r.state:SetJustifyH("LEFT")
  r.note = win.list:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  r.note:SetPoint("LEFT", r.state, "RIGHT", 4, 0)
  r.note:SetJustifyH("LEFT")
  ER.NoteThemeFonts(r.name); ER.NoteThemeFonts(r.state); ER.NoteThemeFonts(r.note)
  rows[i] = r
  return r
end

local function ClassColor(name)
  local unit
  if name == ER.Me() then unit = "player" end
  if not unit then
    local n = IsInRaid() and GetNumGroupMembers() or GetNumSubgroupMembers()
    local pre = IsInRaid() and "raid" or "party"
    for i = 1, n do
      local u = pre .. i
      local un = Plain(GetUnitName(u, true))
      if un and Ambiguate(un, "none") == name then unit = u; break end
    end
  end
  local _, class = unit and UnitClass(unit)
  local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  return c and c:WrapTextInColorCode(name) or name
end

local function UpdateWindow()
  if not (win and win:IsShown()) then return end
  local s = ER.session
  if not s then win:Hide(); return end

  win.quest:SetText(s.title)
  win.by:SetText(s.mine and "You started this check." or (s.leader .. " wants to start it."))

  local names = ER.Roster()
  for i, n in ipairs(names) do
    local r = Row(i)
    local m = s.members[n] or { state = "wait" }
    r.name:SetText(ClassColor(n))
    r.state:SetText(STATE_TEXT[m.state] or m.state)
    r.note:SetText(STATUS_TEXT[m.status or ""] or "")
    r.name:Show(); r.state:Show(); r.note:Show()
  end
  for i = #names + 1, #rows do
    rows[i].name:Hide(); rows[i].state:Hide(); rows[i].note:Hide()
  end
  win.list:SetHeight(math.max(1, #names) * ROW_H)

  local ready, users, total = ER.Counts()
  local all = ER.AllReady()
  if s.mine then
    win.ready:Hide(); win.notready:Hide()
    win.anyway:Show(); win.cancel:Show()
    win.anyway:SetEnabled(not (all or s.go or s.startOnOpen))
    if s.go then
      win.foot:SetText(GREEN .. "Escort started.|r")
    elseif all or s.startOnOpen then
      win.foot:SetText(GREEN .. "Ready. Talk to the quest giver again and it starts.|r")
    elseif users < total then
      win.foot:SetText(("%d/%d ready. %d without the addon can't tick ready."):format(ready, total, total - users))
    else
      win.foot:SetText(("%d/%d ready."):format(ready, total))
    end
  else
    win.cancel:Hide(); win.anyway:Hide()
    win.ready:Show(); win.notready:Show()
    local mine = s.members[ER.Me()]
    local st = mine and mine.state
    win.ready:SetEnabled(st ~= "ready")
    win.notready:SetEnabled(st ~= "notready")
    if s.go then
      win.foot:SetText(GREEN .. s.leader .. " started the escort.|r")
    elseif st == "ready" then
      win.foot:SetText(ER.char.autoJoin and "You'll join the escort when it starts." or "Ready. Accept the join prompt when it starts.")
    else
      win.foot:SetText(("%d/%d ready."):format(ready, total))
    end
  end

  -- header block (title, quest, by-line, help) + rows + footer and buttons
  local head = 18 + 22 + 6 + (win.quest:GetStringHeight() or 16) + 4 + 14 + 8 + (win.help:GetStringHeight() or 26) + 10
  win:SetHeight(head + math.max(1, #names) * ROW_H + 84)
end

function ER.ApplyScale()
  if win then win:SetScale(ER.char.scale or 1) end
end

function ER.ShowWindow()
  win = win or BuildWindow()
  ER.ApplyScale()
  ER.ApplyTheme(win)
  win:Show()
  UpdateWindow()
end

function ER.HideWindow()
  if win then win:Hide() end
end

function ER.Refresh()
  ER.CheckAuto()
  UpdateGate()
  UpdateWindow()
end
