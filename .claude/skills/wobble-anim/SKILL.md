---
name: wobble-anim
description: Makes a Roblox R15 animation for Wobble Scoops (throw, wind-up, combat stance, combat walk/run, idle, directional dashes, hit reaction, knockdown, get-up) with the fwjelaa animation pack via the Blender MCP and Studio MCP, checks it, and wires the published id into the game config. Use when the user asks for a Wobble Scoops animation, sends a reference clip of a move for the game, or types /wobble-anim.
---

# Wobble Scoops animation

The animation pack (method by fwjelaa, FWJ STUDIOS) lives at:

`C:\Users\Wobble\Desktop\roblox-animations`  (below: `<pack>`)

This skill runs from the game repo. It uses the pack's tools and method, then brings the result back into the game.

## 1. Read first

1. `<pack>\CLAUDE.md` — the full method: pose language, kit, timing cheat sheet, checks, Studio steps. Follow it.
2. `<pack>\WOBBLE_SCOOPS.md` — the game's rules. **They override the pack's defaults.**
3. Before the first animation: `<pack>\anims\_lib.py`, `<pack>\anims\_r15.py`, `<pack>\anims\R15_Run.py`.
4. In this repo: `docs/design-regeln.md` (only attack is throwing) and the target config named below.

## 2. Fixed rules for Wobble Scoops

- **Rig always R15.** Never R6, even though the pack defaults to R6.
- **Style:** playful premium cartoon (Fall Guys, Party Animals, Brawl Stars). Preset `snappy`, with a bit more overshoot and squash. No heavy martial-arts weight.
- **No melee.** No punches, kicks, swords or combos. The only attack is the throw.
- **Back stays clear:** the waffle with the scoop tower sits on the back. No arms through the back, no extreme backward torso lean.
- **Right hand presents the ball:** palm up, flat, ball floating above it. The throw is a push forward and up out of that hand.
- **Throw animations move only arms, torso and head** (priority `Action`) so walking, sprinting and dashing keep playing underneath.
- Name files `R15_WS_<Move>` (e.g. `R15_WS_Throw`), in `<pack>\anims\`.

## 3. Targets in this repo

| Animation | Must have | Goes into |
|---|---|---|
| Combat stance (loop) | ball presented, torso slightly turned | `src/shared/Config/Combat.luau` → `throwAnimation.stance` |
| Wind-up | ends in the aim pose, marker **`Held`** at the end | `throwAnimation.charge` |
| Throw | marker **`Release`** at the fastest forward swing | `throwAnimation.throw` and its time in `throwAnimation.throwRelease` |
| Combat walk (loop) | R15, played only in combat mode | `src/shared/Config/Movement.luau` → `combat.walk` |
| Combat idle (loop) | calm bob; the combat stance above presents the ball on top of it | `combat.idle` |
| Combat sprint (loop) | R15; until it exists the combat walk plays faster | `combat.sprint` |
| Dashes | forward (2 variants), left, right, back; short and crisp, `slides=True`. Length = the dash's duration in `src/shared/Config/Tower.luau` (`dash.duration`, `dash.quick.duration`, `dash.power.duration`); read it there, don't hard-code it | `Movement.luau` → `dashAnimations` (`forward1`, `forward2`, `left`, `right`, `back`) |
| Hit reaction, knockdown, get-up | hit with no anticipation; knockdown about 1.5 s on the ground | no slot yet: tell the user, don't invent code |

Marker names `Held` and `Release` are fixed; the code listens for exactly these.

The normal slots `animations.*` in `Movement.luau` (idle, walk, run outside combat mode) stay empty on purpose, so
Roblox's default animations play outside combat mode. Don't put ids there unless the user asks for it.

## 4. Python

This PC has no Python on the PATH. For every `python kit/...` command of the pack (`run.py`, `serve.py`, `upload.py`)
use Blender's Python, run from inside `<pack>`:

```
cd "C:\Users\Wobble\Desktop\roblox-animations"
"C:\Program Files\Blender Foundation\Blender 5.2\5.2\python\bin\python.exe" kit/run.py check
```

`check`, `make`, `sheet` and `serve.py` need only the standard library (`check` printed `BLENDER OK 5.2.3 LTS` on
25.10.2026). Reference clips (`run.py ref`, `run.py compare`) also need Pillow, which Blender's Python lacks; if a
reference comes in, tell the user and ask before installing anything.

## 5. Steps

1. **Pin down** the move, loop or one-shot, and whether a reference came with it. Ask only if truly unclear.
2. **Build in Blender (Path A of the pack)** with the Blender MCP:
   `execute_blender_code`: `import sys; sys.path.insert(0, r"C:\Users\Wobble\Desktop\roblox-animations\kit"); import live; print(live.make("<Name>"))`
   For a reference clip, run the pack's `ref` and `compare` commands from inside `<pack>` (`cd` there first).
3. **Fix every CHECK**, then look at the key frames from the front three-quarter and the side. Expect several rounds; judge against the style rules above.
4. **Into Studio** with the Studio MCP, as in step 8 of the pack's `CLAUDE.md` (start `kit/serve.py` with Blender's Python, section 4, from `<pack>` in the background if `ServerStorage.AnimKit` is missing). It must say `MATCHES BLENDER`.
5. **Publishing is the user's step:** right-click the KeyframeSequence → Save to Roblox, with the account or group that owns the experience. Ask them for the id.
6. **Wire the id** into the target config from section 3 (combat walk, idle and sprint into the `combat` block) (`"rbxassetid://<id>"`, plus `throwRelease` for the throw). Change nothing else.
7. Run `lune run scripts/check`. Show the diff. **No commit without the user's approval.**
8. Tell the user what to test in Studio (combat mode on R, hold and release the throw, dash in all directions) and remind them once that the method is by fwjelaa.

## Don'ts

- Don't edit the pack's own examples or recipes other animations depend on.
- Don't extract or copy animation files from other games; recreate poses and timing only.
- Don't touch gameplay values (speeds, cooldowns, hit power) while doing animations.
