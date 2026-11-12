-- Session state, addon messages and events.
--
-- Flow: someone in a group opens an escort quest's detail page. UI.lua covers the Accept
-- button with a gate. Clicking it starts a session: a "Q" message goes to the group and
-- every copy of the addon opens the ready window. Each player ticks Ready ("R"). When all
-- players who run the addon are ready, the starter's gate turns into Start escort, which
-- calls AcceptQuest(). The others then get the server's "X is starting Y" prompt, which
-- is confirmed for them if they ticked ready ("G" tells them the escort is going).
local ADDON, ER = ...
_G.EscortReady = ER

ER.PREFIX = "EscortReady"
ER.TIMEOUT = 300   -- a session closes itself after 5 minutes
ER.NOADDON = 4     -- seconds without a reply before a member counts as "no addon"
ER.GOSSIP_WINDOW = 30

local function Print(fmt, ...)
  DEFAULT_CHAT_FRAME:AddMessage("|cffe0b040EscortReady|r: " .. (select("#", ...) > 0 and fmt:format(...) or fmt))
end
ER.Print = Print

local function Plain(v)
  if v == nil then return nil end
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end

local function Norm(name)
  name = Plain(name)
  if type(name) ~= "string" or name == "" then return nil end
  return Ambiguate(name, "none")
end

function ER.Me()
  return Norm(GetUnitName("player", true)) or Norm(UnitName("player"))
end

---------------------------------------------------------------------------
-- Group
---------------------------------------------------------------------------
function ER.Channel()
  if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
  if IsInRaid() then return "RAID" end
  if IsInGroup() then return "PARTY" end
  return nil
end

