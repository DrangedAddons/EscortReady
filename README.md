# EscortReady

A WoW Forever addon for escort quests in a group.

Once someone accepts an escort, the NPC starts walking and won't talk to anyone else until it's over. Party members who still had to hand in an earlier part, or wanted to pick the quest up themselves, are stuck. EscortReady stops that.

## How it works

- In a group, an escort quest's Accept button becomes **Check party**. Shift-click it to accept without a check.
- Clicking it sends a ready check to the group. Everyone with the addon gets a window with Ready / Not ready, plus who's on the quest or has done it before.
- When everyone is ready, the quest is accepted by itself. If the quest page was closed, it starts the moment you talk to the quest giver again.
- **Start anyway** starts without everyone, after a Yes on a warning.
- Auto-quest addons (Questie, RestedXP, Leatrix Plus and anything else calling `AcceptQuest()`) are held back on escorts in a group. Their accept starts the party check instead, and EscortReady accepts once the group is ready.
- Party members who ticked ready get the game's "join this quest" prompt accepted for them. If the NPC then offers exactly one "I'm ready" / "Let's go" line, it's picked.

## Escort detection

Uses [Questie](https://github.com/Questie/Questie) (optional, but without it only the built-in list works):

1. A built-in list of vanilla escorts, from Questie's own escort list.
2. Questie's escort quest tag.
3. QuestieDB's party-accept quest flag.

Overrides: `/er add <questID>`, `/er not <questID>`, `/er reset <questID>`, `/er check <questID>`.

## Options

Esc > Options > AddOns > EscortReady, or `/er config`. Per character: the gate, auto-join, the start line, window size. With EllesmereUI loaded the window follows its look and font (Window look dropdown).

The Testing buttons open the window without a quest. As the starter in a group, a [Test] check goes to the party like a ready check; solo, made-up members tick ready over a few seconds. No quest is ever accepted by a test.

## Commands

`/er` (or `/escortready`) lists them all.
