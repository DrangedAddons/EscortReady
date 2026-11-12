-- Escort detection. Three sources, checked in order after the player's own overrides:
--   1. KNOWN below: vanilla escorts, from the "Escort Quests" block of Questie's
--      Modules/Auto/DisallowedIDs.lua (non-escorts in that block left out).
--   2. Questie's quest tag 84 (ESCORT), via QuestieDB.GetQuestTagInfo.
--   3. QuestieDB's questFlags PARTY_ACCEPT bit (2). The server sends the party an
--      "X is starting Y, join?" prompt for these, which is how escorts work.
local _, ER = ...

local KNOWN = {
  [155] = true,  -- The Defias Brotherhood
  [219] = true,  -- Missing In Action
  [309] = true,  -- Protecting the Shipment
  [434] = true,  -- The Attack!
  [435] = true,  -- Escorting Erland
  [648] = true,  -- Rescue OOX-17/TN!
  [660] = true,  -- Hints of a New Plague?
  [665] = true,  -- Sunken Treasure
  [667] = true,  -- Death From Below
  [731] = true,  -- The Absent Minded Prospector
  [836] = true,  -- Rescue OOX-09/HL!
  [863] = true,  -- The Escape
  [898] = true,  -- Free From the Hold
  [938] = true,  -- Mist
  [945] = true,  -- Therylune's Escape
  [976] = true,  -- Supplies to Auberdine
  [994] = true,  -- Escape Through Force
  [995] = true,  -- Escape Through Stealth
  [1144] = true, -- Willix the Importer
  [1222] = true, -- Stinky's Escape
  [1270] = true, -- Stinky's Escape
  [1273] = true, -- Questioning Reethe
  [1324] = true, -- The Missing Diplomat
  [1393] = true, -- Galen's Escape
  [1440] = true, -- Return to Vahlarriel
  [1560] = true, -- Tooga's Quest
  [2742] = true, -- Rin'ji is Trapped!
  [2767] = true, -- Rescue OOX-22/FE!
  [2845] = true, -- Wandering Shay
  [2904] = true, -- A Fine Mess
  [3367] = true, -- Suntara Stones
  [3382] = true, -- A Crew Under Fire
  [3525] = true, -- Extinguishing the Idol
  [3982] = true, -- What Is Going On?
  [4121] = true, -- Precarious Predicament
  [4245] = true, -- Chasing A-Me 01
  [4261] = true, -- Ancient Spirit
  [4322] = true, -- Jail Break!
  [4491] = true, -- A Little Help From My Friends
  [4770] = true, -- Homeward Bound
  [4901] = true, -- Guardians of the Altar
  [4904] = true, -- Free at Last
  [4966] = true, -- Protect Kanati Greycloud
  [5203] = true, -- Rescue From Jaedenar
  [5321] = true, -- The Sleeper Has Awakened
  [5713] = true, -- One Shot. One Kill.
  [5821] = true, -- Bodyguard for Hire
  [5943] = true, -- Gizelton Caravan
  [5944] = true, -- In Dreams
  [6132] = true, -- Get Me Out of Here!
  [6403] = true, -- The Great Masquerade
  [6482] = true, -- Freedom to Ruul
  [6523] = true, -- Protect Kaya
  [6544] = true, -- Torek's Assault
  [6641] = true, -- Vorsha the Lasher
  [7046] = true, -- The Scepter of Celebras
  [25476] = true, -- Rescue OOX-22/FE!
  -- Found in Forever's QuestieDB by their event objective (2026-11-13)
  [1651] = true,  -- Protect Daphne Stilwell
  [4492] = true,  -- Escort Ringo to Spraggle Frock
  [98430] = true, -- Escort Perith Stormhoof out of Palemane Rock (Forever)
  [99053] = true, -- Escort Lynessa Duskblossom out of Ban'ethil (Forever)
  [99123] = true, -- Escort Pal'juh out of Kolkar Crag (Forever)
  [99144] = true, -- Escort Bareth Dawnstone out of Crusader's Outpost (Forever)
  -- Fights and other events that sent the party join prompt in game
  [96067] = true, -- Rock 'em and Sock 'em: fight Sleebo's robot G45-B4G (Forever)
}

local ESCORT_TAG = 84
local PARTY_ACCEPT = 2

local questieDB
local function QuestieModule()
  if questieDB ~= nil then return questieDB or nil end
  local loader = QuestieLoader
  if loader and loader.ImportModule then
    local ok, mod = pcall(loader.ImportModule, loader, "QuestieDB")
    if ok and type(mod) == "table" and type(mod.GetQuestTagInfo) == "function" then
      questieDB = mod
      return mod
    end
  end
  return nil -- not cached: Questie may still be loading
