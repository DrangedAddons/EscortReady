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
ER.COUNTDOWN = 3   -- seconds the window stays up after the quest starts, counting down

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

-- Anyone else in the group who's online. Alone in a group (everyone else left or is
-- offline), nobody can be locked out by the quest giver, so there's nothing to check.
function ER.HasCompany()
  if not ER.Channel() then return false end
  local raid = IsInRaid()
  local n = raid and GetNumGroupMembers() or GetNumSubgroupMembers()
  for i = 1, n do
    local u = (raid and "raid" or "party") .. i
    if UnitExists(u) and not UnitIsUnit(u, "player") and UnitIsConnected(u) then return true end
  end
  return false
end

-- Names in group order, you first. A local test session brings its own made-up roster.
function ER.Roster(s)
  if s and s.roster then return s.roster end
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

-- s: the check this message is about. A local test never sends anything.
function ER.Send(msg, s)
  if s and s.test and not s.live then return end
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
-- Several checks can run at once, one per quest (two party event quests started at the same
-- time). ER.sessions[qid] = the running check for that quest; ER.order = running checks in the
-- order they started, which is also the window order, left to right.
-- s = { qid, title, leader, mine, t0, seq, members = { [name] = { state, status, t } }, go, hidden }
-- state: "wait" (no reply yet), "noaddon", "seen", "ready", "notready"
-- hidden: its panel isn't on screen (closed with X, or never shown: already completed).
ER.sessions, ER.order = {}, {}
local seq = 0

local function RemoveSession(s)
  if ER.sessions[s.qid] == s then ER.sessions[s.qid] = nil end
  for i = #ER.order, 1, -1 do
    if ER.order[i] == s then table.remove(ER.order, i) end
  end
end

local function AddSession(s)
  local old = ER.sessions[s.qid]
  if old then RemoveSession(old) end
  ER.sessions[s.qid] = s
  ER.order[#ER.order + 1] = s
end

-- A copy, safe to loop over while checks end.
function ER.Running()
  local out = {}
  for i, s in ipairs(ER.order) do out[i] = s end
  return out
end

-- Panels start hidden; ER.ShowWindow(s) puts one on screen.
local function NewSession(qid, title, leader, roster)
  seq = seq + 1
  local s = { qid = qid, title = title, leader = leader, mine = leader == ER.Me(), t0 = GetTime(),
    seq = seq, members = {}, roster = roster, hidden = true }
  for _, n in ipairs(ER.Roster(s)) do s.members[n] = { state = "wait", t = GetTime() } end
  AddSession(s)
  return s
end

local function Member(s, name)
  local m = s.members[name]
  if not m then m = { state = "wait", t = GetTime() }; s.members[name] = m end
  return m
end

function ER.SetMyState(s, state)
  if not s or ER.sessions[s.qid] ~= s then return end
  local m = Member(s, ER.Me())
  m.state = state
  m.status = ER.MyStatus(s.qid)
  ER.Send(("R^%d^%s^%s"):format(s.qid, state, m.status), s)
  ER.Refresh()
end

-- Count of ready / addon users / everyone, for the current roster only.
function ER.Counts(s)
  if not s then return 0, 0, 0 end
  local ready, users, total = 0, 0, 0
  for _, n in ipairs(ER.Roster(s)) do
    local m = Member(s, n)
    total = total + 1
    if m.state ~= "wait" and m.state ~= "noaddon" then users = users + 1 end
    if m.state == "ready" then ready = ready + 1 end
  end
  return ready, users, total
end

function ER.AllReady(s)
  local ready, users, total = ER.Counts(s)
  return users > 0 and ready == users and ready == total
end

---------------------------------------------------------------------------
-- The game's own ready check, for players without the addon. Only the party leader (or a
-- raid leader/assistant) may start one. Whoever starts it, every copy of EscortReady sees
-- each answer (READY_CHECK_CONFIRM) and puts it on that player's line, addon or not.
---------------------------------------------------------------------------
function ER.CanReadyCheck()
  if UnitIsGroupLeader and UnitIsGroupLeader("player") then return true end
  return IsInRaid() and UnitIsGroupAssistant and UnitIsGroupAssistant("player") or false
end

