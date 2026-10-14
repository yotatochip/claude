# Gridiron Saturday 26

> This repo also contains **Sharks Vs Minnows**, a Roblox tag game. See [`sharks-vs-minnows/`](sharks-vs-minnows/README.md).

A 3D college football game that runs in the browser, inspired by the look and feel of EA Sports College Football 26. It plays full 11-on-11 football: you call plays from a playbook, read the coverage, throw to receivers, run the ball, and play defense, with downs, a game clock, special teams and college overtime.

Everything you see is generated in code at load time. That covers the painted field, uniforms with numbers and nameplates, helmets, the stadium bowl, a 30,000-person crowd, lights and the video board. No image files are needed, so the game is a single HTML file.

## Play it

Open `dist/index.html` in a recent desktop browser (Chrome, Edge, Firefox or Safari). It is fully self-contained, so you can double-click it, with no server or install. A gamepad works if one is plugged in.

## Controls

| Action | Keyboard | Gamepad |
| --- | --- | --- |
| Move | WASD / arrow keys | Left stick / d-pad |
| Sprint | Shift | RT |
| Snap the ball | Space | A / ✕ |
| Throw | 1–5 or click the icon above a receiver. Tap for a touch pass, hold for a bullet | Face button shown on the receiver's icon (✕ ○ □ △ R1) |
| Juke / stiff-arm | E / F | B / X |
| Dive (ball carrier) or diving tackle (defense) | Space | A |
| Switch defender | Tab or Q | B |
| Timeout (between plays) | T | View / Back |
| Pause · mute · controls | Esc · M · H | Start |

Play-call screens take arrow keys and Enter, a click, or the d-pad and A. Field goals, punts and kickoffs you kick yourself use a meter: press Space when the needle is in the green.

## What's in the game

- **Teams:** eight fictional schools, each with its own colors, helmet logo, painted end zones and ratings. You can play a home or road game.
- **Playbook:** ten offensive plays across Shotgun, Singleback, I-Form and Pistol formations, including quick game, verticals, play action and runs. Six defensive calls: Cover 2, Cover 3, Quarters, Cover 1, Cover 0 Blitz and Fire Zone. Every play card shows its play art.
- **Simulation:** offensive linemen block, and pass rushers shed blocks over time. Receivers run routes, and man and zone defenders react to them. Passes are led to the receiver with accuracy that drops under pressure and on deep throws. Tackling accounts for angles, jukes and stiff-arms, and defenders dive from a step away.
- **Rules:** downs and distance, an accelerated game clock with runoff, timeouts, safeties, touchbacks, punts with fair catches and returns, field goals and PATs, halftime with the second-half kickoff, and college overtime from the 25.
- **Presentation:** broadcast camera behind the play, a score bug, the blue line of scrimmage and yellow first-down line, a chain crew, and banners for first downs, sacks and touchdowns. Also a touchdown celebration camera, a live video board, LED ribbon boards, a crowd that reacts to big plays, and synthesized crowd noise, whistles, hits and a drumline.
- **Look:** sculpted players with shoulder pads, gloves, cleats, wrist tape and mesh-fabric jerseys; clear-coated helmets; a crowd of shaped fans who throw their arms up and flash phones on big plays; steel roofs with hung light rigs; turf with mowing stripes that change with the viewing angle; sun or stadium-light shadows and neutral, broadcast-style color. Kickoff can be at noon, dusk or night.
- **Settings:** quarter length (3, 5 or 8 minutes), four difficulty levels, and High, Medium or Low graphics. Resolution also adjusts automatically if the frame rate drops.

## Build from source

```bash
npm install
npm run build
```

This writes two files:

- `dist/index.html`: fully self-contained, with three.js bundled in. Works offline.
- `dist/artifact.html`: the same game, loading three.js from jsDelivr through an import map (smaller, for hosting).

Source lives in `src/`:

| File | What it does |
| --- | --- |
| `main.js` | Boot, world setup, frame loop |
| `game.js` | Possession, downs, clock, scoring, special teams, CPU play-calling |
| `sim.js` | The 22-player simulation: blocking, routes, coverage, passing, tackling, kicks |
| `player-model.js` | Articulated player model and procedural animation |
| `stadium.js` | Bowl, crowd, light rigs, video board, ribbon boards, sidelines |
| `field.js` | Turf, paint, goalposts, pylons, broadcast lines, chains |
| `textures.js` | Every procedural texture: field paint, jerseys, helmets, ball, grass detail |
| `graphics.js` | Renderer, post-processing, time-of-day lighting |
| `camera.js` | Broadcast, kick, celebration and title cameras |
| `ui.js`, `style.css` | Title menu, score bug, play-call cards, banners, overlays |
| `input.js` | Keyboard, gamepad and touch |
| `audio.js` | Synthesized stadium audio |
| `data.js` | Teams, rosters and the playbook |

Team names, logos and players are fictional. This project isn't affiliated with EA Sports, the NCAA or any school.
