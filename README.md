# Arcane Undertale

A battle prototype in Godot 4.5: an Undertale/Deltarune-style fight system set in the world of
*Arcane Ascension* (a non-canon, non-commercial fan project). You play Corin and fight four opponents.

## Run it

1. Install [Godot 4.5.1](https://godotengine.org/download).
2. Open this folder as a project (or run `godot --path .`).
3. Press F5.

**Controls:** arrows / WASD move, Z / Enter confirm, X / Shift cancel (hold X in a dodge to move slowly). M mutes the sound effects.

## The fights

| Fighter | Gimmick |
|---|---|
| Slime | Warm-up. Rain, bouncing blobs, and a hop-and-smash. |
| Saffron | Chained attacks, a circular blue-heart arena, and a second form with simulacra. |
| Katashi | Fast. Light-based, with rhythmic beam spirals and an Eclipse that hides hazards. |
| Keras | Heavy, readable cuts - until he stops holding back. He cuts through buffs, armor and menu options. |

Corin has FIGHT (timing bar), MAGIC (Haste, Accelerated Computation, Shockwave), ITEM and MERCY.

## Project layout

- `battle.gd` - menus, FIGHT bar, items, shared battle logic.
- `saffron.gd`, `katashi.gd`, `keras.gd` - one attack engine per boss (same interface).
- `overworld.gd`, `game.gd`, `game.tscn`, `pixel_ui.gd` - a shelved overworld prototype; the project boots into `main.tscn` (the battle).
- `assets/` - sprites (Slime, Keras, the SOUL heart) and the generated pixel font.
- `tools/make_pixel_font.py` - generates the pixel font (edit a glyph, re-run).
- `tools/make_sfx.py` - synthesizes the sound effects in `assets/sfx/` (retune a recipe and re-run, or drop in your own .wav).

## Publishing the web build

The site (https://cat32man.github.io/ArcaneUndertale/) is built by `.github/workflows/static.yml` from the zip
`arcaneundertale (1).zip` in the repo root. To update it:

1. In Godot: *Project > Export... > Web > Export Project...* and save as `build/web/index.html` (untick "Export With Debug").
2. Double-click `publish_web.bat` (it zips the export, commits only that zip and pushes). Options: see `tools/publish_web.ps1`
   (`-DryRun` to just check the export, `-NoPush` to commit and push later from GitHub Desktop).

## Developer shortcuts

Run `godot --path . -- <flags>` to jump straight to a screen:
`--enemy=keras`, `--sub=item`, `--dodge`, `--big`, `--allout`, `--attack=<move>` (e.g. `--attack=metronome`).
Keras extras: `--storm` (all-out, next big attack is the Edge Storm), `--gauntlet` (the 1.5 path), `--gx=<x>` (start the path part-way, e.g. `--gx=1000`).

## Credits

Original characters and world: *Arcane Ascension* by Andrew Rowe (this is an unofficial fan project).
Sprites by the project author; all other art is drawn in code.