function ER.LeaderName()
  local n = IsInRaid() and GetNumGroupMembers() or GetNumSubgroupMembers()
  local pre = IsInRaid() and "raid" or "party"
  for i = 1, n do
    local u = pre .. i
    if UnitIsGroupLeader and UnitIsGroupLeader(u) then return Norm(GetUnitName(u, true)) end
  end
end

-- Anyone in the roster the addon can't hear from yet: a ready check is worth offering.
function ER.HasNoAddon(s)
  if not s then return false end
  for _, n in ipairs(ER.Roster(s)) do
    local m = s.members[n]
    if m and (m.state == "noaddon" or m.noaddon) then return true end
  end
  return false
end

-- One party chat line before the ready check, so players without the addon know what they're
-- answering. Once per check. Ready from them is taken as ready.
function ER.AnnounceReadyCheck(s)
  if not s or s.announced or not ER.HasNoAddon(s) then return end -- all on the addon: no chat
  local ch = ER.Channel()
  if not ch or not SendChatMessage then return end
  s.announced = true
  local text = ("[EscortReady] Ready check for %s: once it starts the quest giver is busy until it's over. "
    .. "Hand in or pick it up first, then hit Ready."):format(s.title)
  if #text > 255 then text = text:sub(1, 252) .. "..." end
  local ok, err = pcall(SendChatMessage, text, ch)
  if not ok then Print("Couldn't post the party message (%s).", tostring(err)) end
end

function ER.StartReadyCheck(s)
  if not ER.CanReadyCheck() then
    Print("Only the party leader can start a ready check. Ask %s to type /readycheck; the answers count here too.",
      ER.LeaderName() or "the leader")
    return
  end
  ER.rcSeen = nil
  ER.AnnounceReadyCheck(s)
  local ok, err = pcall(DoReadyCheck)
  if not ok then
    Print("The game didn't allow a ready check from the addon (%s). Type /readycheck; the answers count here too.", tostring(err))
    return
  end
  C_Timer.After(1.5, function()
    if not ER.rcSeen then Print("No ready check appeared. Type /readycheck; the answers count here too.") end
  end)
end

-- A game ready-check answer only counts for players without the addon: they have no other
-- way to answer. Addon users answer in each quest's panel. With several checks running, the
-- answer goes on that player's line in every one of them.
local function ByReadyCheck(m)
  return m and (m.noaddon or m.state == "noaddon" or m.state == "wait")
end

-- READY_CHECK_CONFIRM: unit answered.
function ER.OnReadyConfirm(unit, isReady)
  if type(unit) ~= "string" or #ER.order == 0 then return end
  local name = Norm(UnitIsUnit and UnitIsUnit(unit, "player") and ER.Me() or GetUnitName(unit, true))
  if not name then return end
  local changed
  for _, s in ipairs(ER.order) do
    local m = s.members[name]
    if ByReadyCheck(m) then
      m.state = isReady and "ready" or "notready"
      m.rc, m.noaddon = true, true
      changed = true
    end
  end
  if changed then ER.Refresh() end
end

-- Lower name wins when two players start a check on the same quest at the same moment.
-- Compared without the realm, lower-cased, so every copy in the group picks the same one.
local function Rank(name)
  return ((name:match("^[^-]+") or name)):lower()
end
ER.Rank = Rank

