# Break Ankles

A Roblox tag game built around Huss Valley's core loop: runners have to get across an open field three times, a chaser with a knife tries to tag them, and the way you survive is by breaking ankles. That means juking with a sideways dash or an instant stop at the moment the chaser commits to a swing. If the swing misses, the chaser falls over.

The rules, roles, abilities, items, currencies, prices and controls follow public guides to Huss Valley. All the code and art in this project are original. Nothing was copied out of Huss Valley.

## Play it

1. Download [`build/BreakAnkles.rbxlx`](build/BreakAnkles.rbxlx) and open it in **Roblox Studio**.
2. Press **Play**. Bots fill empty slots, so you can play alone. The lobby, the arena and the bots are generated when the game starts, so the place looks empty in edit mode. That's expected.
3. To publish it, use **File → Publish to Roblox As…**, create a new experience and name it **Break Ankles**.
4. In **Game Settings → Security**, turn on **Enable Studio Access to API Services** so gems, coins and unlocks save. Without it the game still runs, but nothing saves.
5. Set the experience icon and thumbnails. The Creator Dashboard takes uploaded image files:
   - **Thumbnails:** upload the three pictures in [`art/`](art/) (1920×1080): `thumbnail-ankles-broken.png`, `thumbnail-run.png` and `thumbnail-hero-or-chicken.png`. Your ForgeGUI library also has the original thumbnail art (Roblox asset `91723483788506`).
   - **Icon:** download it from your ForgeGUI library (Roblox asset `98979542296379`).

## How a match works

1. **Intermission (20 s).** Players wait on the lobby deck beside the field and vote for **The Valley** (grass) or **The Dunes** (sand). Each vote card shows a picture of the map over a slowly turning 3D preview, and the winning map's picture shows while the match starts. The Shop, Codes and AFK buttons are on the left.
2. **Roles.** One random player becomes the **Chaser**: one for every 8 players, minimum one. Everyone else is a **Runner**.
3. **Crossings.** Runners line up in a safe zone at one end of a long rectangular field. After "3, 2, 1, RUN!!" they have 40 seconds to reach the safe zone on the far side. The next crossing goes back the other way, and there are 3 crossings in total. Chasers can't enter safe zones, and runners can't be hit inside them.
4. **Getting caught.** One knife hit downs a runner. A teammate can hold **E** next to them to revive them, which takes 2.5 seconds and leaves the rescuer frozen in place while they hold. A downed runner can also use a Rescue Kit. If nobody saves you within 10 seconds, or you're still on the field when the timer runs out, you become a Chaser. The chaser side snowballs.
5. **Hero or Chicken.** Before crossing 2 or 3, one runner may be offered a solo run for +100 gems. If they say yes, everyone else waits behind the gate while they cross alone.
6. **Winning.** Runners win if anyone survives all 3 crossings, and the win is **Flawless** if nobody was caught all game. Chasers win if every runner is converted. A results screen breaks down what you earned.

## Controls

| Action | Keyboard / mouse | Gamepad | Mobile |
| --- | --- | --- | --- |
| Move | WASD | Left stick | Thumbstick |
| Lateral dash (runners) | **Space while holding A or D** (add W for a diagonal) | A + stick | ◀ / ▶ buttons |
| Instant stop | **Alt** | B | STOP |
| Ability | Q | Y | Q |
| Item | F | R1 | F |
| Swing knife (chasers) | Click | R2 | SWING |
| Revive teammate / open shop | Hold E | X | Tap the prompt |

Movement uses momentum. You speed up instead of starting at full speed, and you slide a little when you let go. The dash keeps you facing the same way, so it reads as a juke. There's no jumping and no forward dash.

**Breaking ankles:** if a chaser swings and misses within 0.8 seconds of a runner within 12 studs dashing or stopping, the chaser trips and falls for about a second. The runner gets +15 gems, the kill feed announces it, and it counts toward your Ankles leaderstat. Any missed swing also slows the chaser briefly.

## Abilities, items and economy

**Gems** come from crossings, survival, catches, ankle breaks, rescues and the purple gems on the field, which only runners can pick up. Gems buy abilities and knives. **Coins** come from match rewards and buy consumables.

| Runner ability | Gems | Effect |
| --- | --- | --- |
| One Hit Shield | free | Blocks the next hit for 0.75 s |
| Pocket Door | 875 | A door between you and the chaser that only blocks chasers; 2 swings break it; lasts 6 s |
| Emergency Airhorn | 1,450 | Blasts nearby chasers backward |
| Cloak | 1,625 | Invisible for 3 s. You can still be hit, and using an item ends it |

