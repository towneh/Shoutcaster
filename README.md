# Shoutcaster

Tank and interrupt announcements and a Battle Shout reminder for warriors in
WoW Forever.

Shoutcaster calls out what your warrior does. It tells your group when a taunt
is resisted, an interrupt misses or Shield Wall goes up, and it reminds you
before Battle Shout runs out, even mid-fight.

This addon is built around the more restrictive Forever addon rules, the same
[combat addon rules Blizzard introduced with
Midnight](https://news.blizzard.com/en-us/article/24244638/how-midnights-upcoming-game-changes-will-impact-combat-addons).

## Install

1. Open the [latest release](https://github.com/towneh/Shoutcaster/releases/latest)
   and download `Shoutcaster-v<version>.zip` from its **Assets**.
2. Extract it into `<WoW>\_forever_\Interface\AddOns\`. It unpacks as a
   ready-named `Shoutcaster` folder.
3. Restart the game.

Open the options from **Settings > AddOns > Shoutcaster**, or type `/scast`
(or `/shoutcaster`). `/scast help` lists the commands.

## Announcements

| When | Message |
| --- | --- |
| Taunt is resisted | `TAUNT RESIST! (<enemy>)` |
| Mocking Blow fails | `MOCKING BLOW FAILED! (<enemy>)` |
| Challenging Shout | `AOE TAUNT!` |
| Shield Wall | `SHIELD WALL ACTIVE!` |
| Last Stand | `LAST STAND ACTIVE!` |
| Shield Bash or Pummel interrupts | `Interrupted <enemy> (<spell>)` |
| Shield Bash or Pummel hits a caster without interrupting | `<spell> parried by <enemy>` (or dodged, blocked and so on), or `<spell> failed on <enemy>` |

Without a combat log to read, Shoutcaster watches your target for the split
second after you cast. A miss, resist or immunity at the moment you taunt
counts as a resist (for Mocking Blow, a dodge or parry too), unless the taunt
takes hold anyway. A cast interrupted at the moment your Shield Bash or Pummel
lands counts as your interrupt. The game hides which spell was interrupted,
and the message names only the enemy. A Shield Bash or Pummel on an enemy that
isn't casting stays quiet.

**Test alert** on the main options page shows a sample on your screen.

### Where announcements go

Each location has its own page under Shoutcaster: **Open world**,
**Battlegrounds** (arenas too), **Dungeons** and **Raid instances**.
Shoutcaster uses the page for where you are rather than your group type. A
raid group on a world boss uses **Open world**, and so does standing outside a
dungeon's portal. The page in use shows a green **Now active**, and the other
pages say which one it is.

Each page is a grid with a row for each message, grouped into **Taunts**,
**Cooldowns** and **Interrupts**, and a column for each channel:

| Column | Sends to |
| --- | --- |
| **Group** | Follows your group wherever you are: party chat in a party, raid chat in a raid (a world boss or a 10-player dungeon run included), instance chat in a battleground |
| **Party** | Always party chat. In a raid that's only your five-player subgroup, handy for something like an interrupt rotation within your melee group |
| **RW** | Raid warning, in a raid when you're leader or assistant |
| **Say** | /say, inside instances only, as the game blocks automated /say elsewhere |
| **Yell** | /yell, inside instances only, for the same reason |
| **Me** | Your own chat window |
| **Screen** | Centre-screen alert with the raid warning sound |

Tick any mix. Ticking **Group** and **Party** together posts once in a party,
because a message never goes to the same channel twice. If the game blocks
addon chat, the message shows on your screen instead. **Copy from...** at the
bottom of each page copies another location's ticks.

Out of the box, everything goes to group chat in the open world and dungeons,
with resisted taunts and failed interrupts also shown on screen. Raid
instances add a raid warning for taunts and cooldowns, and send interrupts to
your subgroup rather than the whole raid. Battlegrounds stay quiet apart from
failed interrupts, which show on screen.

| Command | Effect |
| --- | --- |
| `/scast announce` | Show the current location's settings |
| `/scast announce <location>` | Show a location: `world`, `pvp`, `dungeon` or `raid` |
| `/scast announce <location> <row> <column> on` / `off` | Set one tick, e.g. `/scast announce raid shieldBashMissed party on` |
| `/scast announce copy <from> <to>` | Copy one location's ticks to another |
| `/scast announce on` / `off` | Turn all announcements on or off |
| `/scast announce test` | Show a sample alert on your screen |

Rows are `taunt`, `mockingBlow`, `challengingShout`, `shieldWall`,
`lastStand`, `shieldBashInterrupted`, `shieldBashMissed`, `pummelInterrupted`
and `pummelMissed`. Columns are `group`, `party`, `rw`, `say`, `yell`, `me`
and `screen`.

## Reminders

Shows the Battle Shout icon when your shout is missing or about to run out. It
pulses once the shout has gone and counts down while it's under your warning
time, with one sound as it appears.

Out of combat Shoutcaster reads the buff directly. During a fight the game
hides your buffs from addons. Shoutcaster then counts down from what it saw
before the pull, restarts the count whenever you shout, and checks the real
buff again as soon as the fight ends. If another warrior's shout replaces
yours mid-fight, the countdown keeps following yours until then.

The settings are under **Reminders** on the main options page:

| Setting | Default | Notes |
| --- | --- | --- |
| **Battle Shout** | On | Warriors only; the settings below need it ticked |
| **Warn when under** | 15 seconds | 0 to 60. At 0 the icon shows only once the shout has run out |
| **Out of combat** | In instances | Also Always or Never. Hidden while you're resting in a city or inn. In combat it always shows when needed |
| **Sound** | On | Plays once as the icon appears |
| **Unlock to move** | Off | Shows the icon as "Drag to move" so you can place it; a reload locks it again |
| **Icon size** | 100% | 50% to 200%. The icon stays centred on the same spot |
| **Horizontal offset**, **Vertical offset** | 0 and -120 | Distance from the centre of the screen |

Offsets count from the centre of the screen, and 200 and -200 sit the same
distance either side of it. The sliders reach the screen edges at any
resolution or UI scale, and dragging the icon updates them. **Preview** shows
the icon for five seconds, as does changing its size or position.

| Command | Effect |
| --- | --- |
| `/scast remind` | Show the reminder settings |
| `/scast remind on` / `off` | Turn the Battle Shout reminder on or off |
| `/scast remind move` | Unlock or lock the icon for dragging |
| `/scast remind offset <x> <y>` | Place the icon at an exact offset from the screen centre |
| `/scast remind scale <percent>` | Set the icon size, 50 to 200 |
| `/scast remind test` | Show the icon for five seconds |

## Profiles

Settings live in profiles shared by all your characters, and each character
remembers which profile it uses. **Profiles** at the bottom of the main
options page can switch, create (starting from a copy of the current one),
copy from, delete and reset them. `Default` and the profile you're using can't
be deleted. A character whose profile was deleted goes back to `Default` the
next time it logs in or reloads.

| Command | Effect |
| --- | --- |
| `/scast profile` | List your profiles |
| `/scast profile <name>` | Switch to a profile |

## Licence

MIT. See [LICENSE](LICENSE).
