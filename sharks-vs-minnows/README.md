# Sharks Vs Minnows

A round-based Roblox tag game. One shark starts in the middle of the ocean, and every other player is a minnow on the west beach. When the gates drop, the minnows have to swim to the far beach before time runs out. Anyone who gets chomped, or doesn't make it across in time, becomes a shark too. The last minnow standing wins.

Everything is built from code (the map, lighting, UI and effects), so there are no models, decals or packages to import.

## Play it in Roblox Studio

1. Download `SharksVsMinnows.rbxlx` from this folder.
2. Open it in Roblox Studio with **File → Open from File**.
3. Press **Play** (F5). The map builds itself when the server starts. The world is empty in edit mode, which is expected.

With only you in the server, bots fill the round up to 8 swimmers so it's still playable. To test with several real players, use **Test → Clients and Servers** with 2–4 players.

### Publishing

1. **File → Publish to Roblox**.
2. To save coins, gems and wins between sessions, turn on **Game Settings → Security → Enable Studio Access to API Services**. Live servers save automatically.
3. If you want rounds made only of real players, set `Config.BotsEnabled = false` in `ReplicatedStorage/Shared/Config`.

## How a round works

| Phase | What happens |
| --- | --- |
| Intermission (20s) | Everyone hangs out on the lobby island. Use the shop or redeem codes. |
| Ready (4s) | Gates are up, sharks reset to the center line and are frozen, and a 3-2-1 countdown plays. |
| Crossing (22s, getting shorter) | Gates drop. Minnows race to the opposite beach while sharks chomp anything in the water. |
| Results | Survivors win after 8 crossings, or the last minnow wins outright. Sharks win if the ocean is cleared. |

Beaches are safe zones: sharks physically can't step onto them, and nobody can be tagged there.

## Controls

| Action | Key | Mobile / gamepad |
| --- | --- | --- |
| Ability | E | Tap the big button / X |
| Speed Kelp | 1 | Tap the item button |
| Lucky Pearl | 2 | Tap the item button |
| Fishing Net | 3 | Tap the item button |
| Shop, Codes, Spectate | Buttons on the left | Same |

## Abilities

Minnow abilities

| Ability | Cost | Cooldown | Effect |
| --- | --- | --- | --- |
| 💨 Dart | Free | 8s | Short burst of speed |
| 🫧 Bubble Shield | 250 | 22s | Chomps bounce off for 2.5s |
| 🦑 Ink Cloud | 400 | 18s | Nearby sharks are slowed by half and their screen goes black |
| 🌊 Riptide | 750 | 20s | +9 speed for 3s |

Shark abilities

| Ability | Cost | Cooldown | Effect |
| --- | --- | --- | --- |
| 🦈 Lunge | Free | 7s | Explosive dash with a longer bite |
| 📡 Sonar | 300 | 20s | See every minnow through walls for 4s |
| 🩸 Frenzy | 500 | 24s | +8 speed and a bigger bite for 3.5s |
| 🌀 Whirlpool | 850 | 26s | A whirlpool that slows minnows inside it for 3s |

Consumables are bought in the shop, and new players start with a few.

| Item | Who can use it | Effect |
| --- | --- | --- |
| 🌿 Speed Kelp (30) | Anyone | +7 speed for 4s |
| 🦪 Lucky Pearl (75) | Minnows | Blocks the next chomp within 8s |
| 🕸️ Fishing Net (50) | Sharks | Drops a net that roots the first minnow through it for 1.5s |

## Economy

- **Coins:** +10 per crossing survived, +15 per chomp, +60 for surviving the round, +40 bonus for the last minnow, +35 per shark when sharks win, and +5 for playing.
- **Gems:** +1 per win. Spend them on trails (Bubbles, Coral Reef, Toxic Waste, Sunken Gold, Rainbow Reef).
- **Codes:** `SHARKBAIT`, `MINNOWMANIA`, `FINSUP`, `RELEASE`. Add your own in `Config.Codes`.

Wins and coins also appear on the player list.

## Tweaking

Every number lives in `src/shared/Config.luau`: round timers, number of crossings, speeds, tag range, prices, rewards, codes, bot count and colors. Change a value, run `node build.mjs`, and reopen the place.

## Project layout

```
sharks-vs-minnows/
├── SharksVsMinnows.rbxlx      ← open this in Roblox Studio
├── default.project.json       ← Rojo project (same layout, for live syncing)
├── build.mjs                  ← rebuilds the .rbxlx from src/  (node build.mjs)
└── src/
    ├── shared/   → ReplicatedStorage.Shared
    │   ├── Config.luau        all tunables
    │   └── Remotes.luau       every RemoteEvent / RemoteFunction
    ├── server/   → ServerScriptService.Server
    │   ├── Main.server.luau   round loop, tagging, rewards, shop and codes
    │   ├── MapBuilder.luau    lobby island, beaches, ocean, reef, gates, lighting
    │   ├── Entities.luau      players and bots: roles, speed effects, shark/minnow looks, trails
    │   ├── Abilities.luau     abilities and consumables (server-authoritative)
    │   ├── Bots.luau          AI minnows and sharks
    │   └── PlayerData.luau    DataStore saving
    └── client/   → StarterPlayer.StarterPlayerScripts.Client
        ├── Client.client.luau input, remotes, spectating
        ├── Hud.luau           status bar, timer, role, ability bar, banners, kill feed
        ├── Shop.luau          shop and codes windows
        ├── Fx.luau            particles, sounds, camera shake, sonar, ink
        └── Ui.luau            GUI helpers
```

If you use [Rojo](https://rojo.space), run `rojo serve` in this folder and connect from the Studio plugin instead of opening the `.rbxlx`.

The server decides tags, cooldowns, items, coins and purchases, so a modified client can't give itself currency or skip cooldowns. Movement is still client-controlled like any Roblox game, so add an anti-speed check before a big launch.