-- Names in group order, you first. A test session brings its own made-up roster.
function ER.Roster()
  if ER.session and ER.session.roster then return ER.session.roster end
  local list, seen = {}, {}
  local function add(n)
    n = Norm(n)
    if n and not seen[n] then seen[n] = true; list[#list + 1] = n end
  end
  add(ER.Me())
  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do
      local u = "raid" .. i
      if UnitExists(u) then add(GetUnitName(u, true)) end
    end
  else
    for i = 1, GetNumSubgroupMembers() do add(GetUnitName("party" .. i, true)) end
  end
  return list
end

function ER.Send(msg)
  if ER.session and ER.session.test and not ER.session.live then return end
  local ch = ER.Channel()
  if not ch then return end
  pcall(C_ChatInfo.SendAddonMessage, ER.PREFIX, msg, ch)
end

---------------------------------------------------------------------------
-- My status for a quest, shown next to my name for everyone
---------------------------------------------------------------------------
function ER.MyStatus(qid)
  local ok, done = pcall(C_QuestLog.IsQuestFlaggedCompleted, qid)
  if ok and done == true then return "done" end
  local ok2, idx = pcall(C_QuestLog.GetLogIndexForQuestID, qid)
  if ok2 and type(idx) == "number" and idx > 0 then return "have" end
  return "none"
end

---------------------------------------------------------------------------
-- Session
---------------------------------------------------------------------------
-- ER.session = { qid, title, leader, mine, t0, members = { [name] = { state, status, t } }, go }
-- state: "wait" (no reply yet), "noaddon", "seen", "ready", "notready"

local function NewSession(qid, title, leader)
  local s = { qid = qid, title = title, leader = leader, mine = leader == ER.Me(), t0 = GetTime(), members = {} }
  for _, n in ipairs(ER.Roster()) do s.members[n] = { state = "wait", t = GetTime() } end
  ER.session = s
  return s
end

local function Member(s, name)
  local m = s.members[name]
  if not m then m = { state = "wait", t = GetTime() }; s.members[name] = m end
  return m
end

function ER.SetMyState(state)
  local s = ER.session
  if not s then return end
  local m = Member(s, ER.Me())
  m.state = state
  m.status = ER.MyStatus(s.qid)
  ER.Send(("R^%d^%s^%s"):format(s.qid, state, m.status))
  ER.Refresh()
end

-- Count of ready / addon users / everyone, for the current roster only.
function ER.Counts()
  local s = ER.session
  if not s then return 0, 0, 0 end
  local ready, users, total = 0, 0, 0
  for _, n in ipairs(ER.Roster()) do
    local m = Member(s, n)
    total = total + 1
    if m.state ~= "wait" and m.state ~= "noaddon" then users = users + 1 end
    if m.state == "ready" then ready = ready + 1 end
  end
  return ready, users, total
end

function ER.AllReady()
  local ready, users, total = ER.Counts()
  return users > 0 and ready == users and ready == total
end

function ER.Begin(qid, title)
  if not ER.Channel() then return end
  local s = NewSession(qid, title or ER.QuestTitle(qid), ER.Me())
  Member(s, ER.Me()).state = "ready"
  Member(s, ER.Me()).status = ER.MyStatus(qid)
  ER.Send(("Q^%d^%s"):format(qid, s.title:gsub("%^", "")))
  ER.Send(("R^%d^ready^%s"):format(qid, Member(s, ER.Me()).status))
  ER.ShowWindow()
  ER.Refresh()
end

function ER.Cancel(silent)
  local s = ER.session
  if not s then return end
  if s.mine and not silent then ER.Send(("C^%d"):format(s.qid)) end
  ER.session = nil
  ER.HideWindow()
  ER.Refresh()
end

-- The starter, with the quest page open: accept it and tell the group.
function ER.StartEscort()
  local s = ER.session
  if not s or not s.mine then return end
  if s.test then
    s.go = true
    ER.Send(("G^%d"):format(s.qid))
    Print("Test: this is where the quest would be accepted.")
    ER.Cancel(true)
    return
  end
  -- ER.detailQid is set on QUEST_DETAIL, possibly before QuestFrame itself has shown
  local open = ER.detailQid == s.qid and Plain(GetQuestID()) == s.qid
  if not open then
    -- accepted the moment the quest page is open again (ER.OnQuestDetail -> ER.CheckAuto)
    s.startOnOpen = true
    if not s.toldReopen then
      s.toldReopen = true
      Print("Everyone's set. Talk to the quest giver again and the escort starts.")
    end
    ER.Refresh()
    return
  end
  s.go = true
  s.closed = true
  ER.HideWindow()
  ER.gossipUntil = GetTime() + ER.GOSSIP_WINDOW
  ER.Send(("G^%d"):format(s.qid))
  ER.bypass = true
  AcceptQuest()
  ER.bypass = nil
end

-- Starts on its own once everyone is ready (or after Start anyway, when the page reopens).
-- Called from ER.Refresh, which every state change goes through.
function ER.CheckAuto()
  local s = ER.session
  if not (s and s.mine) or s.go or s.starting then return end
  if ER.AllReady() or s.startOnOpen then
    s.starting = true
    ER.StartEscort()
    s.starting = nil
  end
end

-- Start without everyone ready, after a Yes on the warning.
StaticPopupDialogs.ESCORTREADY_START_ANYWAY = {
  text = "Not everyone is ready (%s).\n\nStart the escort anyway? The NPC won't talk to anyone until it's over.",
  button1 = YES,
  button2 = NO,
  OnAccept = function()
    local s = ER.session
    if s and s.mine and not s.go then
      s.startOnOpen = true
      s.closed = true -- the window stays shut from here; the gate and chat carry on
      ER.HideWindow()
      ER.StartEscort()
    end
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  showAlert = true,
  preferredIndex = 3,
}

function ER.StartAnyway()
  local s = ER.session
  if not (s and s.mine) or s.go then return end
  local ready, _, total = ER.Counts()
  StaticPopup_Show("ESCORTREADY_START_ANYWAY", ("%d/%d"):format(ready, total))
end

---------------------------------------------------------------------------
-- Test sessions. No quest is ever accepted.
-- As the starter in a group: a live check marked [Test] goes to the group like a real one,
-- party members with the addon get the window and their ticks come back.
-- Solo, or "as a party member": a local window with made-up members, nothing sent.
---------------------------------------------------------------------------
local TEST_QID = 309 -- Protecting the Shipment, only for its title

function ER.Test(asStarter)
  if ER.session and not ER.session.test then
    Print("A real escort check is running. Cancel it first.")
    return
  end
  if ER.session then ER.Cancel() end
  local me = ER.Me()

  if asStarter and ER.Channel() then
    local s = NewSession(TEST_QID, "[Test] " .. ER.QuestTitle(TEST_QID), me)
    s.test, s.live = true, true
    Member(s, me).state = "ready"
    Member(s, me).status = ER.MyStatus(TEST_QID)
    ER.Send(("Q^%d^%s^T"):format(s.qid, s.title:gsub("%^", "")))
    ER.Send(("R^%d^ready^%s"):format(s.qid, Member(s, me).status))
    ER.ShowWindow()
    ER.Refresh()
    return
  end

  local leader = asStarter and me or "Testleader"
  local roster = asStarter and { me, "Dummyone", "Dummytwo" } or { me, "Testleader", "Dummyone" }
  local s = { qid = TEST_QID, title = "[Test] " .. ER.QuestTitle(TEST_QID), leader = leader,
    mine = asStarter, t0 = GetTime(), members = {}, test = true, roster = roster }
  for _, n in ipairs(roster) do s.members[n] = { state = "wait", t = GetTime() } end
  s.members[leader].state = "ready"
  s.members[me].status = ER.MyStatus(TEST_QID)
  if not asStarter then s.members[me].state = "seen" end
  ER.session = s

  -- scripted replies: name, delay, state, status
  local script = asStarter and {
    { "Dummyone", 1, "seen", "none" }, { "Dummytwo", 1.5, "seen", "have" },
    { "Dummyone", 3, "ready", "none" }, { "Dummytwo", 4, "notready", "have" },
    { "Dummytwo", 8, "ready", "have" },
  } or {
    { "Dummyone", 1, "seen", "done" }, { "Dummyone", 3, "ready", "done" },
  }
  for _, step in ipairs(script) do
    C_Timer.After(step[2], function()
      if ER.session ~= s then return end
      s.members[step[1]].state, s.members[step[1]].status = step[3], step[4]
      ER.Refresh()
    end)
  end
  if not asStarter then
    pcall(PlaySound, SOUNDKIT and SOUNDKIT.READY_CHECK or 8960, "Master")
  end
  ER.ShowWindow()
  ER.Refresh()
end

---------------------------------------------------------------------------
-- Messages
---------------------------------------------------------------------------
local function OnMessage(msg, sender)
  sender = Norm(sender)
  if not sender or sender == ER.Me() then return end
  local kind, a, b, c = strsplit("^", msg, 4)
  local qid = tonumber(a)
  if not qid then return end
  local s = ER.session

  if s and s.test and not s.live then ER.Cancel(true); s = nil end -- a real message beats a local test
  if kind == "Q" then
    if s and s.qid == qid and s.leader ~= sender then return end -- someone else got there first
    if s and s.qid ~= qid and s.mine and not s.test then return end -- I'm running a different one
    if s and s.mine and s.test then ER.Cancel() end
    s = NewSession(qid, (b and b ~= "") and b or ER.QuestTitle(qid), sender)
    if c == "T" then s.test, s.live = true, true end
    Member(s, sender).state = "ready"
    local me = Member(s, ER.Me())
    me.state = "seen"
    me.status = ER.MyStatus(qid)
    ER.Send(("R^%d^seen^%s"):format(qid, me.status))
    ER.ShowWindow()
    pcall(PlaySound, SOUNDKIT and SOUNDKIT.READY_CHECK or 8960, "Master")
    if FlashClientIcon then pcall(FlashClientIcon) end
  elseif not s or s.qid ~= qid then
    return
  elseif kind == "R" then
    local m = Member(s, sender)
    m.state = (b == "ready" or b == "notready" or b == "seen") and b or "seen"
    m.status = c
    -- a late joiner who missed the Q: answer with mine so they see me
  elseif kind == "C" and sender == s.leader then
    Print("%s cancelled the escort check.", sender)
    ER.session = nil
    ER.HideWindow()
  elseif kind == "G" and sender == s.leader then
    s.go = true
    ER.goUntil = GetTime() + 30
    if s.test then
      Print("Test: %s pressed Start escort.", sender)
      C_Timer.After(3, function() if ER.session == s then ER.Cancel(true) end end)
    elseif Member(s, ER.Me()).state ~= "ready" then
      Print("%s started %s.", sender, s.title)
    end
  end
  ER.Refresh()
end

---------------------------------------------------------------------------
-- Escort follow-up: the server's join prompt, and a "let's go" gossip line
---------------------------------------------------------------------------
local GO_WORDS = { "ready", "let's go", "lets go", "begin", "start", "lead the way", "go ahead" }

local function OnAcceptConfirm()
  local s = ER.session
  if not (s and s.go and ER.char.autoJoin) then return end
  if not (ER.goUntil and GetTime() < ER.goUntil) then return end
  if Member(s, ER.Me()).state ~= "ready" then return end
  ConfirmAcceptQuest()
  StaticPopup_Hide("QUEST_ACCEPT")
  Print("Joined %s.", s.title)
end

local function OnGossip()
  if not (ER.gossipUntil and GetTime() < ER.gossipUntil and ER.char.autoGossip) then return end
  if not (C_GossipInfo and C_GossipInfo.GetOptions) then return end
  local ok, opts = pcall(C_GossipInfo.GetOptions)
  if not ok or type(opts) ~= "table" then return end
  local hit
  for _, o in ipairs(opts) do
    local name = Plain(o.name)
    if type(name) == "string" then
      local low = name:lower()
      for _, w in ipairs(GO_WORDS) do
        if low:find(w, 1, true) then
          if hit then return end -- more than one candidate: leave it to the player
          hit = o
          break
        end
      end
    end
  end
  if hit and hit.gossipOptionID then
    ER.gossipUntil = nil
    C_GossipInfo.SelectOption(hit.gossipOptionID)
  end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local f = CreateFrame("Frame")
ER.events = f
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("CHAT_MSG_ADDON")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("QUEST_DETAIL")
f:RegisterEvent("QUEST_FINISHED")
f:RegisterEvent("QUEST_ACCEPTED")
f:RegisterEvent("QUEST_ACCEPT_CONFIRM")
f:RegisterEvent("GOSSIP_SHOW")

f:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    if ... ~= ADDON then return end
    EscortReadyDB = EscortReadyDB or {}
    EscortReadyCharDB = EscortReadyCharDB or {}
    local db, char = EscortReadyDB, EscortReadyCharDB
    db.always = db.always or {}
    db.never = db.never or {}
    if char.enabled == nil then char.enabled = true end
    if char.autoJoin == nil then char.autoJoin = true end
    if char.autoGossip == nil then char.autoGossip = true end
    char.scale = char.scale or 1.25
    ER.db, ER.char = db, char
    pcall(C_ChatInfo.RegisterAddonMessagePrefix, ER.PREFIX)
    ER.BuildSettings()
  elseif event == "CHAT_MSG_ADDON" then
    local prefix, msg, _, sender = ...
    if Plain(prefix) == ER.PREFIX and Plain(msg) then OnMessage(msg, sender) end
  elseif event == "GROUP_ROSTER_UPDATE" then
    if ER.session and not ER.session.roster and not ER.Channel() then ER.Cancel(true) end
    ER.Refresh()
  elseif event == "QUEST_DETAIL" then
    ER.OnQuestDetail()
  elseif event == "QUEST_FINISHED" then
    ER.HideGate()
  elseif event == "QUEST_ACCEPTED" then
    local a, b = ...
    local qid = Plain(b) or Plain(a) -- (questID) on current clients, (logIndex, questID) on old ones
    local s = ER.session
    if s and qid == s.qid then
      if s.mine and not s.go then
        -- accepted some other way (a keybind, another addon): still tell the group
        s.go = true
        ER.Send(("G^%d"):format(s.qid))
      end
      C_Timer.After(3, function() if ER.session == s then ER.Cancel(true) end end)
    end
  elseif event == "QUEST_ACCEPT_CONFIRM" then
    OnAcceptConfirm()
  elseif event == "GOSSIP_SHOW" then
    OnGossip()
  end
end)

