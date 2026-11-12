# EscortReady

A WoW Forever addon for **party event quests** in a group: escorts, fights, and anything else where accepting the quest ties up the quest giver.

Once someone accepts one, the NPC walks off, turns hostile or starts a scene, and won't talk to anyone else until it's over. Party members who still had to hand in an earlier part, or wanted to pick the quest up themselves, are stuck. EscortReady stops that.

## How it works

- In a group, a party event quest's Accept button becomes **Check party**. Shift-click it to accept without a check.
- Clicking it sends a ready check to the group. Everyone with the addon gets a window with Ready / Not ready, plus who's on the quest. Anyone who has already completed it is marked ready automatically.
- When everyone is ready, the quest is accepted by itself. If the quest page was closed, it starts the moment you talk to the quest giver again.
- **Start anyway** starts without everyone, after a Yes on a warning.
- Auto-quest addons (Questie, RestedXP, Leatrix Plus and anything else calling `AcceptQuest()`) are held back on these quests in a group. Their accept starts the party check instead, and EscortReady accepts once the group is ready.
- Party members who ticked ready get the game's "join this quest" prompt accepted for them. If the NPC then offers exactly one "I'm ready" / "Let's go" line, it's picked.

## How a quest is recognised

No single source flags all of them, so several checks run:

| Check | Catches |
|---|---|
| Built-in list | known escorts and fights, vanilla and Forever |
| Questie's event objective ("Escort...", "Protect...", "Defend...") | escorts Questie has, Forever ones included |
| The quest page's objective ("escort", "safely to", "help ... escape") | escorts that say so on the page |
| The game's / Questie's escort tag | tagged escorts |
| Learning from the party join prompt | anything the game sends the join prompt for, after the first time; shared with the group |
| `/er add` | anything the others miss |

[Questie](https://github.com/Questie/Questie) is optional, but without it only the built-in list, the page text, learning and `/er add` work.

Overrides: `/er add [questID]` (no ID: the quest page you opened last), `/er not <questID>`, `/er reset <questID>`, `/er check <questID>`. `/er log` shows what each recent quest page was decided as, and why.

## Options

Esc > Options > AddOns > EscortReady, or `/er config`. Per character: the gate, auto-join, the start line, window size. With EllesmereUI loaded the window follows its look and font (Window look dropdown).

The Testing buttons open the window without a quest. As the starter in a group, a [Test] check goes to the party like a ready check; solo, made-up members tick ready over a few seconds. No quest is ever accepted by a test.

## Commands

`/er` (or `/escortready`) lists them all.