-- Starts a check for this quest, or shows the one already running for it (mine or someone
-- else's). Checks for other quests keep running alongside.
function ER.Begin(qid, title)
  if not ER.HasCompany() then return end
  local s = ER.sessions[qid]
  if s then ER.ShowWindow(s); ER.Refresh(); return end
  s = NewSession(qid, title or ER.QuestTitle(qid), ER.Me())
  Member(s, ER.Me()).state = "ready"
  Member(s, ER.Me()).status = ER.MyStatus(qid)
  ER.Send(("Q^%d^%s"):format(qid, s.title:gsub("%^", "")), s)
  ER.Send(("R^%d^ready^%s"):format(qid, Member(s, ER.Me()).status), s)
  ER.ShowWindow(s)
  ER.Refresh()
end

function ER.Cancel(s, silent)
  if not s then return end
  if s.mine and not silent then ER.Send(("C^%d"):format(s.qid), s) end
  RemoveSession(s)
  ER.HidePanel(s)
  ER.Refresh()
end

function ER.CancelAll(silent)
  for _, s in ipairs(ER.Running()) do ER.Cancel(s, silent) end
end

-- The starter, with the quest page open: accept it and tell the group.
function ER.StartEscort(s)
  if not s or not s.mine or ER.sessions[s.qid] ~= s then return end
  if s.test then
    s.go = true
    ER.Send(("G^%d"):format(s.qid), s)
    if s.live then ER.AnnounceStart(s) end -- live group test: same party line, title says [Test]
    Print("Test: this is where %s would be accepted.", s.title)
    ER.EndCheck(s, not s.closed)
    return
  end
  -- ER.detailQid is set on QUEST_DETAIL, possibly before QuestFrame itself has shown
  local open = ER.detailQid == s.qid and Plain(GetQuestID()) == s.qid
  if not open then
    -- accepted the moment the quest page is open again (ER.OnQuestDetail -> ER.CheckAuto)
    s.startOnOpen = true
    if not s.toldReopen then
      s.toldReopen = true
      Print("Everyone's set for %s. Talk to the quest giver again and the quest starts.", s.title)
    end
    return
  end
  s.go = true
  ER.gossipUntil = GetTime() + ER.GOSSIP_WINDOW
  ER.Send(("G^%d"):format(s.qid), s)
  ER.AnnounceStart(s)
  ER.RealAccept()
  ER.EndCheck(s, not s.closed) -- after Start anyway the panel is already shut: keep it shut
end

-- Players without the addon can't get the "started" message or the alert, so when anyone in
-- the group has no addon, the start goes in party chat too. Nothing when all have the addon.
function ER.AnnounceStart(s)
  if not s or ER.sessions[s.qid] ~= s or not ER.HasNoAddon(s) then return end
  local ch = ER.Channel()
  if not ch or not SendChatMessage then return end
  local text = s.anyway
    and ("[EscortReady] Started %s without waiting for everyone. The quest giver is busy until it's over."):format(s.title)
    or ("[EscortReady] Everyone's ready: %s has started."):format(s.title)
  if #text > 255 then text = text:sub(1, 252) .. "..." end
  local ok, err = pcall(SendChatMessage, text, ch)
  if not ok then Print("Couldn't post the party message (%s).", tostring(err)) end
end

-- The raid-warning banner in the middle of the screen, its sound, and a chat line.
function ER.AlertStartedAnyway(who, title)
  local text = ("%s started %s without waiting for you."):format(who, title)
  if RaidNotice_AddMessage and RaidWarningFrame then
    pcall(RaidNotice_AddMessage, RaidWarningFrame, text, ChatTypeInfo and ChatTypeInfo.RAID_WARNING or { r = 1, g = 0.3, b = 0.1 })
  end
  pcall(PlaySound, SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959, "Master")
  if FlashClientIcon then pcall(FlashClientIcon) end
  Print("|cffff4040%s|r", text)
end

-- A check is over the moment its quest starts. Nothing of it is kept, so if the quest fails
-- or someone goes again, the next accept gets a fresh ready check.
-- linger: the panel stays up ER.COUNTDOWN seconds saying the quest started, counting down
-- to closing (ER.LingerWindow in UI.lua). The check itself is gone either way.
function ER.EndCheck(s, linger)
  if not s or ER.sessions[s.qid] ~= s then return end
  RemoveSession(s)
  if linger then ER.LingerWindow(s) else ER.HidePanel(s) end
  ER.Refresh()
end

---------------------------------------------------------------------------
-- The block. Auto-quest addons (Questie, RestedXP, Leatrix Plus, EllesmereUI's quest
-- tracker, dialogue addons...) all call the global AcceptQuest() when a quest page opens.
-- Swapping the global catches every one of them that looks it up when it runs, which all
-- the installed ones do. AcceptQuest isn't a protected function, so this is allowed.
-- In a group, on an escort, nothing accepts until EscortReady says so (ER.RealAccept).
---------------------------------------------------------------------------
local origAccept = AcceptQuest

function ER.RealAccept()
  return origAccept()
end

local lastBlockMsg = {}

-- The escort quest a call to AcceptQuest() would accept right now, if it must be held.
local function HeldQuest()
  local char = ER.char
  if not (char and char.enabled) or not ER.HasCompany() then return nil end
  local qid = Plain(GetQuestID())
  if type(qid) ~= "number" or qid <= 0 or not ER.IsEscort(qid) then return nil end
  -- Always held, every time. EscortReady's own accept goes through ER.RealAccept, never here.
  return qid
end
ER.HeldQuest = HeldQuest

-- Called instead of a real accept. Starts the party check for an escort nobody is checking
-- yet, so an auto-accept addon gets the same flow as clicking Check party. If a check for it
-- is already running (mine or a party member's), that one is shown instead.
local function Held(qid)
  local now = GetTime()
  if not lastBlockMsg[qid] or now - lastBlockMsg[qid] > 10 then
    lastBlockMsg[qid] = now
    Print("Held back accepting %s (a party event quest) until the group is ready.", ER.QuestTitle(qid))
  end
  local title = Plain(GetTitleText())
  ER.Begin(qid, type(title) == "string" and title ~= "" and title or nil)
end

AcceptQuest = function(...)
  local qid = HeldQuest()
  if qid then Held(qid); return end
  return origAccept(...)
end

-- If the Accept button's click handler is the original function itself (bound in XML),
-- the global swap doesn't reach it, so the button gets the same check.
if QuestFrameAcceptButton and QuestFrameAcceptButton:GetScript("OnClick") == origAccept then
  QuestFrameAcceptButton:SetScript("OnClick", function() AcceptQuest() end)
end

-- Starts on its own once everyone is ready (or after Start anyway, when the page reopens).
-- Called from ER.Refresh, which every state change goes through.
function ER.CheckAuto()
  for _, s in ipairs(ER.Running()) do
    if s.mine and not s.go and not s.starting and (ER.AllReady(s) or s.startOnOpen) then
      s.starting = true
      ER.StartEscort(s)
      s.starting = nil
    end
  end
end

-- Start without everyone ready, after a Yes on the warning. The check rides along as data.
StaticPopupDialogs.ESCORTREADY_START_ANYWAY = {
  text = "Not everyone is ready for %s (%s).\n\nStart it anyway? The NPC won't talk to anyone until it's over.",
  button1 = YES,
  button2 = NO,
  OnAccept = function(self, data)
    local s = data or (self and self.data)
    if s and s.mine and not s.go and ER.sessions[s.qid] == s then
      s.startOnOpen = true
      s.anyway = true -- for the party chat line (ER.AnnounceStart)
      s.closed = true -- the panel stays shut from here; the gate and chat carry on
      ER.HidePanel(s)
      ER.StartEscort(s)
      ER.Refresh()
    end
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  showAlert = true,
  preferredIndex = 3,
}

function ER.StartAnyway(s)
  if not (s and s.mine) or s.go then return end
  local ready, _, total = ER.Counts(s)
  StaticPopup_Show("ESCORTREADY_START_ANYWAY", s.title, ("%d/%d"):format(ready, total), s)
end

---------------------------------------------------------------------------
-- Test sessions. No quest is ever accepted.
-- As the starter in a group: a live check marked [Test] goes to the group like a real one,
-- party members with the addon get the window and their ticks come back.
-- Solo, or "as a party member": a local window with made-up members, nothing sent.
---------------------------------------------------------------------------
-- Each test press adds another check (up to 4 at once), so the side-by-side panels can be
-- tried too. These quests only lend their titles.
local TEST_QIDS = { 309, 1144, 863, 4021 } -- vanilla escorts, for their titles only

function ER.Test(asStarter)
  local qid, n
  for i, id in ipairs(TEST_QIDS) do
    if not ER.sessions[id] then qid, n = id, i; break end
  end
  if not qid then
    Print("Four test checks are already up. Close or cancel one first.")
    return
  end
  local me = ER.Me()
  local title = ("[Test%s] %s"):format(n > 1 and (" " .. n) or "", ER.QuestTitle(qid))

  if asStarter and ER.HasCompany() then
    local s = NewSession(qid, title, me)
    s.test, s.live = true, true
    Member(s, me).state = "ready"
    Member(s, me).status = ER.MyStatus(qid)
    ER.Send(("Q^%d^%s^T"):format(s.qid, s.title:gsub("%^", "")), s)
    ER.Send(("R^%d^ready^%s"):format(s.qid, Member(s, me).status), s)
    ER.ShowWindow(s)
    ER.Refresh()
    return
  end

  local leader = asStarter and me or "Testleader"
  local roster = asStarter and { me, "Dummyone", "Dummytwo" } or { me, "Testleader", "Dummyone" }
  local s = NewSession(qid, title, leader, roster)
  s.mine, s.test = asStarter, true
  s.members[leader].state = "ready"
  s.members[me].status = ER.MyStatus(qid)
  if not asStarter then
    s.members[me].state = s.members[me].status == "done" and "ready" or "seen"
  end

  -- scripted replies: name, delay, state, status. A "done" member is ready at once.
  local script = asStarter and {
    { "Dummyone", 1, "seen", "none" }, { "Dummytwo", 1.5, "ready", "done" },
    { "Dummyone", 3, "notready", "none" }, { "Dummyone", 7, "ready", "none" },
  } or {
    { "Dummyone", 1, "ready", "done" },
  }
  for _, step in ipairs(script) do
    C_Timer.After(step[2], function()
      if ER.sessions[s.qid] ~= s then return end
      s.members[step[1]].state, s.members[step[1]].status = step[3], step[4]
      ER.Refresh()
    end)
  end
  if not asStarter then
    pcall(PlaySound, SOUNDKIT and SOUNDKIT.READY_CHECK or 8960, "Master")
  end
  ER.ShowWindow(s)
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
  local s = ER.sessions[qid]

  if kind == "L" then
    if b and b ~= "" then ER.Learn(b, true, qid > 0 and qid or nil) end
    return
  end
  if s and not s.live and s.roster then -- a local test on the same quest gives way to a real check
    ER.Cancel(s, true); s = nil
  end
  if kind == "Q" then
    -- Two players started a check on this quest at the same moment, before either heard the
    -- other. Every copy keeps the lower name as the starter (ER.Rank), so they all agree.
    if s and s.leader ~= sender then
      if Rank(sender) >= Rank(s.leader) then return end -- the check I have wins
      if s.mine then
        -- theirs wins: I become a party member of it, still ready (I wanted it started)
        s.leader, s.mine = sender, false
        s.startOnOpen, s.anyway, s.toldReopen = nil, nil, nil
        pcall(StaticPopup_Hide, "ESCORTREADY_START_ANYWAY", s)
        Member(s, ER.Me()).state = "ready"
        ER.Send(("R^%d^ready^%s"):format(qid, Member(s, ER.Me()).status or ER.MyStatus(qid)), s)
        Print("%s started a check for %s at the same moment. Theirs goes ahead and you're marked ready.", sender, s.title)
      else
        s.leader = sender
      end
      Member(s, sender).state = "ready"
      ER.Refresh()
      return
    end
    s = NewSession(qid, (b and b ~= "") and b or ER.QuestTitle(qid), sender)
    if c == "T" then s.test, s.live = true, true end
    Member(s, sender).state = "ready"
    local me = Member(s, ER.Me())
    me.status = ER.MyStatus(qid)
    -- already completed: nothing to pick up, so ready from the start (Not ready still works)
    me.state = me.status == "done" and "ready" or "seen"
    ER.Send(("R^%d^%s^%s"):format(qid, me.state, me.status), s)
    if me.status == "done" then
      -- nothing for me to do: ready without a panel or sound (/er show opens it)
      Print("%s is starting %s. You've already completed it, so you're marked ready.", sender, s.title)
    else
      ER.ShowWindow(s)
      pcall(PlaySound, SOUNDKIT and SOUNDKIT.READY_CHECK or 8960, "Master")
      if FlashClientIcon then pcall(FlashClientIcon) end
    end
  elseif not s then
    return
  elseif kind == "R" then
    local m = Member(s, sender)
    m.state = (b == "ready" or b == "notready" or b == "seen") and b or "seen"
    m.status = c
  elseif kind == "C" and sender == s.leader then
    Print("%s cancelled the party check for %s.", sender, s.title)
    ER.Cancel(s, true)
    return
  elseif kind == "G" and sender == s.leader then
    -- Started. The check ends here; only a 30 s window to say yes to the game's join
    -- prompt is kept (if I ticked ready), so a later start of this quest gets a new check.
    local ready = Member(s, ER.Me()).state == "ready"
    if s.test then
      Print("Test: %s started the quest.", sender)
      if not ready then ER.AlertStartedAnyway(sender, s.title) end -- title says [Test]
    else
      ER.join = { qid = s.qid, title = s.title, ready = ready, untilT = GetTime() + 30 }
      -- Started without me (Start anyway, while I hadn't ticked or said Not ready): say so loudly.
      if not ready then ER.AlertStartedAnyway(sender, s.title) end
    end
    -- ready players see "started" count down; anyone left behind got the alert instead
    ER.EndCheck(s, ready and Member(s, ER.Me()).status ~= "done")
    return
  end
  ER.Refresh()
end

---------------------------------------------------------------------------
-- Escort follow-up: the server's join prompt, and a "let's go" gossip line
---------------------------------------------------------------------------
local GO_WORDS = { "ready", "let's go", "lets go", "begin", "start", "lead the way", "go ahead" }

-- The game asks the party to join only for party-accept quests, which is what escorts are.
-- So the prompt itself teaches us the quest, by title (the event gives no ID). Shared with
-- the group so everyone's copy learns it too.
-- learned[key] = the title as shown; learnedIds[questID] = title. The ID arrives later, from
-- whichever comes first: QUEST_ACCEPTED after joining from the prompt, a quest page with that
-- title (ER.LearnId from LogDetail), or a party member's "L" message that carries one.
function ER.Learn(title, quiet, qid)
  local key = ER.LearnKey(title)
  if not key then return end
  local db = ER.db
  local new = not db.learned[key]
  if new then db.learned[key] = title end
  if qid and qid > 0 then ER.LearnId(qid, title, quiet) end
  if new and not quiet then
    Print("Learned %s as a party event quest. It'll be held for a ready check from now on.", title)
    ER.Send(("L^%d^%s"):format(qid or 0, (title:gsub("%^", ""))))
  end
end

-- An ID for a learned title. Told to the group once (not when it came from the group),
-- so their exports carry it too.
function ER.LearnId(qid, title, quiet)
  local db = ER.db
  if type(qid) ~= "number" or qid <= 0 or db.learnedIds[qid] then return end
  db.learnedIds[qid] = title or ER.QuestTitle(qid)
  local key = ER.LearnKey(title)
  if key and not db.learned[key] then db.learned[key] = title end
  if not quiet then
    ER.Send(("L^%d^%s"):format(qid, (tostring(db.learnedIds[qid]):gsub("%^", ""))))
  end
end

-- Is this quest one we learned by title only? Then record its ID.
function ER.MatchLearned(qid, title)
  local key = ER.LearnKey(title)
  if key and ER.db.learned[key] and not ER.db.learnedIds[qid] then ER.LearnId(qid, title) end
end

-- The quests this account found that the built-in list doesn't have, as plain lines to paste
-- into Discord or a GitHub issue. No character, realm or account names in it.
--   add <id> <title>      marked with /er add
--   learned <id> <title>  learned from the party join prompt
--   learned ? <title>     learned, ID not seen yet
--   not <id> <title>      marked with /er not (a wrong catch)
function ER.ExportText()
  local db = ER.db
  local version = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(ADDON, "Version") or "?"
  local lines, count = {}, 0
  local function Add(kind, qid, title)
    lines[#lines + 1] = ("%s %s %s"):format(kind, qid and tostring(qid) or "?", title or "")
    count = count + 1
  end
  local function Sorted(t)
    local ids = {}
    for id in pairs(t) do if type(id) == "number" then ids[#ids + 1] = id end end
    table.sort(ids)
    return ids
  end
  for _, id in ipairs(Sorted(db.always)) do
    if not ER.IsBuiltIn(id) then Add("add", id, ER.QuestTitle(id)) end
  end
  local idKeys = {}
  for _, id in ipairs(Sorted(db.learnedIds)) do
    local title = type(db.learnedIds[id]) == "string" and db.learnedIds[id] or ER.QuestTitle(id)
    idKeys[ER.LearnKey(title) or ""] = true
    if not ER.IsBuiltIn(id) and not db.always[id] then Add("learned", id, title) end
  end
  local keys = {}
  for key in pairs(db.learned) do if not idKeys[key] then keys[#keys + 1] = key end end
  table.sort(keys)
  for _, key in ipairs(keys) do
    local v = db.learned[key]
    Add("learned", nil, type(v) == "string" and v or key)
  end
  for _, id in ipairs(Sorted(db.never)) do Add("not", id, ER.QuestTitle(id)) end
  table.insert(lines, 1, ("EscortReady %s found quests (%s), %d line%s"):format(
    version, date("%Y-%m-%d"), count, count == 1 and "" or "s"))
  return table.concat(lines, "\n"), count
end

-- Every quest page opened: what was read and what was decided. Kept in EscortReadyDB.log
-- (last 20) so a missed escort can be looked at after a /reload; /er log prints it.
function ER.LogDetail()
  local qid = Plain(GetQuestID())
  if type(qid) ~= "number" then return end
  ER.lastDetailQid = qid
  local title, objective = ER.PageText(qid)
  ER.MatchLearned(qid, title)
  local yes, why = ER.IsEscort(qid)
  local tag
  if C_QuestLog and C_QuestLog.GetQuestTagInfo then
    local ok, info = pcall(C_QuestLog.GetQuestTagInfo, qid)
    if ok and type(info) == "table" then tag = tostring(Plain(info.tagID)) .. " " .. tostring(Plain(info.tagName)) end
  end
  local flags, inQuestie = nil, false
  local qdb = QuestDB or (LibQuestieDB and LibQuestieDB.Quest)
  if qdb and type(qdb.questFlags) == "function" then
    local ok, v = pcall(qdb.questFlags, qid)
    flags = ok and v or nil
  end
  if qdb and type(qdb.name) == "function" then
    local ok, v = pcall(qdb.name, qid)
    inQuestie = ok and v ~= nil
  end
  local log = ER.db.log
  table.insert(log, 1, {
    when = date("%Y-%m-%d %H:%M:%S"), qid = qid, title = title, objective = objective and objective:sub(1, 200),
    group = ER.Channel() or "solo", gate = ER.char.enabled, escort = yes and true or false, why = why,
    tag = tag, questieFlags = flags, inQuestie = inQuestie,
  })
  for i = #log, 21, -1 do log[i] = nil end
end

local function OnAcceptConfirm(...)
  local _, title = ...
  title = Plain(title)
  if type(title) == "string" then ER.Learn(title) end
  local j = ER.join
  if not (j and j.ready and ER.char.autoJoin and GetTime() < j.untilT) then return end
  ER.join = nil -- one prompt, one yes
  ConfirmAcceptQuest()
  StaticPopup_Hide("QUEST_ACCEPT")
  Print("Joined %s.", j.title)
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
f:RegisterEvent("READY_CHECK")
f:RegisterEvent("READY_CHECK_CONFIRM")

f:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    if ... ~= ADDON then return end
    EscortReadyDB = EscortReadyDB or {}
    EscortReadyCharDB = EscortReadyCharDB or {}
    local db, char = EscortReadyDB, EscortReadyCharDB
    db.always = db.always or {}
    db.never = db.never or {}
    db.learned = db.learned or {}     -- lower-case title -> true, from the party join prompt
    db.learnedIds = db.learnedIds or {}
    db.log = db.log or {}
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
    if not ER.Channel() then
      for _, s in ipairs(ER.Running()) do
        if not s.roster then ER.Cancel(s, true) end -- left the group; local tests stay
      end
    end
    ER.Refresh()
  elseif event == "QUEST_DETAIL" then
    ER.LogDetail()
    ER.OnQuestDetail()
  elseif event == "QUEST_FINISHED" then
    ER.HideGate()
  elseif event == "QUEST_ACCEPTED" then
    local a, b = ...
    local qid = Plain(b) or Plain(a) -- (questID) on current clients, (logIndex, questID) on old ones
    if type(qid) == "number" then ER.MatchLearned(qid, ER.QuestTitle(qid)) end -- joined from the prompt
    local s = type(qid) == "number" and ER.sessions[qid]
    if s then
      if s.mine and not s.go then
        -- accepted some other way (an addon that kept its own copy of AcceptQuest): still tell the group
        s.go = true
        ER.Send(("G^%d"):format(s.qid), s)
      end
      ER.EndCheck(s)
    end
  elseif event == "QUEST_ACCEPT_CONFIRM" then
    OnAcceptConfirm(...)
  elseif event == "GOSSIP_SHOW" then
    OnGossip()
  elseif event == "READY_CHECK" then
    ER.rcSeen = GetTime()
    -- the starter of a ready check counts as ready (the game marks them so, with no confirm)
    local who = Norm((...))
    local changed
    for _, s in ipairs(ER.order) do
      local m = who and s.members[who]
      if ByReadyCheck(m) then m.state, m.rc, m.noaddon = "ready", true, true; changed = true end
    end
    if changed then ER.Refresh() end
  elseif event == "READY_CHECK_CONFIRM" then
    local unit, isReady = ...
    ER.OnReadyConfirm(Plain(unit), Plain(isReady))
  end
end)

-- Ticks: no-reply members become "no addon", sessions time out.
C_Timer.NewTicker(1, function()
  if #ER.order == 0 then return end
  local now, changed = GetTime(), false
  for _, s in ipairs(ER.Running()) do
    if now - s.t0 > ER.TIMEOUT then
      Print("Party check for %s timed out.", s.title)
      ER.Cancel(s)
    else
      for _, m in pairs(s.members) do
        if m.state == "wait" and now - m.t > ER.NOADDON then
          m.state, m.noaddon = "noaddon", true -- noaddon stays set after a ready-check answer
          changed = true
        end
      end
    end
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
    Print("Party event gate %s.", OnOff(char.enabled))
  elseif cmd == "join" then
    char.autoJoin = not char.autoJoin
    Print("Join the party event quest when you ticked ready: %s.", OnOff(char.autoJoin))
  elseif cmd == "gossip" then
    char.autoGossip = not char.autoGossip
    Print("Pick the NPC's start line after accepting: %s.", OnOff(char.autoGossip))
  elseif cmd == "scale" and tonumber(arg) then
    char.scale = math.max(0.5, math.min(3, tonumber(arg)))
    ER.ApplyScale()
    Print("Window scale %.2f.", char.scale)
  elseif (cmd == "add" or cmd == "not" or cmd == "reset") and (tonumber(arg) or (arg == "" and ER.lastDetailQid)) then
    -- no ID: the quest page opened last
    local qid = tonumber(arg) or ER.lastDetailQid
    db.always[qid] = cmd == "add" or nil
    db.never[qid] = cmd == "not" or nil
    local yes, why = ER.IsEscort(qid)
    Print("%s (%d): %s%s.", ER.QuestTitle(qid), qid, yes and "party event quest" or "not a party event quest", why and (" - " .. why) or "")
  elseif cmd == "check" and tonumber(arg) then
    local qid = tonumber(arg)
    local yes, why = ER.IsEscort(qid)
    Print("%s (%d): %s%s.", ER.QuestTitle(qid), qid, yes and "party event quest" or "not a party event quest", why and (" - " .. why) or "")
  elseif cmd == "export" then
    ER.ShowExport()
  elseif cmd == "log" then
    local log = db.log
    if #log == 0 then Print("No quest pages seen yet.") end
    for i = 1, math.min(5, #log) do
      local e = log[i]
      Print("%s  %s (%d)  %s  %s%s", e.when, e.title or "?", e.qid, e.group,
        e.escort and "|cff40ff40party event|r" or "|cffff4040not a party event|r", e.why and (" - " .. e.why) or "")
    end
  elseif cmd == "test" then
    ER.Test(arg ~= "member")
  elseif cmd == "config" or cmd == "settings" then
    ER.OpenSettings()
  elseif cmd == "show" then
    if #ER.order > 0 then ER.ShowWindow() else Print("No party check running.") end
  elseif cmd == "cancel" then
    ER.CancelAll()
  else
    Print("Gate %s, auto-join %s, auto start line %s, scale %.2f.", OnOff(char.enabled), OnOff(char.autoJoin), OnOff(char.autoGossip), char.scale)
    Print("/er on | off - the party check gate on the Accept button")
    Print("/er join - join the party event quest automatically once you ticked ready")
    Print("/er gossip - after starting, pick the NPC's \"I'm ready\" line if there's exactly one")
    Print("/er check <questID> | add <id> | not <id> | reset <id>")
    Print("/er add (no ID) - mark the quest page you opened last as a party event quest")
    Print("/er log - the last quest pages opened and what was decided")
    Print("/er export - the quests you found, to copy and send for the built-in list")
    Print("/er show | cancel | scale <n> | config")
    Print("/er test - test check as the starter (sent to your group if you're in one)")
    Print("/er test member - local test as a party member, with dummies")
  end
end