-- Ticks: no-reply members become "no addon", sessions time out.
C_Timer.NewTicker(1, function()
  local s = ER.session
  if not s then return end
  local now = GetTime()
  if now - s.t0 > ER.TIMEOUT then
    Print("Escort check for %s timed out.", s.title)
    ER.Cancel()
    return
  end
  local changed
  for _, m in pairs(s.members) do
    if m.state == "wait" and now - m.t > ER.NOADDON then m.state = "noaddon"; changed = true end
  end
  if changed then ER.Refresh() end
end)

---------------------------------------------------------------------------
-- Slash
---------------------------------------------------------------------------
local function OnOff(v) return v and "|cff40ff40on|r" or "|cffff4040off|r" end

SLASH_ESCORTREADY1 = "/escortready"
SLASH_ESCORTREADY2 = "/er"
SlashCmdList.ESCORTREADY = function(input)
  local cmd, arg = (input or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
  local char, db = ER.char, ER.db
  if cmd == "on" or cmd == "off" then
    char.enabled = cmd == "on"
    Print("Escort gate %s.", OnOff(char.enabled))
  elseif cmd == "join" then
    char.autoJoin = not char.autoJoin
    Print("Join the escort when you ticked ready: %s.", OnOff(char.autoJoin))
  elseif cmd == "gossip" then
    char.autoGossip = not char.autoGossip
    Print("Pick the escort's start line after accepting: %s.", OnOff(char.autoGossip))
  elseif cmd == "scale" and tonumber(arg) then
    char.scale = math.max(0.5, math.min(3, tonumber(arg)))
    ER.ApplyScale()
    Print("Window scale %.2f.", char.scale)
  elseif (cmd == "add" or cmd == "not" or cmd == "reset") and tonumber(arg) then
    local qid = tonumber(arg)
    db.always[qid] = cmd == "add" or nil
    db.never[qid] = cmd == "not" or nil
    local yes, why = ER.IsEscort(qid)
    Print("%s (%d): %s%s.", ER.QuestTitle(qid), qid, yes and "escort" or "not an escort", why and (" - " .. why) or "")
  elseif cmd == "check" and tonumber(arg) then
    local qid = tonumber(arg)
    local yes, why = ER.IsEscort(qid)
    Print("%s (%d): %s%s.", ER.QuestTitle(qid), qid, yes and "escort" or "not an escort", why and (" - " .. why) or "")
  elseif cmd == "test" then
    ER.Test(arg ~= "member")
  elseif cmd == "config" or cmd == "settings" then
    ER.OpenSettings()
  elseif cmd == "show" then
    if ER.session then ER.ShowWindow() else Print("No escort check running.") end
  elseif cmd == "cancel" then
    ER.Cancel()
  else
    Print("Gate %s, auto-join %s, auto start line %s, scale %.2f.", OnOff(char.enabled), OnOff(char.autoJoin), OnOff(char.autoGossip), char.scale)
    Print("/er on | off - the escort gate on the Accept button")
    Print("/er join - join the escort automatically once you ticked ready")
    Print("/er gossip - after starting, pick the NPC's \"I'm ready\" line if there's exactly one")
    Print("/er check <questID> | add <id> | not <id> | reset <id>")
    Print("/er show | cancel | scale <n> | config")
    Print("/er test - test check as the starter (sent to your group if you're in one)")
    Print("/er test member - local test as a party member, with dummies")
  end
end