end

local function Plain(v)
  if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
  return v
end

-- The open quest page's title and text, when the page shows quest qid. Forever has quests
-- Questie doesn't know (Rescue Roundup), and these are what's left to go on.
local function PageText(qid)
  local ok, open = pcall(GetQuestID)
  if not ok or Plain(open) ~= qid then return nil end
  local function Read(fn)
    if type(fn) ~= "function" then return "" end
    local okr, v = pcall(fn)
    v = okr and Plain(v)
    return type(v) == "string" and v or ""
  end
  return Read(GetTitleText), Read(GetObjectiveText), Read(GetQuestText)
end
ER.PageText = PageText

-- Words that only show up in an escort's objective. Checked against the objective text only
-- (not the story text, which says "protect" and "lead" for all sorts of quests).
local OBJECTIVE_WORDS = { "escort", "safely to", "safely back", "lead .- to safety", "lead .- out of", "protect .- while", "keep .- alive", "help .- escape" }

-- Questie's event objective (triggerEnd: the quest-log line ticked by an event, e.g. "Escort
-- Corporal Keeshan back to Redridge"). Measured on Forever's QuestieDB: these words caught 35
-- of the 56 known party event quests and 6 others, all 6 real escorts. Exploration and
-- battleground events use the same field with other wording.
local EVENT_WORDS = { "escort", "protect", "defend", "rescue", "escape" }

function ER.LearnKey(title)
  title = Plain(title)
  if type(title) ~= "string" or title == "" then return nil end
  return title:lower():gsub("^%s+", ""):gsub("%s+$", "")
end

-- Returns true/false plus the source that decided it.
function ER.IsEscort(qid)
  if type(qid) ~= "number" or qid <= 0 then return false end
  local db = ER.db
  if db and db.never[qid] then return false, "you marked it not a party event quest" end
  if db and db.always[qid] then return true, "your list" end
  if KNOWN[qid] then return true, "known party event quest" end
  if db and db.learnedIds[qid] then return true, "seen with the party join prompt before" end

  local title, objective = PageText(qid)
  local key = ER.LearnKey(title)
  if db and key and db.learned[key] then return true, "seen with the party join prompt before" end
  if objective and objective ~= "" then
    local low = objective:lower()
    for _, w in ipairs(OBJECTIVE_WORDS) do
      if low:find(w) then return true, "the objective says \"" .. w:gsub("%.%-", "...") .. "\"" end
    end
  end

  if C_QuestLog and C_QuestLog.GetQuestTagInfo then
    local ok, info = pcall(C_QuestLog.GetQuestTagInfo, qid)
    if ok and type(info) == "table" and Plain(info.tagID) == ESCORT_TAG then return true, "the game's escort tag" end
  end

  local mod = QuestieModule()
  if mod then
    local ok, tag = pcall(mod.GetQuestTagInfo, qid)
    if ok and tag == ESCORT_TAG then return true, "Questie escort tag" end
  end

  local qdb = QuestDB or (LibQuestieDB and LibQuestieDB.Quest)
  if qdb and type(qdb.triggerEnd) == "function" then
    local ok, trig = pcall(qdb.triggerEnd, qid)
    local text = ok and type(trig) == "table" and trig[1] or (ok and trig)
    if type(text) == "string" then
      local low = text:lower()
      for _, w in ipairs(EVENT_WORDS) do
        if low:find(w, 1, true) then return true, "Questie's event objective says \"" .. w .. "\"" end
      end
    end
  end
  -- (Forever's QuestieDB has no questFlags; kept for clients whose data does.)
  if qdb and type(qdb.questFlags) == "function" then
    local ok, flags = pcall(qdb.questFlags, qid)
    if ok and type(flags) == "number" and bit.band(flags, PARTY_ACCEPT) ~= 0 then
      return true, "Questie party-accept flag"
    end
  end
  return false
end

function ER.QuestTitle(qid)
  local t
  if C_QuestLog and C_QuestLog.GetTitleForQuestID then
    local ok, v = pcall(C_QuestLog.GetTitleForQuestID, qid)
    if ok and type(v) == "string" and v ~= "" then t = v end
  end
  if not t then
    local qdb = QuestDB or (LibQuestieDB and LibQuestieDB.Quest)
    if qdb and type(qdb.name) == "function" then
      local ok, v = pcall(qdb.name, qid)
      if ok and type(v) == "string" then t = v end
    end
  end
  return t or ("Quest " .. qid)
end
