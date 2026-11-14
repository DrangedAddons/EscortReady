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
    -- shows the check already running for this quest, or starts one (others keep running)
    local title = Plain(GetTitleText())
    ER.Begin(self.qid, type(title) == "string" and title ~= "" and title or nil)
  end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Party event quest", 1, 0.82, 0)
    GameTooltip:AddLine("Once this starts (an escort, a fight or another event), the NPC won't talk to anyone until it's over. "
      .. "Ready-check the group so everyone can hand in or pick up first.", 1, 1, 1, true)
    if self.why then GameTooltip:AddLine("Detected by: " .. self.why, 0.6, 0.6, 0.6, true) end
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
  local s = gate.qid and ER.sessions[gate.qid]
  if s then
    if s.mine then
      local ready, _, total = ER.Counts(s)
      if ER.AllReady(s) or s.startOnOpen then
        gate:SetText(GREEN .. "Starting...|r")
        gate.note:SetText(GREEN .. "Starting the quest.|r")
      else
        gate:SetText(("Waiting %d/%d"):format(ready, total))
        gate.note:SetText(GOLD .. "Waiting for the group to tick ready.|r")
      end
    else
      gate:SetText("Ready check")
      gate.note:SetText(GOLD .. s.leader .. " is starting this quest.|r")
    end
  else
    gate:SetText("Check party")
    gate.note:SetText(GOLD .. "Party event quest: ready-check your group first.|r")
  end
end

function ER.OnQuestDetail()
  local qid = Plain(GetQuestID())
  local char = ER.char
  if not (char and char.enabled and type(qid) == "number" and ER.HasCompany()) then ER.HideGate(); return end
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
-- Ready window: one panel per running check, side by side in a row centred on the screen,
-- oldest on the left. One check gets the full-size panel; with more, every panel narrows
-- (PANEL_W_MULTI, less if the screen is short of room) so the row fits instead of stacking.
-- The row is one invisible holder frame: drag any panel to move them all, Escape closes all.
---------------------------------------------------------------------------
local holder
local panels = {}
local lingering = {} -- checks whose quest started, counting down to close (ER.LingerWindow)
local ROW_H = 20
local PANEL_W, PANEL_W_MULTI, PANEL_W_MIN, GAP = 470, 330, 250, 8

local STATE_TEXT = {
  ready = GREEN .. "Ready|r",
  notready = RED .. "Not ready|r",
  seen = GOLD .. "Getting ready...|r",
  wait = GREY .. "...|r",
  noaddon = GREY .. "No addon|r",
}
local STATUS_TEXT = { have = "on the quest", done = "already completed", none = "" }
local STATUS_SHORT = { have = "on quest", done = "done", none = "" }

local function MakeButton(parent, text, w)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w or 110, 24)
  b:SetText(text)
  return b
end

local function Recentre(f)
  local cx, cy = f:GetCenter()
  local ux, uy = UIParent:GetCenter()
  if not (cx and ux) then return end
  local k = UIParent:GetEffectiveScale() / f:GetEffectiveScale()
  f:ClearAllPoints()
  f:SetPoint("CENTER", UIParent, "CENTER", cx - ux * k, cy - uy * k)
end

