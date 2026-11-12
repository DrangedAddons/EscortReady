# Changelog

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