| Chaser ability | Gems | Effect |
| --- | --- | --- |
| Bear Trap | free | Tossed 10 studs ahead; roots the first runner for 0.5 s; lasts 12 s |
| Bowling Ball | 600 | Rolls along the ground; a direct hit trips the runner |
| Big Dagger | 1,125 | Doubles your reach for the next swing; expires after 5 s |
| Rocket Shoes | 1,300 | Burst in your move direction (or camera direction) |
| Rufus's Leash | 1,625 | 15-stud leash that yanks a runner 6 studs toward you |

| Item (3 uses per pack) | Coins | Effect |
| --- | --- | --- |
| Banana Peel | 135 | The first opponent to step on it slips |
| Rescue Kit | 203 | Revive yourself when downed |
| Adrenaline | 135 | 5 s of extra speed and sharper turning |

There are also six cosmetic knife skins, which cost gems, and seven titles that show above your head. You earn titles through play, for example Flawless, Hero, Menace and Untouchable. Leveling comes from XP, and rescues give a big XP boost.

**Codes** (Codes button): `BREAKANKLES` gives 250 gems, 15 minutes of 2x gems, 15 minutes of 2x coins and the *Ankle Breaker* title. `FIRSTCROSSING` gives 150 gems and 200 coins. Add your own in `Config.Codes`.

## Changing the game

Every number lives in [`src/shared/Config.luau`](src/shared/Config.luau): timers, field size, speeds, dash, knife reach, ankle-break window, rewards, codes, bots, sounds and music. Prices and descriptions are in [`src/shared/Catalog.luau`](src/shared/Catalog.luau).

- **Music:** paste audio IDs into `Config.Music.Lobby` and `Config.Music.Chase`. The game ships without music because the ForgeGUI plan on this account doesn't include music or sound-effect generation.
- **Sounds:** the defaults are built-in Roblox sounds. Swap in any `rbxassetid://` you own in `Config.Sounds`.
- **Robux gem packs:** create Developer Products and add them to `Config.Products`, for example `[123456] = { Gems = 1000 }`.
- **Bots:** set `Config.Bots.Enabled = false` to require real players. While it's on, bots fill each match up to 6 players.

## Working on the code

The source is a [Rojo](https://rojo.space) project:

```bash
rojo serve                                               # live-sync into Studio with the Rojo plugin
rojo build default.project.json -o build/BreakAnkles.rbxlx   # rebuild the place file
selene src                                               # lint
```

| Path | What it does |
| --- | --- |
| `src/server/Match.luau` | Match loop: intermission, map vote, chaser pick, crossings, Hero or Chicken, results |
| `src/server/Combat.luau` | Knife swings, shields, ankle breaks, downs, revives, conversions |
| `src/server/Abilities.luau` | Abilities (Q) and consumables (F) |
| `src/server/Hazards.luau` | Bear traps, banana peels, bowling balls, pocket doors |
| `src/server/Bots.luau` | Bot runners and chasers that juke, chase, fake out and rescue |
| `src/server/Roster.luau` | Players and bots, roles, knives, name tags, cloak |
| `src/server/MapBuilder.luau` | The lobby deck and both arena themes, built from parts |
| `src/server/DataService.luau` | Saving gems, coins, unlocks and stats |
| `src/server/Shop.luau` | Buying, equipping, codes, votes, AFK, Robux gem packs |
| `src/server/Gems.luau`, `Rewards.luau`, `Status.luau`, `Phase.luau`, `Groups.luau` | Field gems, payouts, stuns/slows, shared match state, collision groups |
| `src/client/Movement.luau` | Momentum movement, dash, instant stop, knockbacks |
| `src/client/Input.luau` | Keyboard, gamepad and touch bindings |
| `src/client/HUD.luau`, `Menus.luau` | All on-screen UI, the shop and codes |
| `src/client/Effects.luau`, `Sounds.luau` | Swings, trails, shields, ankle-break pop-ups, camera shake, audio |
| `src/shared/` | Config, catalog, arena geometry, movement math, remotes |

## Known differences from Huss Valley

- No exact numbers for field size, speeds or timers have been published for Huss Valley, so the values in `Config` are estimates you can tune.
- Guides list a fifth runner ability, *Broken Vow*, but don't describe what it does, so it isn't included.
- Huss Valley's later multi-level map, with vaults, slides and rooftops, isn't included. This version uses the classic open field plus a second sand-themed map.
- Bots aren't part of Huss Valley. They're here so the game is playable before it has players, and you can turn them off.