local function Displayed()
  local list = {}
  for _, s in ipairs(ER.order) do if not s.hidden then list[#list + 1] = s end end
  for _, s in ipairs(lingering) do if not s.hidden then list[#list + 1] = s end end
  table.sort(list, function(a, b) return a.seq < b.seq end)
  return list
end

local function BuildHolder()
  local f = CreateFrame("Frame", "EscortReadyFrame", UIParent)
  f:SetSize(PANEL_W, 200)
  f:SetPoint("CENTER", 0, 120)
  f:SetFrameStrata("DIALOG")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  tinsert(UISpecialFrames, "EscortReadyFrame")
  -- Escape (or anything else hiding it directly) closes every panel. A hidden UI (Alt+Z)
  -- also fires OnHide, but leaves IsShown() true: that one changes nothing.
  f:SetScript("OnHide", function(self)
    if self.laying or self:IsShown() then return end
    for _, s in ipairs(Displayed()) do s.hidden = true end
  end)
  f:Hide()
  return f
end

local function BuildPanel(i)
  local f = CreateFrame("Frame", "EscortReadyPanel" .. i, holder, "BackdropTemplate")
  f:SetSize(PANEL_W, 200)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function() holder:StartMoving() end)
  f:SetScript("OnDragStop", function() holder:StopMovingOrSizing(); Recentre(holder) end)
  f:SetBackdrop(ER.DEFAULT_BACKDROP) -- Theme.lua swaps it for the EllesmereUI look
  f.rows = {}

  -- X closes this panel only; the check keeps running (/er show brings it back)
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -6, -6)
  close:SetScript("OnClick", function() ER.HidePanel(f.s) end)

  f.header = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  f.header:SetPoint("TOP", 0, -18)
  f.header:SetText("Party event ready check")

  f.quest = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  f.quest:SetPoint("TOP", f.header, "BOTTOM", 0, -6)

  f.by = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.by:SetPoint("TOP", f.quest, "BOTTOM", 0, -4)

  f.help = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.help:SetPoint("TOP", f.by, "BOTTOM", 0, -8)
  f.help:SetText("Hand in your earlier parts and pick up this quest if you want it. "
    .. "Once it starts the NPC won't talk to anyone until it's over.")

  f.list = CreateFrame("Frame", nil, f)
  f.list:SetPoint("TOPLEFT", f.help, "BOTTOMLEFT", 0, -10)
  f.list:SetPoint("RIGHT", f, "RIGHT", -20, 0)
  f.list:SetHeight(ROW_H)

  -- starter: it starts by itself once everyone is ready; Start anyway asks first
  f.anyway = MakeButton(f, "Start anyway", 130)
  f.anyway:SetScript("OnClick", function() ER.StartAnyway(f.s) end)
  f.cancel = MakeButton(f, "Cancel", 130)
  f.cancel:SetScript("OnClick", function() ER.Cancel(f.s) end)
  f.anyway:SetPoint("BOTTOMLEFT", 20, 18)
  f.cancel:SetPoint("BOTTOMRIGHT", -20, 18)
  -- the game's ready check, offered while someone has no addon (leader/assistant only)
  f.rc = MakeButton(f, "Ready check", 130)
  f.rc:SetScript("OnClick", function() ER.StartReadyCheck(f.s) end)
  f.rc:SetMotionScriptsWhileDisabled(true)
  f.rc:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Ready check", 1, 0.82, 0)
    GameTooltip:AddLine("Starts the game's own ready check, so players without EscortReady can answer. "
      .. "Their Ready / Not ready goes on their line here.", 1, 1, 1, true)
    if not ER.CanReadyCheck() then
      GameTooltip:AddLine("Only the party leader can start one. Ask " .. (ER.LeaderName() or "the leader")
        .. " to type /readycheck; the answers count here too.", 1, 0.4, 0.4, true)
    end
    GameTooltip:Show()
  end)
  f.rc:SetScript("OnLeave", GameTooltip_Hide)

  -- everyone else
  f.ready = MakeButton(f, "Ready", 130)
  f.ready:SetScript("OnClick", function() ER.SetMyState(f.s, "ready") end)
  f.notready = MakeButton(f, "Not ready", 130)
  f.notready:SetScript("OnClick", function() ER.SetMyState(f.s, "notready") end)
  f.ready:SetPoint("BOTTOMLEFT", 20, 18)
  f.notready:SetPoint("BOTTOMRIGHT", -20, 18)

  f.foot = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")

  f.erTitle = f.header
  for _, b in ipairs({ f.anyway, f.cancel, f.rc, f.ready, f.notready }) do ER.ThemeRegisterButton(b) end
  ER.ApplyTheme(f)
  f:Hide()
  return f
