# Changelog

## 0.13.0

- New option **Also in battlegrounds and arenas** (off by default, per character, or `/er bg`). A 40-player Alterac Valley raid was getting a ready check for The Battle of Alterac; now battlegrounds aren't checked unless you tick it.
- New option **Also in raid groups** (on by default, per character, or `/er raid`). Untick it and party event quests go through without a check while you're in a raid.

## 0.12.1

- Test checks no longer look at whether you've done the test quest (they borrow real vanilla escorts, which party members may have completed). Everyone is "not done" in a test, so everyone gets the panel and ticks ready by hand. Party members need 0.12.1 too.

## 0.12.0

- Alone in a group (everyone else has left or is offline), party event quests aren't held and no check starts. Nobody is there to be locked out.
- Removed shift-click on Check party. The only ways to start a party event quest in a group are everyone ready, or Start anyway and its Yes.

## 0.11.0

- Several party event quests can be checked at once. Each check gets its own panel, side by side in a row centred on the screen, the first one started on the left. With one check the panel is full size; with more, the panels narrow so the row fits. Drag any panel to move the row. The X closes one panel (the check keeps running, `/er show` brings it back) and Escape closes them all.
- Opening a party event quest while someone else's check for it is running shows their check. It no longer replaces it on your screen or sends a second one to the group.
- Two players starting a check on the same quest at the same moment: every copy keeps the one from the alphabetically first name. The other starter becomes a party member of it, marked ready. Before, both acted as the starter and both accepted.
- The game's ready check now only fills in players without the addon. Addon users answer in each quest's panel.
- Testing: each press of a test button adds another check (up to four), so the side-by-side panels can be tried too.
- `/er cancel` cancels every running check.

## 0.10.0

- When anyone in the group doesn't have EscortReady, the start also goes in party chat, since they can't get the addon's alert:
  - Start anyway: "[EscortReady] Started <quest> without waiting for everyone. The quest giver is busy until it's over."
  - Everyone ready: "[EscortReady] Everyone's ready: <quest> has started."
- Nothing is posted when everyone has the addon. The live group test posts it too, with [Test] in the quest name.

## 0.9.0

- Players without EscortReady can answer now. When someone in the group shows "No addon", the starter's window gets a **Ready check** button. It posts one party chat line naming the quest (the quest giver will be busy until it's over, hand in or pick it up first, then hit Ready) and starts the game's own ready check.
- Their Ready / Not ready goes on their line, marked "ready check". Ready counts as ready, so when everyone is ready the quest starts as usual.
- The game only lets the party leader (or a raid assistant) start a ready check. Otherwise the button is greyed out and the window says to ask the leader to type /readycheck. Answers to anyone's ready check count while a check is running.
- In a group where everyone has the addon nothing changes: no button and no party message.

## 0.8.0

- When everyone is ready the quest still starts straight away, but the window no longer vanishes in a flash. It stays up showing everyone ready and "The quest has started", counts down "This window closes in 3... 2... 1..." and closes itself. You can close it sooner with the X or Escape. (Most noticeable when everyone has already done the quest and is marked ready instantly.)
- Start anyway still shuts the window at once.

## 0.7.0

- When the starter uses Start anyway, party members who hadn't ticked Ready (or said Not ready) get an alert: a raid-warning banner in the middle of the screen, the raid-warning sound and a chat line saying who started the quest without waiting for them. Ready players and players who already completed it get no alert. The live group test shows it too.

## 0.6.2

- Fixed: after a quest started, the check stayed marked "started" for up to 5 minutes, and a new start of the same quest in that time went through with no ready check (a failed escort, or someone else going next). Now the check ends the moment the quest starts, and every start gets a fresh ready check.
- Players who have already completed the quest are marked ready without the window popping up or the ready-check sound; they get a chat line instead. `/er show` still opens it.

## 0.6.1

- The ready window closes by itself on everyone's screen as soon as the whole group is ready. Party members get a chat line saying the starter is starting the quest. `/er show` brings the window back.

## 0.6.0

- Learned quests now get their quest ID, not just the title: from your quest log when you join from the prompt, from the quest page the next time anyone opens it, or from a party member who has it.
- `/er export` (or Export found quests in the options) opens a box with the quests you've found that aren't in the built-in list yet, ready to copy and paste in Discord or a GitHub issue. No character or realm names in it.

## 0.5.0

- Covers **party event quests**, not just escorts: fights and anything else where accepting ties up the quest giver. The window, chat and options say "party event quest" now.
- New check: Questie's event objective ("Escort...", "Protect...", "Defend...", "Rescue...", "Escape..."). On Forever's data it matches only real escorts.
- Added to the built-in list: Protect Daphne Stilwell, Escort Ringo, four Forever escorts (Perith Stormhoof, Lynessa Duskblossom, Pal'juh, Bareth Dawnstone) and Rock 'em and Sock 'em (the G45-B4G fight).
- The quest page check also matches "help ... escape".

## 0.4.0

- Catches escorts Questie doesn't know (Forever's own quests, like Rescue Roundup):
  - the quest objective saying "escort", "safely to", "lead ... to safety" and the like;
  - the game's own escort tag, read directly;
  - learning: when the game asks you to join a party member's quest, that quest is remembered as an escort for next time, and passed to the group.
- `/er add` with no ID marks the quest page you opened last as an escort.
- `/er log` lists the last quest pages opened and why each was or wasn't treated as an escort (also saved for a closer look after /reload).

## 0.3.0

- Party members who have already completed the escort are marked ready automatically, with "already completed" next to their name. They can still click Not ready if they need the NPC for something else.

## 0.2.0

- Auto-quest addons can no longer start an escort in a group. Questie, RestedXP, Leatrix Plus, EllesmereUI's quest tracker, dialogue addons and anything else that calls `AcceptQuest()` is held back on an escort until the group is ready.
- When an auto-accept is held back, the party check starts by itself. Once everyone is ready, or you say Yes to Start anyway, EscortReady accepts the quest.
- Shift-click on Check party still accepts straight away.

## 0.1.0

- First version. In a group, an escort quest's Accept button becomes "Check party". It sends a ready check to the group; everyone with the addon gets a window to tick Ready or Not ready.
- As soon as everyone is ready the quest is accepted by itself (if the quest page was closed, it starts the moment you talk to the quest giver again). Party members who ticked ready get the game's join prompt confirmed for them.
- Start anyway starts without everyone ready, after a Yes on a warning prompt. The window closes as soon as you say Yes, or as soon as the escort starts.
- Addon icon: a lit-up group of people (the Everybody's Friend guild perk art).
- With EllesmereUI loaded, the window and buttons match its look (Match EllesmereUI by default, or pick one in the options) and use its global font.
- After starting, if the NPC offers exactly one "I'm ready" / "Let's go" style line, it's picked.
- Escorts are detected from a built-in vanilla list, Questie's escort tag and QuestieDB's party-accept quest flag. `/er add` and `/er not` override it.
- Options panel with test buttons: in a group the starter test goes out to the party like a real check (no quest accepted); solo it uses dummy members.
