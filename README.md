<div align="center">

# 🔥 EMBER CRYPT 🔥

**A torchlit top-down pixel roguelike made in Godot 4. Every pixel is drawn in code.**

[![Play in browser](https://img.shields.io/badge/%E2%96%B6%20PLAY%20IN%20BROWSER-jaigod.github.io%2Fember--crypt-ff7a1a?style=for-the-badge&labelColor=1a0d08)](https://jaigod.github.io/ember-crypt/)

[![Godot 4.3](https://img.shields.io/badge/Godot-4.3-478cbf?style=flat-square&logo=godotengine&logoColor=white)](https://godotengine.org)
![GDScript](https://img.shields.io/badge/GDScript-100%25-355570?style=flat-square)
![Assets](https://img.shields.io/badge/image%20%26%20audio%20files-0-c1361a?style=flat-square)
[![Build & Deploy](https://github.com/JaiGod/ember-crypt/actions/workflows/deploy.yml/badge.svg)](https://github.com/JaiGod/ember-crypt/actions/workflows/deploy.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-ffd65c?style=flat-square)](LICENSE)

</div>

---

> Your torch is your life clock. It burns down as you explore, and the crypt rebuilds itself every run.
> Gather **embers**, light **braziers**, find the stairs, and survive to the **Ashen King** on floor 10.
> **Death is permanent.**

## ✨ Features

| | |
|---|---|
| 🗺️ **Procedural floors** | Rooms and 2-tile corridors are generated fresh each floor, linked as a spanning tree with extra loops and pillars for cover. |
| 🕯️ **Torch-light radius** | Light shrinks as fuel burns. Lighting is computed per tile with line of sight, and explored areas stay as a cold blue memory. When the torch runs out, the dark starts to hurt. |
| ⚔️ **Melee + dash** | Arc-based melee with hit-stop, knockback and screen shake. The dash gives brief invulnerability. |
| 🗡️ **4 weapons** | **Ember Sword** (fast arc), **Cleaver Axe** (huge sweep), **Bone Spear** (long thrust), **Cinder Wand** (bolts that burn a little fuel). |
| 👹 **5 enemy AIs** | **Skitter** swarms erratically · **Ember Ooze** hops and splits · **Bone Knight** telegraphs a lunge · **Wisp** keeps its distance and fires orbs · **Shade** blinks behind you and steals fuel. |
| 🔥 **Bosses** | **The Cinder Warden** (floor 5) and **The Ashen King** (floor 10). Each has ring bursts, a telegraphed charge, summons and spiral streams, and gets faster when enraged. |
| 🎁 **Loot & blessings** | Chests, gold, hearts and weapon drops. Between floors you choose 1 of 3 blessings (10 total). |
| 💀 **Permadeath** | Every run ends with a summary of floor, kills, gold, time, weapon and score. Your best score and deepest floor are saved. |
| 📱 **Plays anywhere** | Keyboard + mouse, or touch with a virtual stick, ATK and DASH buttons, and auto-aim. Portrait phones switch to a taller base resolution. |
| 🔊 **Synth audio** | 19 sound effects synthesised into PCM `AudioStreamWAV` buffers at startup. Toggle with **M**. |

## 🎮 Controls

| Action | Keyboard / Mouse | Touch |
|---|---|---|
| Move | `WASD` / arrow keys | Left thumb-stick (touch anywhere on the left side) |
| Attack | Left click or `J` (aims at the mouse) | **ATK** button (auto-aims at the nearest foe) |
| Dash | `Space` / `Shift` / right click | **DASH** button |
| Pause | `Esc` / `P` | ⏸ icon |
| Sound | `M` | 🔈 icon |
| Minimap | `Tab` | map icon |
| Pick blessing | `1` `2` `3` | Tap a card |

## 🛠️ Tech stack

- **Engine:** Godot 4.3 (GL Compatibility renderer), GDScript
- **Art:** 100% procedural. Tiles, sprites, weapons, bosses, particles and UI are all drawn with `draw_rect` / `draw_circle` / `draw_colored_polygon` in `_draw()`. The minimap is a generated `ImageTexture`.
- **Audio:** sounds synthesised in code into `AudioStreamWAV` (square, saw, sine and triangle waves plus filtered noise)
- **CI/CD:** GitHub Actions with the `barichello/godot-ci:4.3` container. It runs a headless **smoke-test bot**, exports Web with **threads off** (no COOP/COEP headers needed) and deploys to **GitHub Pages**. A separate job builds an Android debug APK and attaches it to the `v1.0.0` release.

## 📁 Project structure

```
ember-crypt/
├── project.godot          # 480×270 base, canvas_items stretch, GL Compatibility
├── export_presets.cfg     # Web (no threads) + Android presets
├── main.tscn              # Game (Node2D) → Cam, Sfx, UI/HUD
├── game.gd                # state machine, player, enemy AI, bosses, lighting, world drawing
├── gen.gd                 # procedural rooms + corridors generator
├── hud.gd                 # HUD, menus, upgrade cards, summary, touch controls, minimap
├── sfx.gd                 # synthesised sound effects
├── site/index.html        # landing page (the Web export goes in /play/)
└── .github/workflows/deploy.yml
```

## 🚀 Run locally

1. Install [Godot 4.3](https://godotengine.org/download).
2. `git clone https://github.com/JaiGod/ember-crypt && cd ember-crypt`
3. Open `project.godot` in the editor and press **F5**, or run `godot --path .` from the command line.
4. Headless smoke test: `godot --headless --fixed-fps 60 --quit-after 60000 -- --smoke`. It prints `SMOKE OK` when the bot finishes a full run.
5. Web build: `godot --headless --export-release "Web" build/play/index.html`, copy `site/index.html` to `build/`, then serve `build/` with `python3 -m http.server`.

Dev hook: `.../play/?floor=5` starts a run directly on floor 5 (useful for testing bosses).

## 📓 Development log

**Day 1: core loop and the torch idea.** I wanted one mechanic that is both the timer and the vision system. The torch radius is `26 + fuel × 0.78` px with a two-sine flicker. Fuel burns at 1.35/s, embers give +30, and at zero fuel you take 1 damage every 2.2 s. That forces you to keep moving without being instantly lethal.

**Lighting without shaders.** Each frame, every light (torch, lit braziers and glowing projectiles) walks the tiles inside its radius and does a Bresenham line-of-sight test. The result goes into a per-tile `lightmap`, which also marks tiles as *seen*. Tiles are tinted from cold blue (remembered) to warm orange (lit), so the map shows where you've been without revealing what's lurking there. I only reset the tiles lit last frame (`lit_idx`), so the cost stays proportional to the light area, not the map size.

**Dungeon generation.** Rejection-sampled rooms with a 2-tile margin. Each room joins its nearest earlier room, which gives a tree, and then two random extra corridors add loops so it doesn't feel linear. Corridors are 2 tiles wide because 1-tile corridors made fights with the knight's lunge feel unfair. Stairs go in the room farthest from the spawn.

**Enemy AI.** Every enemy has a single `mode` + timer state machine. The Bone Knight and the boss charge both *telegraph* with a red line before committing, which made deaths feel fair in playtests. The Shade picks a blink spot around the player that is floor, clear and in line of sight, so it never teleports into walls.

**Bug: frozen boss.** In the browser, the Cinder Warden just sat there. A headless trace script showed `Trying to assign an array of type "Array" to a variable of type "Array[int]"`. A typed array assigned from a ternary (`[..] if rage else [..]`) loses its type in Godot 4.3. The fix was a plain untyped array, and the CI smoke test now fails on any `SCRIPT ERROR`.

**Bug: drawing outside `_draw`.** The HUD reused the game's flame-drawing helper, but that helper drew on the *game* node during the *HUD's* draw call. It now takes a target `CanvasItem`.

**Web audio.** `AudioStreamGenerator` doesn't work in Godot 4.3's single-threaded Web build, which plays audio as samples. All sounds are therefore pre-rendered into `AudioStreamWAV` buffers at startup, which take about 50 ms to generate.

**Mobile.** Touch emulation of the mouse is off, so taps and clicks share one button hit-test path (`g.buttons`, rebuilt every HUD draw). Portrait phones switch the base resolution to 360×480 and zoom the camera in so the pixels stay chunky. Upgrade cards size themselves to the screen width.

**Testing.** I used Playwright on the local Web export at 960×540 and at 390×844 with real touch events. That meant zero console errors and no horizontal scroll on the landing page. The headless soak script cycled every weapon through floors 2–10 against live AI.

## 🗺️ Ideas for later
- Endless mode past floor 10, plus a daily seed
- More bosses and elite enemy variants
- Gamepad support

---

<div align="center">

Made by Jaineil Rana (JaKing) · part of [JaiGod](https://github.com/JaiGod)

</div>
