# Working title: SPIRE OF MERCY (Arcane Ascension x Undertale-style)

Engine: Godot 4.5.1 (GDScript). 2D, 640x480 base resolution, pixel-art, nearest filtering.
Exe: see memory `godot_executable_path` (not on PATH).

> Lore caveat: Arcane Ascension (Andrew Rowe) names below are from memory of book 1
> (Sufficiently Advanced Magic): Serpent Spire, Corin Cadence, Mirage, mage classes/affinities,
> the Spire's themed floors and guardians. VERIFY every proper noun against the books before
> shipping. Keep the story set in an original corner of the world (a different Spire climber)
> so we are not retelling canon and can't contradict it.

---

## 1. Pitch

You are a young climber who enters a Spire (a magical tower of themed floors) to earn a
mage class. In the Spire, every guardian/creature "fight" can be won by KILLING (gains
power/levels, matches the series' power-progression fantasy) or by SPARING (understanding
the creature's magic). The twist on Undertale: in Arcane Ascension, power comes from
*attunement and understanding of magic*, so the "Mercy" route is literally the
**study route** - you learn a creature's spell by solving its bullet pattern, and unlock
a class/spell from it without violence.

Core fantasy: "Ascend by understanding, not by conquering."

## 2. Pillars
1. Bullet-hell dodge combat where each enemy's pattern IS its magic (readable, learnable).
2. Mercy/Study route as a real alternative progression (spells earned by sparing).
3. Funny, warm, slightly melancholy dialogue; every floor has a theme and a mood.
4. Small, finishable: 5 floors + boss, ~2-3 hours, 3 endings.

## 3. Mapping Undertale -> Arcane Ascension

| Undertale | This game |
|---|---|
| FIGHT | **Strike** - timing bar, physical/spell damage; raises "Ruthless" counter |
| ACT | **Study** - observe, cast-test, talk; each enemy has 3-4 study steps |
| ITEM | **Pack** - potions, spirit tonic, food |
| MERCY | **Release** - available when enemy is Understood (study meter full) |
| Soul (red heart) | **Mana Core** - you dodge as a glowing core; mode changes per magic type |
| LV / EXP | **Rank / Essence** - kill = Essence (stats); spare = Insight (spells/class) |
| Monsters | Spire creatures, constructs, rival climbers, guardians |
| Genocide/Pacifist | **Conqueror / Scholar / Muddle-through** endings |

### Soul modes (one per magic flavor, introduced one per floor)
- Standard (free move)
- Gravity/Earth (platform-ish, jump)
- Bind/Chain (moves only on a grid/rail)
- Mirror (inputs inverted or you control a duplicate)
- Time (bullets rewind; dodge a telegraphed echo)
- Blue/Orange-style rule bullets: "Still" (hurts if you move) and "Flow" (hurts if you stop)

## 4. Story outline (original, set in the Spire)
- Prologue: Village at the Spire's base. Tutorial attunement ceremony; you get a blank Mana Core.
- Floor 1 - **Verdant Floor** (Nature magic): slimes, thorn sprites. Teaches Study/Release. Guide NPC.
- Floor 2 - **Clockwork Floor** (Artifice/Time): constructs; puzzle rooms; Time soul mode.
- Floor 3 - **Mirror Hall** (Illusion): doppelgangers, rival climber appears (recurring character).
- Floor 4 - **Drowned Archive** (Water/Knowledge): ghost scholars; lore dumps; Bind mode.
- Floor 5 - **The Heart Floor** (Fear/Life): boss = the Spire's Guardian, who tests *why* you climb.
- Endings: Scholar (spared all, guardian becomes your teacher), Conqueror (killed, power but
  hollow Spire), Muddle (mixed; bittersweet). Rival's fate depends on route.
- Fourth-wall/meta moments: the Spire "remembers" earlier runs (save-file memory, like Undertale).

## 5. Systems design

### Battle flow (state machine)
`ENEMY_INTRO -> PLAYER_MENU -> (STRIKE | STUDY | PACK | RELEASE) -> ENEMY_DIALOGUE -> DODGE_PHASE -> PLAYER_MENU ...`
Win: enemy HP 0 (Strike) or Released. Lose: Core HP 0 -> checkpoint retry with softer option.

### Enemy data (Resource-driven)
`EnemyData.tres`: name, hp, study_steps[] (text + effect on mood), mood_threshold,
patterns[] (list of PatternData), flavor lines, kill_reward, spare_reward (spell id), soul_mode.

### Bullet patterns
- Patterns are small GDScript/Resource "sequencers": spawn function + params + duration.
- Bullet pool (reuse nodes), types: straight, aimed, sine, orbit, spawner-bullet, laser (telegraph + fire).
- Box (arena) resizable per attack. Player hitbox tiny, invulnerability frames after hit.
- Authoring helper: `PatternPlayer` scene with debug button to loop one pattern.

### Overworld
- Top-down grid-free movement, `CharacterBody2D`, tilemap rooms, interact with Z/Enter.
- Room transitions, NPC dialogue, save points ("Attunement Stones" - restore HP, save).
- Random encounters OFF; encounters are visible (nicer for Mercy design).

### Dialogue
- Lightweight custom typewriter textbox (Undertale-style blips per character voice) OR the
  Dialogue Manager addon (decide in M1). Custom is ~100 lines and keeps full control.
- Text script format: plain `.dlg` / JSON with speaker, text, speed, shake, portrait tags.

### Progression
- Kill -> Essence -> HP/ATK/DEF. Spare -> Insight -> unlock spells usable in Strike/Study
  (e.g. Thorn Bind, Rewind, Mirror Step). Spells also gate some puzzles.
- Track hidden counters: `kills`, `spares`, `studies_completed`, `rival_choices`.

### Save/Load
- `user://save.json`: room, hp, inventory, counters, flags, spells. Autoload `SaveSystem`.

## 6. Technical architecture (Godot 4.5.1)

```
res://
  autoload/   GameState.gd, SaveSystem.gd, Audio.gd, Dialogue.gd, SceneRouter.gd
  battle/     BattleScene.tscn, BattleMenu, Arena, Bullet.tscn, BulletPool.gd,
              soul/ (SoulStandard, SoulGravity, SoulBind, SoulMirror, SoulTime)
  patterns/   *.tres / *.gd
  enemies/    data/*.tres, sprites/
  overworld/  Player.tscn, Room_*.tscn, NPC.gd, Interactable.gd, Trigger.gd
  ui/         Textbox.tscn, MenuButton, HPBar
  data/       items.tres, spells.tres, dialogue/
  art/ audio/ fonts/
```
- Autoloads for global state; signals for decoupling (`battle_finished(result)`).
- Pixel-perfect: stretch mode `canvas_items`, scale integer, 2D snap.
- Input map: move (arrows/WASD), confirm (Z/Enter), cancel (X/Shift), menu (C/Ctrl).
- Testing: headless smoke test script that loads each room + runs each pattern for N frames
  (note: headless runs share exe name with editor - kill by PID only).

## 7. Milestones

| M | Goal | Done when |
|---|---|---|
| M0 | Project scaffold, input map, resolution, git-less folder structure | Blank room runs |
| M1 | Textbox + dialogue + overworld player + 1 room + NPC | Can walk and talk |
| M2 | Battle shell: menu, arena, Core movement, HP, one bullet pattern | Win/lose loop works |
| M3 | Study/Release/Strike logic + EnemyData resources + 2 Floor-1 enemies | Spare and kill both finish |
| M4 | Floor 1 full: 3 rooms, 3 enemies, mini-boss, save point, Insight reward | Playable vertical slice |
| M5 | Soul modes 2-3, Floors 2-3 | Each soul mode has 2 patterns |
| M6 | Floors 4-5, boss, endings, rival arc | Full playthrough |
| M7 | Polish: audio, screen shake, juice, menus, options, bugs | Release candidate |

**Vertical slice target (M4) is the go/no-go point** - judge whether Study-as-spell-learning
feels fun before building more floors.

## 8. Art & audio approach
- Art: placeholder shapes/colour blocks first; replace with pixel art (hand-drawn, AI-assisted
  concept, or asset packs with proper license). Limited palette per floor for cohesion.
- Audio: chiptune/tracker music per floor; text blips per character; royalty-free/CC0 as
  placeholders. Credit all sources.
- Fonts: pixel font with OFL license.

## 9. Risks
- Lore accuracy / IP: Arcane Ascension is Andrew Rowe's property. Fan game = non-commercial,
  credit the author, don't use book text/art; consider asking permission if ever distributing widely.
- Undertale-likeness: avoid copying its characters/music/jokes; mechanics are fair game, content must be original.
- Scope creep: patterns and writing are the real cost. Cap at ~12 enemies + 1 boss.
- Dodge design balance: playtest each pattern; add accessibility (reduced flashing, hit-assist, skip).

## 10. Open decisions (need your call)
1. Protagonist: original climber (recommended) vs. a canon character like Corin?
2. Tone: comedic-warm (Undertale) vs. more serious LitRPG?
3. Dialogue: custom textbox vs. Dialogue Manager addon?
4. Art source: hand-made, asset packs, or AI-assisted placeholders?
5. Length: slice-only demo (Floor 1) first, or commit to all 5 floors?
6. Is the rival / "Spire remembers you" meta-mechanic in scope?

## 11. Immediate next steps
1. Answer open decisions 1, 3, 5.
2. Run M0: create Godot project, input map, folder structure.
3. Build M1+M2 in parallel (textbox, and a single dodge pattern) as the earliest fun check.