end

local function Row(p, i)
  local r = p.rows[i]
  if r then return r end
  r = {}
  r.name = p.list:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  r.name:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
  r.name:SetHeight(ROW_H)
  r.name:SetJustifyH("LEFT")
  r.name:SetWordWrap(false) -- Forever names can be two words: one line, cut with ... if still too long
  r.state = p.list:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  r.state:SetPoint("LEFT", r.name, "RIGHT", 6, 0)
  r.state:SetJustifyH("LEFT")
  r.state:SetWordWrap(false)
  r.note = p.list:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  r.note:SetPoint("LEFT", r.state, "RIGHT", 4, 0)
  r.note:SetJustifyH("LEFT")
  r.note:SetWordWrap(false)
  ER.NoteThemeFonts(r.name); ER.NoteThemeFonts(r.state); ER.NoteThemeFonts(r.note)
  ER.ApplyTheme(p) -- fonts for the new row
  p.rows[i] = r
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

-- Fills panel p for check s at width w. Returns the panel's height.
local function UpdatePanel(p, s, w)
  local compact = w < PANEL_W
  local inner = w - 40
  p:SetWidth(w)
  p.quest:SetWidth(inner); p.help:SetWidth(inner)
  local closing = s.closingUntil ~= nil

  p.quest:SetText(s.title)
  p.by:SetText(s.mine and "You started this check." or (s.leader .. " wants to start it."))

  -- columns: name | state | note, narrower when the panels share the row
  local stateW = compact and 78 or 100
  local noteW = compact and 58 or 120
  local nameW = inner - stateW - noteW - 10
  local names = s.roster or ER.Roster(s)
  for i, n in ipairs(names) do
    local r = Row(p, i)
    local m = s.members[n] or { state = "wait" }
    r.name:SetWidth(nameW); r.state:SetWidth(stateW); r.note:SetWidth(noteW)
    r.name:SetText(ClassColor(n))
    r.state:SetText(STATE_TEXT[m.state] or m.state)
    local note = (compact and STATUS_SHORT or STATUS_TEXT)[m.status or ""] or ""
    if note == "" and m.rc then note = compact and "rcheck" or "ready check" end
    r.note:SetText(note)
    r.name:Show(); r.state:Show(); r.note:Show()
  end
  for i = #names + 1, #p.rows do
    p.rows[i].name:Hide(); p.rows[i].state:Hide(); p.rows[i].note:Hide()
  end
  p.list:SetHeight(math.max(1, #names) * ROW_H)

  -- buttons: two per row; Ready check sits between them, or above them when narrow
  local bw = math.min(130, math.floor((inner - 10) / 2))
  for _, b in ipairs({ p.anyway, p.cancel, p.ready, p.notready, p.rc }) do b:SetWidth(bw) end
  local ready, users, total = ER.Counts(s)
  local all = ER.AllReady(s)
  local rcShown = not closing and s.mine and not s.go and not s.startOnOpen and ER.HasNoAddon(s)
  p.rc:SetShown(rcShown)
  p.rc:SetEnabled(ER.CanReadyCheck())
  p.rc:ClearAllPoints()
  local extra = 0
  if compact and rcShown then
    p.rc:SetPoint("BOTTOM", 0, 48)
    extra = 30
  else
    p.rc:SetPoint("BOTTOM", 0, 18)
  end
  p.foot:ClearAllPoints()
  p.foot:SetPoint("BOTTOM", 0, 46 + extra)
  p.foot:SetWidth(inner)

  if closing then
    -- nothing left to click: just the result and the countdown
    p.ready:Hide(); p.notready:Hide(); p.anyway:Hide(); p.cancel:Hide()
    local left = math.max(1, math.ceil(s.closingUntil - GetTime()))
    p.foot:SetText(GREEN .. "Everyone is ready. " .. (s.mine and "The quest has started."
      or (s.leader .. " started the quest.")) .. "|r\n" .. ("This closes in %d..."):format(left))
  elseif s.mine then
    p.ready:Hide(); p.notready:Hide()
    p.anyway:Show(); p.cancel:Show()
    p.anyway:SetEnabled(not (all or s.go or s.startOnOpen))
    if s.go then
      p.foot:SetText(GREEN .. "Quest started.|r")
    elseif all or s.startOnOpen then
      p.foot:SetText(GREEN .. "Ready. Talk to the quest giver again and it starts.|r")
    elseif ER.HasNoAddon(s) then
      p.foot:SetText(("%d/%d ready. %d without the addon: "):format(ready, total, total - users)
        .. (ER.CanReadyCheck() and "use Ready check so they can answer."
          or ("ask " .. (ER.LeaderName() or "the leader") .. " to type /readycheck.")))
    else
      p.foot:SetText(("%d/%d ready."):format(ready, total))
    end
  else
    p.cancel:Hide(); p.anyway:Hide()
    p.ready:Show(); p.notready:Show()
    local mine = s.members[ER.Me()]
    local st = mine and mine.state
    p.ready:SetEnabled(st ~= "ready")
    p.notready:SetEnabled(st ~= "notready")
    if s.go then
      p.foot:SetText(GREEN .. s.leader .. " started the quest.|r")
    elseif st == "ready" and mine.status == "done" then
      p.foot:SetText("You've already completed this, so you're marked ready. Click Not ready if you still need the NPC.")
    elseif st == "ready" then
      p.foot:SetText(ER.char.autoJoin and "You'll join the quest when it starts." or "Ready. Accept the join prompt when it starts.")
    else
      p.foot:SetText(("%d/%d ready."):format(ready, total))
    end
  end

  -- header block (title, quest, by-line, help) + rows + footer and buttons
  local head = 18 + 22 + 6 + (p.quest:GetStringHeight() or 16) + 4 + 14 + 8 + (p.help:GetStringHeight() or 26) + 10
  local foot = math.max(0, (p.foot:GetStringHeight() or 14) - 28) -- a footer of 3+ lines
  local h = head + math.max(1, #names) * ROW_H + 84 + extra + foot
  p:SetHeight(h)
  return h
end

-- Puts every displayed check on screen, left to right in start order, and sizes the row.
local function Layout()
  if not holder then return end
  local list = Displayed()
  for i = #list + 1, #panels do panels[i]:Hide(); panels[i].s = nil end
  if #list == 0 then
    holder.laying = true
    holder:Hide()
    holder.laying = nil
    return
  end
  local n = #list
  local w = n == 1 and PANEL_W or PANEL_W_MULTI
  -- room on screen, in the holder's own (scaled) units
  local room = (UIParent:GetWidth() * UIParent:GetEffectiveScale() / holder:GetEffectiveScale()) - 40
  if type(room) == "number" and room > 0 then
    w = math.max(PANEL_W_MIN, math.min(w, math.floor((room - GAP * (n - 1)) / n)))
  end
  local tallest = 0
  for i, s in ipairs(list) do
    local p = panels[i]
    if not p then p = BuildPanel(i); panels[i] = p end
    p.s = s
    p:ClearAllPoints()
    p:SetPoint("TOPLEFT", holder, "TOPLEFT", (i - 1) * (w + GAP), 0)
    local h = UpdatePanel(p, s, w)
    if type(h) == "number" and h > tallest then tallest = h end
    p:Show()
  end
  holder:SetSize(n * w + (n - 1) * GAP, math.max(tallest, 1))
  holder:Show()
end

function ER.ApplyScale()
  if holder then holder:SetScale(ER.char.scale or 1) end
end

-- Theme change: every panel built so far.
function ER.RethemeWindows()
  for _, p in ipairs(panels) do ER.ApplyTheme(p) end
end

-- s: put that check's panel on screen. No s: every running check's panel (/er show).
function ER.ShowWindow(s)
  holder = holder or BuildHolder()
  ER.ApplyScale()
  if s then
    s.hidden = false
  else
    for _, x in ipairs(ER.order) do x.hidden = false end
  end
  ER.RethemeWindows()
  Layout()
end

local function Drop(list, s)
  for i = #list, 1, -1 do if list[i] == s then table.remove(list, i) end end
end

-- Takes one check's panel off screen; the rest close up around the centre.
function ER.HidePanel(s)
  if not s then return end
  s.hidden = true
  Drop(lingering, s)
  Layout()
end

-- The quest has started (the check is already over): its panel stays up ER.COUNTDOWN seconds
-- showing the final roster and "closes in 3... 2... 1", then closes. Closing it early (X or
-- Escape) is fine. A new check for the same quest gets a panel of its own.
function ER.LingerWindow(s)
  s.go = true
  s.closingUntil = GetTime() + ER.COUNTDOWN
  Drop(lingering, s)
  lingering[#lingering + 1] = s
  ER.ShowWindow(s)
  C_Timer.NewTicker(0.2, function(t)
    local still = false
    for _, x in ipairs(lingering) do if x == s then still = true end end
    if not still then t:Cancel(); return end
    if GetTime() >= s.closingUntil then
      t:Cancel()
      Drop(lingering, s)
      Layout()
    else
      Layout()
    end
  end)
end

function ER.Refresh()
  ER.CheckAuto()
  UpdateGate()
  Layout()
end

---------------------------------------------------------------------------
-- Export box: the found quests as text, selected, ready for Ctrl+C
---------------------------------------------------------------------------
local exportWin

local function BuildExport()
  local f = CreateFrame("Frame", "EscortReadyExport", UIParent, "BackdropTemplate")
  f:SetSize(520, 340)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetBackdrop(ER.DEFAULT_BACKDROP)
  tinsert(UISpecialFrames, "EscortReadyExport")

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -6, -6)

  f.header = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  f.header:SetPoint("TOP", 0, -18)
  f.header:SetText("Found party event quests")
  f.erTitle = f.header

  f.help = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.help:SetPoint("TOP", f.header, "BOTTOM", 0, -6)
  f.help:SetWidth(470)
  f.help:SetText("Ctrl+C to copy, then paste it in Discord or a GitHub issue so these go in the built-in list. "
    .. "Quests already in the list are left out.")

  local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 22, -64)
  scroll:SetPoint("BOTTOMRIGHT", -40, 50)
  local bg = scroll:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", -4, 4)
  bg:SetPoint("BOTTOMRIGHT", 24, -4)
  bg:SetColorTexture(0, 0, 0, 0.4)

  local edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  edit:SetAutoFocus(false)
  edit:SetFontObject("ChatFontNormal")
  edit:SetWidth(440)
  edit:SetScript("OnEscapePressed", function() f:Hide() end)
  -- read-only: typing puts the export back
  edit:SetScript("OnTextChanged", function(self, user)
    if user and f.text then self:SetText(f.text); self:HighlightText() end
  end)
  edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
  scroll:SetScrollChild(edit)
  f.edit = edit

  local done = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  done:SetSize(120, 24)
  done:SetPoint("BOTTOM", 0, 18)
  done:SetText("Close")
  done:SetScript("OnClick", function() f:Hide() end)
  ER.ThemeRegisterButton(done)

  f:Hide()
  return f
end

function ER.ShowExport()
  exportWin = exportWin or BuildExport()
  local text, count = ER.ExportText()
  if count == 0 then
    text = text .. "\n(nothing yet: no quests found beyond the built-in list)"
  end
  exportWin.text = text
  exportWin:SetScale(ER.char.scale or 1)
  ER.ApplyTheme(exportWin)
  exportWin:Show()
  exportWin.edit:SetText(text)
  exportWin.edit:SetFocus()
  exportWin.edit:HighlightText()
end
