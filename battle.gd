extends Node2D
## Prototype battle: Corin vs. Slime. All art is drawn with code (no external assets).
## Controls: arrows/WASD move, Z/Enter confirm, X/Shift cancel.

enum S { SELECT, MENU, SUB, MESSAGE, BAR, SLASH, DODGE, END }

signal fight_over(outcome: String)   # embedded in the overworld: won / spared / fled / lost

const SaffronFight := preload("res://saffron.gd")
const KatashiFight := preload("res://katashi.gd")
const KerasFight := preload("res://keras.gd")
const ENEMIES := [
	{"id": "slime", "label": "Slime", "desc": "Warm-up. 70 HP."},
	{"id": "saffron", "label": "Saffron  (boss)", "desc": "Vae'kes. Two forms. Corin gets +HP, +MANA, +damage."},
	{"id": "katashi", "label": "Katashi  (boss)", "desc": "Visage of light. Extremely fast. Corin gets +HP, +MANA, +damage."},
	{"id": "keras", "label": "Keras  (boss)", "desc": "Slow, but every cut is huge. Wields the Dominion Breaker."},
]

# Persists across scene reloads so "play again" stays on the same enemy.
static var next_enemy: String = ""

const TEXT_BOX := Rect2(40, 195, 560, 140)
const ARENA := Rect2(235, 195, 170, 140)
const SLIME_POS := Vector2(320, 125)   # visual center (popups, slash target)
const SLIME_BASE := Vector2(320, 170)  # bottom-center the sprite sits on
const SLIME_SCALE := 6.0               # 16x16 pixel art -> chunky
const SMASH_R := 28.0                  # smash impact radius (px)
const SMASH_FLOOR_Y := 328.0            # the arena floor the Slime slams into
const SMASH_G := 3600.0                # fall gravity
const SMASH_G_UP := 2200.0             # rebound gravity (slower = floatier bounce)
const SMASH_BODY_H := 38.0
const HOVER_Y := 186.0                # sprite bottom while hovering just above the arena
const BUTTONS := ["FIGHT", "MAGIC", "ITEM", "MERCY"]

# --- tuning ---
const BAR_TRACK_L := 70.0
const BAR_TRACK_R := 570.0
const BAR_TARGET_X := 120.0
const BAR_BASE_SPEED := 430.0
const BAR_PERFECT := 4.0      # px from center for a crit
const BAR_FALLOFF := 70.0     # px from center where damage hits zero-ish
const BAR_MISS_BELOW := 0.25  # mult under this counts as a miss
const DODGE_TIME := 6.0
const SOUL_SPEED := 150.0
const SOUL_SPEED_HASTE := 230.0
const POISON_DMG := 3
const SLIME_MAX_HP := 70
const SAFFRON_MAX_HP := 320
const KATASHI_MAX_HP := 300
const KERAS_MAX_HP := 350
const KERAS_SPARE_AT := 0.4   # at this fraction of HP, Keras spares Corin (phase 2 starts if you keep fighting)
const FORM2_FRAC := 0.4    # Saffron's second form starts when this fraction of his HP is left

const MAGIC := [
	{"id": "haste", "name": "Haste", "cost": 3, "desc": "SOUL moves faster. Lasts 1 FIGHT."},
	{"id": "accel", "name": "Accelerated Computation", "cost": 4, "desc": "FIGHT bar slower/easier. Lasts 2 FIGHTS."},
	{"id": "shock", "name": "Shockwave", "cost": 5, "desc": "Sword slash through the air. Heavy damage."},
]
const ITEMS := [
	{"id": "transference", "name": "Transference Sword", "desc": "Makes Shockwave stronger and cheaper."},
	{"id": "selys", "name": "Selys-Lyann", "desc": "Frost: poisons + slows enemy. Faster bar. Frost Armor (DEF+)."},
	{"id": "draught", "name": "Healing Draught", "kind": "heal", "pct": 0.3, "desc": "Restores 30% of max HP."},
	{"id": "elixir", "name": "Spirit Elixir", "kind": "heal", "pct": 0.7, "desc": "Restores 70% of max HP."},
]

var pixel_font: Texture2D = load("res://assets/font/pixel_font.png")
var heart_tex: Texture2D = _white_copy("res://assets/SOUL/heart.png")   # white so any color can tint it


func _white_copy(path: String) -> Texture2D:
	var img: Image = (load(path) as Texture2D).get_image()
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var px: Color = img.get_pixel(x, y)
			img.set_pixel(x, y, Color(1, 1, 1, px.a))
	return ImageTexture.create_from_image(img)


# --- player ---
var hp: int = 40
var max_hp: int = 40
var mp: int = 20
var max_mp: int = 20
var atk: int = 10
var stock: Dictionary = {"draught": 4, "elixir": 1}   # consumables left this battle
var weapon: String = "plain"   # plain / transference / selys
var haste_left: int = 0
var accel_left: int = 0

# --- enemy ---
var embedded: bool = false      # true when launched from the overworld (no enemy-select screen)
var outcome: String = ""
var enemy_id: String = "slime"
var enemy_name: String = "SLIME"
var enemy_max: int = SLIME_MAX_HP
var enemy_hp: int = SLIME_MAX_HP
var spare_frac: float = 0.3
var poison_dmg: int = POISON_DMG
var frost_note: bool = false
var armor_cut: int = 0          # turns Frost Armor stays cut (Keras)
var menu_cut: int = -1          # menu button index cut away for a turn (Keras)
var sever_note: bool = false
var items_cut: bool = false     # Keras phase 2: the healing half of the ITEM button is gone
var blade_dull: int = 0         # turns the sword stays dulled (FIGHT damage halved)
var dull_note: bool = false
var mana_note: int = 0
var menu_note: bool = false
var bar_mult: float = 1.0   # >1 = this enemy makes the FIGHT bar faster (Katashi is fast)
var saf = null
var select_idx: int = 0
var poison_turns: int = 0
var enemy_alive: bool = true
var enemy_shake: float = 0.0
var enemy_fade: float = 1.0

# --- ui state ---
var state: int = S.SELECT
var menu_idx: int = 0
var sub_kind: String = ""
var sub_idx: int = 0
var menu_text: String = "* A Slime blocks the way."
var msg_queue: Array = []
var msg_cb: Callable
var cur_msg: String = ""
var msg_shown: float = 0.0
var box: Rect2 = TEXT_BOX
var t_anim: float = 0.0
var popups: Array = []   # {text, pos, t, color}
var shake: float = 0.0   # screen-shake trauma 0..1

# --- bar ---
var bar_mode: String = "fight"
var bar_x: float = BAR_TRACK_R
var bar_result: float = 0.0
var bar_label: String = ""
var bar_stopped: bool = false
var bar_jitter: float = 1.0

# --- slash ---
var slash_t: float = 0.0
var slash_mult: float = 0.0
var slash_kind: String = "fight"

# --- dodge ---
var dodge_t: float = 0.0
var dodge_len: float = DODGE_TIME
var slime_away: bool = false   # Slime is airborne (off-screen) during a smash
var sm_pos: Vector2 = Vector2(320, 186)   # smash body: bottom-center of the sprite
var sm_vy: float = 0.0
var smash_lock: float = 0.3
var smash_drift: float = 0.0
var return_dist: float = 1.0
var smash_left: int = 0
var smash_phase: String = ""
var smash_t: float = 0.0
var smash_wait: float = 0.9
var pattern: String = "rain"
var spawn_timer: float = 0.0
var bullets: Array = []   # {pos, vel, r, kind}
var soul: Vector2 = ARENA.get_center()
var iframes: float = 0.0
var end_text: String = ""


var slime_idle: Array[Texture2D] = []
var slime_jump: Array[Texture2D] = []   # [0] = in air, [1] = squashed (takeoff/landing)
var slime_ball: Texture2D
var hop_t: float = -1.0
var idle_hop_timer: float = 3.0


func _ready() -> void:
	randomize()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_init_sfx()
	for n in ["SlimeIdle1", "SlimeIdle2"]:
		slime_idle.append(load("res://assets/Slime/%s.png" % n))
	for n in ["SlimeJump1", "SlimeJump2"]:
		slime_jump.append(load("res://assets/Slime/%s.png" % n))
	slime_ball = load("res://assets/Slime/SlimeBall.png")
	# dev shortcuts:  godot --path . -- --enemy=katashi --sub=item
	if not embedded:
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--enemy="):
				next_enemy = arg.substr(8)
	if next_enemy != "":
		setup_enemy(next_enemy)
		for arg in (OS.get_cmdline_user_args() if not embedded else PackedStringArray()):
			if arg.begins_with("--sub="):
				sub_kind = arg.substr(6)
				sub_idx = 0
				state = S.SUB
			if arg == "--big" and saf != null:
				saf.turns_since_big = 99   # next boss turn is the big attack
			if arg == "--allout" and enemy_id == "keras":
				saf.begin_allout()
				items_cut = true
			if arg == "--storm" and enemy_id == "keras":   # all-out Keras, next big attack = Edge Storm
				saf.begin_allout()
				saf.turns_since_big = 99
				saf.big_runs = 1
				items_cut = true
			if arg.begins_with("--gx=") and saf != null and enemy_id == "keras":
				saf.dev_gx = float(arg.substr(5))
			if arg == "--gauntlet" and enemy_id == "keras":   # skip ahead: Keras has spared you, you swing
				saf.begin_spared()
				saf.begin_gauntlet()
			if arg == "--dodge":
				start_dodge()
				for a2 in OS.get_cmdline_user_args():
					if a2.begins_with("--attack=") and saf != null:   # force one move: --attack=spiral
						saf.phase = "chain"
						saf.queue = [a2.substr(9)]
						saf.cur = {}
						saf.gap = 0.0


func setup_enemy(id: String) -> void:
	enemy_id = id
	next_enemy = id
	if id == "saffron":
		enemy_name = "SAFFRON"
		enemy_max = SAFFRON_MAX_HP
		spare_frac = 0.12
		poison_dmg = 22   # Saffron is weak to spirit-frost
		max_hp = 90
		max_mp = 45
		atk = 18
		bar_mult = 1.0
		saf = SaffronFight.new(self)
		menu_text = "* Saffron regards you calmly. His hand rests on a sword."
	elif id == "keras":
		enemy_name = "KERAS"
		enemy_max = KERAS_MAX_HP
		spare_frac = 0.15
		poison_dmg = 10
		max_hp = 90
		max_mp = 45
		atk = 18
		saf = KerasFight.new(self)   # (lore: as fast as Katashi; the slow, readable pace is a balance choice)
		menu_text = "* Keras stands still. The Dominion Breaker hums, and the air near it comes apart."
	elif id == "katashi":
		enemy_name = "KATASHI"
		enemy_max = KATASHI_MAX_HP
		spare_frac = 0.15
		poison_dmg = 10
		max_hp = 90
		max_mp = 45
		atk = 18
		bar_mult = 1.2   # he is hard to hit
		saf = KatashiFight.new(self)
		menu_text = "* Katashi is already looking at you. You didn't see him move."
	else:
		enemy_name = "SLIME"
		enemy_max = SLIME_MAX_HP
		spare_frac = 0.3
		poison_dmg = POISON_DMG
		max_hp = 40
		max_mp = 20
		atk = 10
		bar_mult = 1.0
		saf = null
		menu_text = "* A Slime blocks the way."
	weapon = "selys"   # Corin starts with Selys-Lyann drawn
	armor_cut = 0
	menu_cut = -1
	items_cut = false
	blade_dull = 0
	dull_note = false
	mana_note = 0
	sever_note = false
	menu_note = false
	hp = max_hp
	mp = max_mp
	stock = {"draught": 4, "elixir": 1}
	enemy_hp = enemy_max
	state = S.MENU


func is_boss() -> bool:
	return saf != null


# ---------------------------------------------------------------- sound
# Effects are WAVs in assets/sfx (generated by tools/make_sfx.py). `sfx("name", volume)` plays one;
# a missing file is silently skipped. M toggles mute.
const SFX_NAMES := ["blip", "select", "cancel", "text", "bar_stop", "slash", "hit", "crit", "miss", "shock",
	"cast", "heal", "hurt", "spare", "flee", "win", "lose", "impact", "thump", "throw", "stab", "swoosh",
	"powerup", "flash", "fire", "pillar", "beam", "dash", "cut", "cut_big", "sever", "draw", "dim", "boing"]
const SFX_VOLUME := 0.45   # master level for all effects
var sfx_players: Array = []
var sfx_cache: Dictionary = {}
var muted: bool = false
var slash_sfx_done: bool = false
var text_blip_at: int = 0


func _init_sfx() -> void:
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		sfx_players.append(p)
	for n: String in SFX_NAMES:
		var path: String = "res://assets/sfx/%s.wav" % n
		if ResourceLoader.exists(path):
			sfx_cache[n] = load(path)


func sfx(sound: String, vol: float = 1.0) -> void:
	if muted or not sfx_cache.has(sound):
		return
	var chosen: AudioStreamPlayer = sfx_players[0]
	for p: AudioStreamPlayer in sfx_players:
		if not p.playing:
			chosen = p
			break
	chosen.stream = sfx_cache[sound]
	chosen.volume_db = linear_to_db(clampf(vol * SFX_VOLUME, 0.0001, 1.0))
	chosen.play()


func add_shake(amount: float) -> void:
	shake = minf(1.0, shake + amount)


func rumble(level: float) -> void:
	shake = maxf(shake, level)


func hurt(dmg: int) -> bool:
	if iframes > 0.0:
		return false
	var d: int = maxi(1, dmg - defense())
	hp = maxi(0, hp - d)
	iframes = 1.0
	add_shake(0.4)
	sfx("hurt")
	add_popup(str(d), soul + Vector2(0, -16), Color(1, 0.4, 0.4))
	return true


func start_hop() -> void:
	hop_t = 0.0
	if state == S.DODGE:
		sfx("boing", 0.5)


func defense() -> int:
	if armor_cut > 0:
		return 0
	return 4 if weapon == "selys" else 0


func sever() -> void:
	# the Dominion Breaker cuts through non-physical things: buffs and the Frost Armor
	haste_left = 0
	accel_left = 0
	armor_cut = 3
	sever_note = true
	add_popup("SEVERED", soul + Vector2(0, -30), Color(0.9, 0.6, 1.0))
	sfx("sever")


func dull_blade() -> void:
	# Edge Breaker: the cut takes the edge off whatever sword Corin holds
	blade_dull = 3
	dull_note = true
	add_popup("DULLED", soul + Vector2(0, -30), Color(1.0, 0.8, 0.4))
	sfx("sever")


func drain_mp(amount: int) -> int:
	# Mana Breaker: burns some of Corin's mana (the keras engine then detonates it at the spot)
	var lost: int = mini(amount, mp)
	mp -= lost
	mana_note += lost
	add_popup("-%d MP" % lost, soul + Vector2(0, -30), Color(0.5, 0.7, 1.0))
	sfx("sever", 0.8)
	return lost


func cut_menu() -> void:
	# ...and through the menu itself: MAGIC or ITEM is cut away until Corin's next action
	menu_cut = [1, 2].pick_random()
	menu_note = true
	sfx("cut_big")


func spareable() -> bool:
	if enemy_id == "keras" and saf.mode == "spared":
		return true   # he spared you; you can return the gesture
	return enemy_alive and enemy_hp <= int(float(enemy_max) * spare_frac)


func shock_cost() -> int:
	return 4 if weapon == "transference" else 5


# ---------------------------------------------------------------- input
func _input(ev: InputEvent) -> void:
	var e := ev as InputEventKey
	if e == null or not e.pressed or e.echo:
		return
	var k: int = e.physical_keycode
	var confirm: bool = k == KEY_Z or k == KEY_ENTER or k == KEY_SPACE
	var cancel: bool = k == KEY_X or k == KEY_SHIFT
	var dx: int = int(k == KEY_RIGHT or k == KEY_D) - int(k == KEY_LEFT or k == KEY_A)
	var dy: int = int(k == KEY_DOWN or k == KEY_S) - int(k == KEY_UP or k == KEY_W)
	if k == KEY_M:
		muted = not muted
		return
	if state == S.MENU or state == S.SUB or state == S.SELECT:
		if (state == S.MENU and dx != 0) or (state != S.MENU and dy != 0):
			sfx("blip", 0.7)
		elif confirm:
			sfx("select")
		elif cancel and state == S.SUB:
			sfx("cancel")

	match state:
		S.MENU:
			if dx != 0:
				menu_idx = posmod(menu_idx + dx, BUTTONS.size())
			elif confirm:
				_menu_select()
		S.SUB:
			var n: int = _sub_list().size()
			if dy != 0:
				sub_idx = posmod(sub_idx + dy, n)
			elif cancel:
				state = S.MENU
			elif confirm:
				_sub_select()
		S.MESSAGE:
			if confirm:
				if msg_shown < cur_msg.length():
					msg_shown = cur_msg.length()
				else:
					_next_msg()
		S.BAR:
			if confirm and not bar_stopped:
				_stop_bar()
		S.SELECT:
			if dy != 0:
				select_idx = posmod(select_idx + dy, ENEMIES.size())
			elif confirm:
				setup_enemy(ENEMIES[select_idx]["id"])
		S.END:
			if embedded:
				if confirm or cancel:
					fight_over.emit(outcome)
			elif confirm:
				get_tree().reload_current_scene()
			elif cancel:
				next_enemy = ""
				get_tree().reload_current_scene()


func _menu_select() -> void:
	if menu_idx == menu_cut:
		say(["* The Dominion Breaker cut that option away."], func(): state = S.MENU)
		return
	match menu_idx:
		0:
			_start_bar("fight")
		1:
			sub_kind = "magic"
			sub_idx = 0
			state = S.SUB
		2:
			sub_kind = "item"
			sub_idx = 0
			state = S.SUB
		3:
			sub_kind = "mercy"
			sub_idx = 0
			state = S.SUB


func _sub_list() -> Array:
	match sub_kind:
		"magic":
			return MAGIC
		"item":
			return ITEMS
		_:
			return [
				{"name": "Spare", "desc": "Spare %s (works when it is tired - yellow name)." % enemy_name.capitalize()},
				{"name": "Flee", "desc": "Run away."},
			]


func _sub_select() -> void:
	var entry: Dictionary = _sub_list()[sub_idx]
	if sub_kind == "magic":
		var cost: int = shock_cost() if entry["id"] == "shock" else int(entry["cost"])
		if mp < cost:
			say(["* Not enough MANA."], func(): state = S.SUB)
			return
		mp -= cost
		match entry["id"]:
			"haste":
				haste_left = 1
				sfx("cast")
				say(["* Corin cast Haste!", "* The SOUL feels light."], enemy_turn)
			"accel":
				accel_left = 2
				sfx("cast")
				say(["* Corin cast Accelerated Computation!", "* Everything seems to slow down."], enemy_turn)
			"shock":
				_start_bar("shock")
	elif sub_kind == "item":
		var id: String = entry["id"]
		if entry.get("kind", "gear") == "heal":
			_use_heal(entry)
			return
		if weapon == id:
			weapon = "plain"
			say(["* Corin put away the %s." % entry["name"]], enemy_turn)
		else:
			weapon = id
			if id == "selys":
				say(["* Corin drew Selys-Lyann.", "* A Frost Armor forms. DEF up!"], enemy_turn)
			else:
				say(["* Corin drew the Transference Sword.", "* Shockwave feels sharper."], enemy_turn)
	else:
		if sub_idx == 0:
			if spareable():
				if enemy_id == "keras" and saf.mode == "spared":
					end_game(["* Corin lowered the sword in answer.", "* Keras nodded once and sheathed the Dominion Breaker.", "* \"Then we are done. Walk on, Corin.\""], "SPARED EACH OTHER")
				elif enemy_id == "keras":
					end_game(["* Corin lowered the sword.", "* Keras held the Dominion Breaker a moment longer, then planted it in the ground.", "* \"...Enough. You have earned that.\""], "YOU SPARED HIM")
				elif enemy_id == "katashi":
					end_game(["* Corin lowered the sword.", "* Katashi's light softened to a warm glow.", "* \"...Heh. You're quicker than you look.\""], "YOU SPARED HIM")
				elif enemy_id == "saffron":
					end_game(["* Corin lowered the guard.", "* Saffron studied him a long moment, then sheathed his sword.", "* \"...Well fought, Corin.\""], "YOU SPARED HIM")
				else:
					end_game(["* Corin spared the Slime.", "* It burbles happily and oozes away."], "YOU SPARED IT")
			elif enemy_id == "keras":
				say(["* Keras does not lower the blade. \"Prove it.\""], enemy_turn)
			elif enemy_id == "katashi":
				say(["* Katashi grins. \"Not even close.\""], enemy_turn)
			elif enemy_id == "saffron":
				say(["* Saffron isn't finished. Neither is the fight."], enemy_turn)
			else:
				say(["* The Slime isn't ready to be spared."], enemy_turn)
		else:
			end_game(["* Corin ran away."], "FLED")


func _use_heal(entry: Dictionary) -> void:
	var id: String = entry["id"]
	if items_cut:
		say(["* That half of the ITEM button was cut away."], func(): state = S.SUB)
		return
	if int(stock[id]) <= 0:
		say(["* No %ss left." % String(entry["name"])], func(): state = S.SUB)
		return
	if hp >= max_hp:
		say(["* Corin's HP is already full."], func(): state = S.SUB)
		return
	stock[id] = int(stock[id]) - 1
	var healed: int = mini(maxi(1, int(round(float(max_hp) * float(entry["pct"])))), max_hp - hp)
	hp += healed
	sfx("heal")
	add_popup("+%d" % healed, Vector2(205, 346), Color(0.4, 1.0, 0.4))
	say(["* Corin used the %s." % entry["name"], "* Recovered %d HP!" % healed], enemy_turn)


# ---------------------------------------------------------------- messages
func say(lines: Array, cb: Callable) -> void:
	msg_queue = lines.duplicate()
	msg_cb = cb
	state = S.MESSAGE
	_next_msg()


func _next_msg() -> void:
	if msg_queue.is_empty():
		msg_cb.call()
		return
	cur_msg = msg_queue.pop_front()
	msg_shown = 0.0


func to_menu() -> void:
	state = S.MENU
	if enemy_id == "keras" and saf.mode == "spared":
		menu_text = "* Keras has spared you. He waits, the blade lowered. If you keep fighting, he will not hold back."
		if saf.gauntlet_passed:
			menu_text = "* Keras waits, the blade lowered. Take your time to heal. When Corin attacks, he will not hold back."
	elif enemy_id == "keras":
		var rlines: Array = ["* Keras shifts his grip. The air parts around the blade.", "* The Dominion Breaker is very quiet.", "* Keras is holding back, and he knows you can tell."]
		menu_text = "* Keras is flagging. Mercy is possible." if spareable() else rlines.pick_random()
	elif enemy_id == "katashi":
		var klines: Array = ["* Katashi's afterimages flicker.", "* The air is bright. Hot.", "* Katashi is somewhere else. Then back."]
		menu_text = "* Katashi is slowing. Mercy is possible." if spareable() else klines.pick_random()
	elif enemy_id == "saffron":
		var lines: Array = ["* Saffron circles, patient.", "* Saffron's sword hums.", "* The air around Saffron bends."]
		menu_text = "* Saffron is tiring. Mercy is possible." if spareable() else lines.pick_random()
	else:
		menu_text = "* The Slime is ready to be spared." if spareable() else "* The Slime wobbles."


func end_game(lines: Array, title: String) -> void:
	end_text = title
	match title:
		"VICTORY":
			sfx("win")
		"GAME OVER":
			sfx("lose")
		"FLED":
			sfx("flee")
		_:
			sfx("spare")
	match title:
		"VICTORY":
			outcome = "won"
		"GAME OVER":
			outcome = "lost"
		"FLED":
			outcome = "fled"
		_:
			outcome = "spared"
	say(lines, func(): state = S.END)


# ---------------------------------------------------------------- fight bar
func _start_bar(mode: String) -> void:
	bar_mode = mode
	bar_x = BAR_TRACK_R
	bar_jitter = randf_range(0.85, 1.2)
	bar_stopped = false
	bar_label = ""
	state = S.BAR


func _bar_speed() -> float:
	# Random per-swing jitter, and the marker speeds up as it nears the target.
	var progress: float = 1.0 - (bar_x - BAR_TARGET_X) / (BAR_TRACK_R - BAR_TARGET_X)
	var s: float = BAR_BASE_SPEED * bar_jitter * bar_mult * (1.0 + 0.5 * clampf(progress, 0.0, 1.0))
	if accel_left > 0:
		s *= 0.6
	if weapon == "selys":
		s *= 1.35
	return s


func _stop_bar() -> void:
	sfx("bar_stop")
	bar_stopped = true
	var dist: float = absf(bar_x - BAR_TARGET_X)
	if dist <= BAR_PERFECT:
		bar_result = 1.4
		bar_label = "PERFECT!"
	else:
		bar_result = pow(clampf(1.0 - dist / BAR_FALLOFF, 0.0, 1.0), 1.5)
		bar_label = "MISS" if bar_result < BAR_MISS_BELOW else ("GOOD" if bar_result > 0.6 else "WEAK")
		if bar_result < BAR_MISS_BELOW:
			bar_result = 0.0
	_begin_slash()


func _begin_slash() -> void:
	slash_kind = bar_mode
	slash_mult = bar_result
	slash_t = 0.0
	state = S.SLASH
	slash_sfx_done = false
	if slash_mult > 0.0:
		sfx("shock" if slash_kind == "shock" else "slash")


func _apply_hit() -> void:
	var base: float = float(atk) * 2.2
	if blade_dull > 0:
		base *= 0.5   # the Dominion Breaker cut the edge off the blade
	if slash_kind == "shock":
		base *= 2.5 if weapon == "transference" else 1.8
	var dmg: int = int(round(base * slash_mult))
	if weapon == "selys" and enemy_id == "saffron":
		dmg = int(round(float(dmg) * 1.25))   # spirit element bites deeper
	haste_left = maxi(0, haste_left - 1)
	accel_left = maxi(0, accel_left - 1)
	var lead: Array = []
	if enemy_id == "keras" and saf.mode == "spared":
		if saf.gauntlet_passed:
			saf.begin_allout()   # you swung at him after the path: now he stops holding back
			items_cut = true
			lead = ["* Keras's eyes narrow.", "* \"...Then I will not hold back.\"", "* The Dominion Breaker screams through the air.", "* It cut Corin's ITEM button in half! The healing items are gone!"]
		else:
			saf.begin_gauntlet()   # you swung at someone who spared you: first, the path
			lead = ["* Keras's eyes narrow.", "* \"...Then run.\"", "* The Dominion Breaker carves the arena into a path!"]
	if dmg <= 0:
		add_popup("MISS", SLIME_POS + Vector2(0, -70), Color.GRAY)
		enemy_turn(lead)
		return
	enemy_hp = maxi(0, enemy_hp - dmg)
	enemy_shake = 0.4
	add_shake(clampf(float(dmg) / 60.0, 0.25, 0.7))
	add_popup(str(dmg), SLIME_POS + Vector2(0, -70), Color.WHITE)
	if weapon == "selys":
		poison_turns = 4 if enemy_id == "saffron" else 3
		frost_note = enemy_id == "saffron"
	if enemy_hp <= 0:
		enemy_alive = false
		if enemy_id == "keras":
			end_game(["* The Dominion Breaker slipped from Keras's hands.", "* \"...A fair cut.\"", "* YOU WON!"], "VICTORY")
		elif enemy_id == "katashi":
			end_game(["* Katashi's halo cracked and went dark.", "* \"...Too slow, huh.\"", "* YOU WON!"], "VICTORY")
		elif enemy_id == "saffron":
			end_game(["* Saffron fell to one knee.", "* \"...You win.\"", "* YOU WON!"], "VICTORY")
		else:
			end_game(["* The Slime melted into a puddle.", "* YOU WON!"], "VICTORY")
	else:
		enemy_turn(lead + _form_lines())


# ---------------------------------------------------------------- enemy turn
func _form_lines() -> Array:
	# Keras drops to 40% -> he spares Corin (once). Continuing to fight triggers his all-out phase.
	if enemy_id == "keras" and enemy_alive and saf.mode == "fight" and enemy_hp <= int(float(enemy_max) * KERAS_SPARE_AT):
		saf.begin_spared()
		return ["* Keras stops mid-swing.", "* The Dominion Breaker lowers.", "* \"Enough. You have shown me what I wanted to see.\"", "* \"I spare you, Corin. Walk away. Or don't.\""]
	# Saffron drops to a quarter health -> simulacra step out of his shadow (once).
	if enemy_id == "saffron" and enemy_alive and saf.form == 1 and enemy_hp <= int(float(enemy_max) * FORM2_FRAC):
		saf.begin_form2()
		return ["* Saffron's outline wavers.", "* Two simulacra step out of his shadow!", "* \"Now dodge all of us.\""]
	return []


func enemy_turn(prefix: Array = []) -> void:
	if enemy_id == "keras" and saf.mode == "spared":
		menu_cut = -1
		say(prefix + ["* Keras stands with the blade lowered. He is waiting for your choice."], to_menu)
		return
	var lines: Array = ["* Blorp.", "* The Slime jiggles menacingly.", "* The Slime burbles.", "* Squelch."]
	if spareable():
		lines = ["* The Slime looks tired.", "* The Slime is panting. Sort of."]
	if enemy_id == "saffron":
		lines = ["* Saffron moves.", "* \"Show me what you've learned.\"", "* Saffron's eyes flash.", "* \"Again.\""]
		if spareable():
			lines = ["* Saffron is breathing hard.", "* \"...Not yet.\""]
	if enemy_id == "keras":
		lines = ["* Keras raises the Dominion Breaker.", "* \"Watch closely.\"", "* The blade hums.", "* \"I am giving you time. Use it.\""]
		if saf.mode == "gauntlet":
			lines = ["* The path stretches ahead. Behind Corin, the blades are already moving.", "* \"Keep moving.\""]
		if saf.mode == "allout":
			lines = ["* Keras is a blur.", "* \"This is the speed I always had.\"", "* The cuts come faster than the warnings.", "* \"Keep up.\""]
		if spareable():
			lines = ["* Keras leans on the Dominion Breaker.", "* \"...Again.\""]
	if enemy_id == "katashi":
		lines = ["* Katashi blurs.", "* \"Too slow!\"", "* A flash. Where did he go?", "* \"Keep up, Corin.\""]
		if spareable():
			lines = ["* Katashi is panting. He is still smiling.", "* \"...Again.\""]
	var out: Array = [lines.pick_random()]
	menu_cut = -1   # a cut menu option comes back once Corin has acted
	if enemy_id == "keras" and poison_turns > 0:
		poison_turns = 0
		out.push_front("* The Dominion Breaker cut through the frost. The poison is gone!")
	if frost_note:
		frost_note = false
		out.push_front("* Spirit-frost bites deep into Saffron!")
	say(prefix + out, start_dodge)


func start_dodge() -> void:
	if is_boss():
		dodge_t = 0.0
		bullets.clear()
		iframes = 0.3
		saf.start_turn()
		state = S.DODGE
		return
	pattern = ["rain", "bounce", "smash"].pick_random()
	dodge_t = 0.0
	dodge_len = DODGE_TIME
	slime_away = false
	if pattern == "smash":
		dodge_len = 99.0
		smash_left = randi_range(3, 5)
		smash_phase = "launch"
		smash_t = 0.0
	spawn_timer = 0.3
	bullets.clear()
	soul = ARENA.get_center()
	iframes = 0.3
	start_hop()
	if pattern == "bounce":
		for i in 3:
			var ang: float = randf_range(0.3, 1.2) + float(i) * 1.9
			bullets.append({
				"pos": Vector2(ARENA.position.x + 30 + 50 * i, ARENA.position.y + 20),
				"vel": Vector2(cos(ang), sin(ang)) * 110.0 * _slow(),
				"r": 8.0, "kind": "bounce",
			})
	state = S.DODGE


func _slow() -> float:
	if poison_turns <= 0:
		return 1.0
	return 0.65 if enemy_id == "saffron" else 0.75


func end_dodge() -> void:
	bullets.clear()
	slime_away = false
	var notes: Array = []
	if poison_turns > 0:
		poison_turns -= 1
		enemy_hp = maxi(1, enemy_hp - poison_dmg)
		add_popup(str(poison_dmg), SLIME_POS + Vector2(0, -70), Color(0.5, 0.9, 1.0))
		var who: Dictionary = {"saffron": "Saffron's spirit", "katashi": "Katashi", "keras": "Keras", "slime": "the Slime"}
		notes.append("* Frost poison eats at %s." % who[enemy_id])
		notes += _form_lines()
	if armor_cut > 0:
		armor_cut -= 1
	if blade_dull > 0:
		blade_dull -= 1
	if dull_note:
		dull_note = false
		notes.append("* The Dominion Breaker dulled the blade! FIGHT damage is halved for 2 turns.")
	if mana_note > 0:
		notes.append("* The Dominion Breaker burst the mana in Corin! (-%d MP)" % mana_note)
		mana_note = 0
	if sever_note:
		sever_note = false
		notes.append("* The Dominion Breaker severed Corin's buffs and Frost Armor!")
	if menu_note:
		menu_note = false
		notes.append("* It cut through the %s option, too." % BUTTONS[menu_cut].capitalize())
	if enemy_id == "keras" and saf.mode == "gauntlet" and saf.gauntlet_done:
		saf.end_gauntlet()
		notes += ["* Corin outran the blades.", "* Keras lowers the Dominion Breaker. \"...Good. Catch your breath.\"", "* He is waiting. This is the time to heal."]
	if notes.is_empty():
		to_menu()
	else:
		say(notes, to_menu)


func _update_dodge(delta: float) -> void:
	dodge_t += delta
	iframes = maxf(0.0, iframes - delta)
	if is_boss():
		var done: bool = saf.update(delta)
		if hp <= 0:
			end_game(["* Corin collapsed...", "* But the Spire isn't done with Corin yet."], "GAME OVER")
		elif done:
			end_dodge()
		return
	var spd: float = SOUL_SPEED_HASTE if haste_left > 0 else SOUL_SPEED
	var dir := Vector2(
		float(Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D))
		- float(Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_DOWN) or Input.is_physical_key_pressed(KEY_S))
		- float(Input.is_physical_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_W)))
	if dir.length() > 0.0:
		dir = dir.normalized()
	if Input.is_physical_key_pressed(KEY_X) or Input.is_physical_key_pressed(KEY_SHIFT):
		spd *= 0.5
	soul += dir * spd * delta
	var inner: Rect2 = ARENA.grow(-10)
	soul = soul.clamp(inner.position, inner.end)

	spawn_timer -= delta
	if dodge_t < dodge_len - 0.5:
		match pattern:
			"rain":
				if spawn_timer <= 0.0:
					spawn_timer = 0.2
					bullets.append({
						"pos": Vector2(randf_range(ARENA.position.x + 8, ARENA.end.x - 8), ARENA.position.y - 4),
						"vel": Vector2(0, randf_range(110.0, 160.0) * _slow()),
						"r": 6.0, "kind": "drop",
					})
			"smash":
				pass  # handled below (runs on its own timeline)

	if pattern == "smash":
		_update_smash(delta)

	var keep: Array = []
	for b: Dictionary in bullets:
		b["pos"] += b["vel"] * delta
		if b["kind"] == "bounce":
			var inner_b: Rect2 = ARENA.grow(-b["r"])
			if b["pos"].x < inner_b.position.x or b["pos"].x > inner_b.end.x:
				b["vel"].x *= -1.0
			if b["pos"].y < inner_b.position.y or b["pos"].y > inner_b.end.y:
				b["vel"].y *= -1.0
			b["pos"] = b["pos"].clamp(inner_b.position, inner_b.end)
		if b["pos"].distance_to(soul) < b["r"] + 4.0:
			hurt(8 if b["kind"] != "drop" else 6)
		var off: bool = not Rect2(-20, -20, 680, 520).has_point(b["pos"]) \
			or (b["kind"] == "drop" and b["pos"].y > ARENA.end.y + 8.0)
		if not off:
			keep.append(b)
	bullets = keep

	if hp <= 0:
		bullets.clear()
		end_game(["* Corin collapsed...", "* But the Spire isn't done with Corin yet."], "GAME OVER")
	elif dodge_t >= dodge_len:
		end_dodge()


# ---- smash: the Slime is a real body. It hovers above the arena loosely following
# the SOUL, locks on, drops under gravity, squashes on the floor, then BOUNCES back up.
# Repeats 3-5x with randomized timing; finally glides home.
func _smash_start_wait() -> void:
	smash_wait = randf_range(0.45, 1.25) / _slow()
	smash_lock = minf(0.3, smash_wait * 0.6)    # stops tracking this long before the drop
	smash_drift = randf_range(-40.0, 40.0)      # sloppy aim offset
	smash_t = 0.0
	smash_phase = "wait"


func _smash_clamp_x(x: float) -> float:
	return clampf(x, ARENA.position.x + SMASH_R + 4.0, ARENA.end.x - SMASH_R - 4.0)


func _smash_hurt(zone: Rect2) -> void:
	if zone.grow(4.0).has_point(soul):
		hurt(10)


func _update_smash(delta: float) -> void:
	smash_t += delta
	match smash_phase:
		"launch":
			if smash_t >= 0.45:
				slime_away = true   # main sprite hands off to the physical one
				sm_pos = Vector2(SLIME_BASE.x, HOVER_Y)
				_smash_start_wait()
		"wait":
			sm_pos.y = HOVER_Y + sin(t_anim * 6.0) * 4.0
			if smash_t < smash_wait - smash_lock:
				var goal: float = _smash_clamp_x(soul.x + smash_drift)
				sm_pos.x = move_toward(sm_pos.x, goal, 170.0 * _slow() * delta)
			if smash_t >= smash_wait:
				sm_pos.y = HOVER_Y
				sm_vy = 0.0
				smash_phase = "fall"
				smash_t = 0.0
		"fall":
			var prev_y: float = sm_pos.y
			sm_vy += SMASH_G * delta
			sm_pos.y = minf(SMASH_FLOOR_Y, sm_pos.y + sm_vy * delta)
			# swept body: crush anything between where it was and where it is
			var w: float = SMASH_R * 1.6
			_smash_hurt(Rect2(sm_pos.x - w * 0.5, prev_y - SMASH_BODY_H, w, (sm_pos.y - prev_y) + SMASH_BODY_H))
			if sm_pos.y >= SMASH_FLOOR_Y:
				smash_phase = "impact"
				smash_t = 0.0
				add_shake(0.6)
				sfx("impact")
		"impact":
			_smash_hurt(Rect2(sm_pos.x - SMASH_R * 1.15, SMASH_FLOOR_Y - 34.0, SMASH_R * 2.3, 34.0))
			if smash_t >= 0.18:
				smash_left -= 1
				# bounce back up: just enough speed to reach hover height
				sm_vy = -sqrt(2.0 * SMASH_G_UP * (SMASH_FLOOR_Y - HOVER_Y))
				smash_phase = "rebound" if smash_left > 0 else "rebound_last"
				smash_t = 0.0
		"rebound", "rebound_last":
			sm_vy += SMASH_G_UP * delta
			sm_pos.y += sm_vy * delta
			# ease sideways toward the SOUL while rising so the next drop isn't a snap
			sm_pos.x = move_toward(sm_pos.x, _smash_clamp_x(soul.x), 120.0 * delta)
			if sm_vy >= 0.0 or sm_pos.y <= HOVER_Y:
				sm_pos.y = maxf(sm_pos.y, HOVER_Y)
				if smash_phase == "rebound":
					_smash_start_wait()
				else:
					smash_phase = "return"
					return_dist = sm_pos.distance_to(SLIME_BASE)
					smash_t = 0.0
		"return":
			# glide back to the resting spot above the arena, then take over as the main sprite
			sm_pos = sm_pos.move_toward(SLIME_BASE, 260.0 * delta)
			if sm_pos.distance_to(SLIME_BASE) < 1.0:
				slime_away = false
				smash_phase = "done"
				smash_t = 0.0
				start_hop()
		"done":
			if smash_t >= 0.5:
				dodge_len = 0.0   # finish the dodge phase now


# ---------------------------------------------------------------- process
func add_popup(text: String, pos: Vector2, col: Color) -> void:
	popups.append({"text": text, "pos": pos, "t": 0.0, "color": col})


func _process(delta: float) -> void:
	t_anim += delta
	if saf != null:
		saf.tick(delta)
	enemy_shake = maxf(0.0, enemy_shake - delta)
	shake = maxf(0.0, shake - delta * 1.8)
	position = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake * shake * 14.0
	if hop_t >= 0.0:
		hop_t += delta
		if hop_t > 0.64:
			hop_t = -1.0
	elif enemy_alive:
		idle_hop_timer -= delta
		if idle_hop_timer <= 0.0:
			idle_hop_timer = randf_range(2.5, 4.5)
			start_hop()
	if not enemy_alive:
		enemy_fade = maxf(0.0, enemy_fade - delta * 0.8)

	var target: Rect2 = TEXT_BOX
	if state == S.DODGE:
		target = saf.box_rect() if is_boss() else ARENA
	box.position = box.position.lerp(target.position, minf(1.0, delta * 14.0))
	box.size = box.size.lerp(target.size, minf(1.0, delta * 14.0))

	for p: Dictionary in popups:
		p["t"] += delta
	popups = popups.filter(func(p: Dictionary) -> bool: return p["t"] < 1.0)

	match state:
		S.MESSAGE:
			msg_shown = minf(float(cur_msg.length()), msg_shown + delta * 45.0)
			var typed: int = int(msg_shown)
			if typed > text_blip_at and typed % 2 == 0 and typed <= cur_msg.length() and cur_msg[typed - 1] != " ":
				sfx("text", 0.35)
			text_blip_at = typed
		S.BAR:
			if not bar_stopped:
				bar_x -= _bar_speed() * delta
				if bar_x < BAR_TARGET_X - 25.0:
					bar_stopped = true
					bar_result = 0.0
					bar_label = "MISS"
					_begin_slash()
		S.SLASH:
			slash_t += delta
			if not slash_sfx_done and slash_t >= 0.3:   # the moment the swing lands
				slash_sfx_done = true
				sfx("miss" if slash_mult <= 0.0 else ("crit" if slash_mult > 1.0 else "hit"))
			if slash_t >= 0.6:
				_apply_hit()
		S.DODGE:
			_update_dodge(delta)
	queue_redraw()


# ---------------------------------------------------------------- drawing
# Pixel font: 5x7 glyphs from assets/font/pixel_font.png (made by tools/make_pixel_font.py).
# `size` keeps the old point-size meaning; it just picks an integer pixel scale.
const FONT_CELL := Vector2i(6, 9)   # atlas cell: 5 wide + 1 spacing, 9 tall (7 body + descenders)
const FONT_COLS := 16
const FONT_BODY := 7                # rows above the baseline


func _px_scale(size: int) -> int:
	if size >= 32:
		return 4
	if size >= 22:
		return 3
	if size >= 14:
		return 2
	return 1


func _text_width(s: String, scale: int) -> float:
	return float(maxi(0, s.length() * FONT_CELL.x - 1) * scale)


func _text(s: String, pos: Vector2, size: int = 16, col: Color = Color.WHITE, width: float = -1.0, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	# pos is the BASELINE-left, like draw_string
	var sc: int = _px_scale(size)
	var x: float = pos.x
	if width > 0.0:
		if align == HORIZONTAL_ALIGNMENT_CENTER:
			x += (width - _text_width(s, sc)) * 0.5
		elif align == HORIZONTAL_ALIGNMENT_RIGHT:
			x += width - _text_width(s, sc)
	x = roundf(x)
	var y: float = roundf(pos.y) - float(FONT_BODY * sc)
	for i in s.length():
		var code: int = s.unicode_at(i)
		if code < 33 or code > 127:
			if code != 32:
				code = 63   # '?'
			else:
				continue
		var idx: int = code - 32
		var src := Rect2(float((idx % FONT_COLS) * FONT_CELL.x), float((idx / FONT_COLS) * FONT_CELL.y), 5.0, float(FONT_CELL.y))
		var dst := Rect2(x + float(i * FONT_CELL.x * sc), y, float(5 * sc), float(FONT_CELL.y * sc))
		draw_texture_rect_region(pixel_font, dst, src, col)


func _wrap(s: String, max_w: float, scale: int) -> Array:
	# greedy word wrap using the fixed glyph advance
	var per_line: int = maxi(1, int((max_w + float(scale)) / float(FONT_CELL.x * scale)))
	var lines: Array = []
	var cur: String = ""
	for word: String in s.split(" "):
		var trial: String = word if cur == "" else cur + " " + word
		if trial.length() <= per_line:
			cur = trial
		else:
			if cur != "":
				lines.append(cur)
			cur = word
	lines.append(cur)
	return lines


func _draw() -> void:
	if state == S.SELECT:
		_draw_select()
		return
	if is_boss():
		if enemy_fade > 0.0:
			saf.draw_boss(Vector2(sin(t_anim * 90.0) * 6.0 * enemy_shake, 0), enemy_fade)
	else:
		_draw_slime()
	_draw_enemy_bar()
	_draw_slash()
	_draw_box()
	if is_boss() and state == S.DODGE:
		saf.draw_attacks()
	_draw_hud()
	_draw_smash()
	for b: Dictionary in bullets:
		var d: float = float(b["r"]) * 2.0
		draw_texture_rect(slime_ball, Rect2(b["pos"] - Vector2(d, d) * 0.5, Vector2(d, d)), false)
	if state == S.DODGE:
		if iframes <= 0.0 or int(t_anim * 20.0) % 2 == 0:
			var heart_col: Color = Color.RED
			if is_boss() and saf.circle_mode:
				heart_col = Color(0.25, 0.45, 1.0)
			_heart(soul, 9.0, heart_col)
	for p: Dictionary in popups:
		var col: Color = p["color"]
		col.a = 1.0 - p["t"]
		_text(p["text"], p["pos"] + Vector2(0, -p["t"] * 30.0), 24, col, 60.0, HORIZONTAL_ALIGNMENT_CENTER)
	if state == S.END:
		_text(end_text, Vector2(0, 150), 36, Color.YELLOW, 640.0, HORIZONTAL_ALIGNMENT_CENTER)
		_text("Z: continue" if embedded else "Z: play again     X: choose enemy", Vector2(0, 190), 16, Color.GRAY, 640.0, HORIZONTAL_ALIGNMENT_CENTER)


func _floor_shadow(at: Vector2, alpha: float) -> void:
	draw_set_transform(at, 0.0, Vector2(1.0, 0.3))
	draw_circle(Vector2.ZERO, SMASH_R, Color(0, 0, 0, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_smash() -> void:
	if pattern != "smash" or state != S.DODGE or not slime_away:
		return
	var floor_pt := Vector2(sm_pos.x, SMASH_FLOOR_Y)
	var phase: String = smash_phase
	# floor shadow: darkens as the Slime gets closer to the floor
	if phase == "wait" or phase == "fall" or phase == "rebound":
		var closeness: float = clampf(1.0 - (SMASH_FLOOR_Y - sm_pos.y) / (SMASH_FLOOR_Y - HOVER_Y), 0.0, 1.0)
		var a: float = 0.25 + 0.35 * closeness
		if phase == "wait":
			a = 0.25 + 0.3 * clampf(smash_t / smash_wait, 0.0, 1.0)
		_floor_shadow(floor_pt, a)
	if phase == "impact":
		var p: float = clampf(smash_t / 0.18, 0.0, 1.0)
		draw_set_transform(floor_pt, 0.0, Vector2(1.0, 0.3))
		draw_arc(Vector2.ZERO, SMASH_R * (0.8 + 1.0 * p), 0, TAU, 32, Color(1, 1, 1, 1.0 - p), 3.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# the Slime itself: squashed on the floor / stretched in the air
	var scale_f: float = SLIME_SCALE * 0.7
	if phase == "return":
		scale_f = lerpf(SLIME_SCALE * 0.7, SLIME_SCALE, 1.0 - sm_pos.distance_to(SLIME_BASE) / maxf(1.0, return_dist))
	var tex: Texture2D = slime_jump[1] if phase == "impact" else slime_jump[0]
	var sz: Vector2 = tex.get_size() * scale_f
	draw_texture_rect(tex, Rect2(sm_pos - Vector2(sz.x * 0.5, sz.y), sz), false)


func _heart(c: Vector2, s: float, col: Color) -> void:
	# pixel-art SOUL (assets/SOUL/heart.png, 8x7). `s` is the old size hint; it only picks the integer scale.
	var sc: int = 3 if s >= 12.0 else 2
	var size: Vector2 = heart_tex.get_size() * float(sc)
	var tl := Vector2(roundf(c.x - size.x * 0.5), roundf(c.y - size.y * 0.5))
	draw_texture_rect(heart_tex, Rect2(tl, size), false, col)


func _draw_slime() -> void:
	if enemy_fade <= 0.0:
		return
	var shake := Vector2(sin(t_anim * 90.0) * 6.0 * enemy_shake, 0)
	var tint := Color(1, 1, 1, enemy_fade)
	if poison_turns > 0:
		tint = Color(0.6, 0.85, 1.0, enemy_fade)
	if spareable():
		tint = tint.lerp(Color(1, 1, 0.5, enemy_fade), 0.5)

	# Pick frame: hop sequence (squash -> air -> land) or the 2-frame idle bob.
	var tex: Texture2D = slime_idle[int(t_anim * 2.0) % 2]
	var lift: float = 0.0
	if hop_t >= 0.0:
		if hop_t < 0.12:
			tex = slime_jump[1]
		elif hop_t < 0.52:
			tex = slime_jump[0]
			lift = sin((hop_t - 0.12) / 0.4 * PI) * 28.0
		else:
			tex = slime_jump[1]
	var size: Vector2 = tex.get_size() * SLIME_SCALE
	var base: Vector2 = SLIME_BASE + shake - Vector2(0, lift)
	if not slime_away:
		draw_texture_rect(tex, Rect2(base - Vector2(size.x * 0.5, size.y), size), false, tint)


func _draw_enemy_bar() -> void:
	if enemy_fade <= 0.0:
		return
	var name_col: Color = Color.YELLOW if spareable() else Color.WHITE
	var y: float = 22.0 if is_boss() else 30.0
	var label: String = enemy_name
	if enemy_id == "saffron" and saf.form == 2:
		label = "SAFFRON + SIMULACRA"
	_text(label, Vector2(170, y), 16, name_col, 300.0, HORIZONTAL_ALIGNMENT_CENTER)
	draw_rect(Rect2(220, y + 6.0, 200, 8), Color(0.3, 0, 0))
	draw_rect(Rect2(220, y + 6.0, 200.0 * float(enemy_hp) / float(enemy_max), 8), Color(0.2, 0.9, 0.2))


func _draw_select() -> void:
	_text("ARCANE UNDERTALE", Vector2(0, 110), 36, Color.WHITE, 640.0, HORIZONTAL_ALIGNMENT_CENTER)
	_text("battle prototype", Vector2(0, 138), 16, Color.GRAY, 640.0, HORIZONTAL_ALIGNMENT_CENTER)
	for i in ENEMIES.size():
		var y: float = 215.0 + 40.0 * i
		var col: Color = Color.YELLOW if i == select_idx else Color.WHITE
		_text(String(ENEMIES[i]["label"]), Vector2(240, y), 22, col)
		if i == select_idx:
			_heart(Vector2(218, y - 8), 9.0, Color.RED)
	_text(String(ENEMIES[select_idx]["desc"]), Vector2(0, 392), 13, Color(0.7, 0.7, 0.7), 640.0, HORIZONTAL_ALIGNMENT_CENTER)
	_text("Up/Down: choose     Z: start     M: mute", Vector2(0, 440), 14, Color.GRAY, 640.0, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_slash() -> void:
	if state != S.SLASH or slash_mult <= 0.0:
		return
	var p: float = clampf(slash_t / 0.5, 0.0, 1.0)
	if slash_kind == "fight":
		var a: Vector2 = SLIME_POS + Vector2(-60, -50)
		var b: Vector2 = SLIME_POS + Vector2(60, 70)
		draw_line(a, a.lerp(b, p), Color.WHITE, 5.0)
	else:
		# Shockwave: a crescent flying up from Corin's side of the screen to the Slime.
		var y: float = lerpf(330.0, SLIME_POS.y, p)
		var w: float = 90.0 + 40.0 * p
		var col := Color(0.6, 0.85, 1.0, 1.0 - p * 0.4)
		draw_arc(Vector2(320, y + 80.0), 80.0 + w * 0.2, deg_to_rad(215), deg_to_rad(325), 24, col, 7.0)
		draw_arc(Vector2(320, y + 90.0), 80.0 + w * 0.2, deg_to_rad(220), deg_to_rad(320), 24, Color(1, 1, 1, 0.8), 3.0)


func _draw_box() -> void:
	if is_boss() and state == S.DODGE and saf.morph > 0.001:
		saf.draw_arena()
		return
	draw_rect(box, Color.BLACK)
	draw_rect(box, Color.WHITE, false, 4.0)
	var inner: Rect2 = box.grow(-14)
	match state:
		S.MENU:
			_para(menu_text, inner)
		S.MESSAGE:
			_para(cur_msg, inner, int(msg_shown))
		S.SUB:
			_draw_sub()
		S.BAR, S.SLASH:
			_draw_bar()


func _para(s: String, r: Rect2, shown: int = -1) -> void:
	# wrap the FULL text first so the typewriter reveal doesn't re-flow words as it types
	var sc: int = _px_scale(20)
	var lines: Array = _wrap(s, r.size.x, sc)
	var left: int = shown if shown >= 0 else 1000000
	for i in lines.size():
		var line: String = lines[i]
		if left <= 0:
			break
		_text(line.substr(0, left), r.position + Vector2(0, float(FONT_BODY * sc) + 6.0 + float(i) * float(FONT_CELL.y * sc + 6)), 20)
		left -= line.length() + 1   # +1 for the space that was wrapped away


func _draw_sub() -> void:
	var list: Array = _sub_list()
	for i in list.size():
		var row_h: float = 24.0 if list.size() > 3 else 30.0
		var y: float = box.position.y + (34.0 if list.size() > 3 else 38.0) + row_h * i
		var name: String = list[i]["name"]
		if sub_kind == "magic":
			var cost: int = shock_cost() if list[i]["id"] == "shock" else int(list[i]["cost"])
			name += "  (%d MP)" % cost
		elif sub_kind == "item" and list[i].get("kind", "gear") == "heal":
			name += "  [CUT]" if items_cut else "  x%d" % int(stock[list[i]["id"]])
		elif sub_kind == "item" and weapon == list[i]["id"]:
			name += "  [equipped]"
		var col: Color = Color.YELLOW if i == sub_idx else Color.WHITE
		if sub_kind == "item" and list[i].get("kind", "gear") == "heal" and (items_cut or int(stock[list[i]["id"]]) <= 0):
			col = Color(0.45, 0.45, 0.45)
		_text(name, Vector2(box.position.x + 54, y), 18, col)
		if i == sub_idx:
			_heart(Vector2(box.position.x + 34, y - 6), 8.0, Color.RED)
	_text(String(list[sub_idx]["desc"]), Vector2(box.position.x + 24, box.end.y - 16), 13, Color(0.7, 0.7, 0.7))


func _draw_bar() -> void:
	var cy: float = box.position.y + box.size.y * 0.5
	var track_col := Color(0.15, 0.15, 0.2)
	draw_rect(Rect2(BAR_TRACK_L, cy - 28, BAR_TRACK_R - BAR_TRACK_L, 56), track_col)
	draw_rect(Rect2(BAR_TRACK_L, cy - 28, BAR_TRACK_R - BAR_TRACK_L, 56), Color(0.7, 0.7, 0.8), false, 2.0)
	var tc: Color = Color(0.5, 0.8, 1.0) if bar_mode == "shock" else Color(1.0, 0.8, 0.2)
	# target: outlined window with a sweet-spot line
	draw_rect(Rect2(BAR_TARGET_X - 8, cy - 28, 16, 56), Color(tc, 0.18))
	draw_rect(Rect2(BAR_TARGET_X - 8, cy - 28, 16, 56), tc, false, 3.0)
	draw_line(Vector2(BAR_TARGET_X, cy - 28), Vector2(BAR_TARGET_X, cy + 28), tc, 2.0)
	var mc: Color = Color.WHITE
	if bar_stopped:
		mc = Color.RED if bar_result <= 0.0 else (Color.YELLOW if bar_result > 1.0 else Color(0.4, 1, 0.4))
	var w: float = 8.0 if not bar_stopped else 10.0 + 4.0 * sin(t_anim * 40.0)
	draw_rect(Rect2(bar_x - w * 0.5, cy - 34, w, 68), mc)
	if bar_mode == "shock":
		_text("SHOCKWAVE", Vector2(BAR_TRACK_L, cy - 40), 14, tc)
	if bar_label != "":
		_text(bar_label, Vector2(BAR_TRACK_L, cy + 52), 18, mc, BAR_TRACK_R - BAR_TRACK_L, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_hud() -> void:
	_text("CORIN", Vector2(40, 366), 18)
	_text("HP", Vector2(130, 366), 14)
	draw_rect(Rect2(155, 353, 100, 14), Color(0.5, 0, 0))
	draw_rect(Rect2(155, 353, 100.0 * float(hp) / float(max_hp), 14), Color.YELLOW)
	_text("%d/%d" % [hp, max_hp], Vector2(262, 366), 14)
	_text("MP", Vector2(335, 366), 14)
	draw_rect(Rect2(360, 353, 100, 14), Color(0, 0.1, 0.4))
	draw_rect(Rect2(360, 353, 100.0 * float(mp) / float(max_mp), 14), Color(0.3, 0.6, 1.0))
	_text("%d/%d" % [mp, max_mp], Vector2(467, 366), 14)
	# status line
	var st: Array = []
	if haste_left > 0:
		st.append("HASTE x%d" % haste_left)
	if accel_left > 0:
		st.append("ACCEL x%d" % accel_left)
	if weapon == "selys":
		st.append("FROST ARMOR CUT (%d)" % armor_cut if armor_cut > 0 else "FROST ARMOR (DEF+%d)" % defense())
	if blade_dull > 0:
		st.append("BLADE DULL x%d" % blade_dull)
	_text("  ".join(st), Vector2(40, 384), 12, Color(0.6, 0.9, 1.0))
	var wname: String = {"plain": "Sword", "transference": "Transference Sword", "selys": "Selys-Lyann"}[weapon]
	_text(wname, Vector2(400, 384), 12, Color(0.8, 0.8, 0.8), 200.0, HORIZONTAL_ALIGNMENT_RIGHT)
	for i in BUTTONS.size():
		var r := Rect2(40 + i * 148, 394, 130, 40)
		var sel: bool = state == S.MENU and i == menu_idx
		var col: Color = Color.YELLOW if sel else Color(1.0, 0.55, 0.1)
		draw_rect(r, Color.BLACK)
		draw_rect(r, col, false, 3.0)
		_text(BUTTONS[i], r.position + Vector2(0, 27), 18, col, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
		if i == 2 and items_cut:
			# sliced in half: a dark gap along the cut, the lower-right half knocked askew
			var gap := PackedVector2Array([r.position + Vector2(r.size.x * 0.62, -2), r.position + Vector2(r.size.x * 0.62 + 8, -2), r.position + Vector2(r.size.x * 0.38 + 8, r.size.y + 2), r.position + Vector2(r.size.x * 0.38, r.size.y + 2)])
			draw_colored_polygon(gap, Color.BLACK)
			draw_line(r.position + Vector2(r.size.x * 0.62, -2), r.position + Vector2(r.size.x * 0.38, r.size.y + 2), Color(0.7, 0.95, 1.0), 2.0)
			draw_line(r.position + Vector2(r.size.x * 0.62 + 8, -2), r.position + Vector2(r.size.x * 0.38 + 8, r.size.y + 2), Color(0.9, 0.5, 1.0), 2.0)
		if i == menu_cut:
			draw_rect(r, Color(0.05, 0.0, 0.1, 0.85))
			draw_line(r.position + Vector2(-4, r.size.y + 4), r.position + Vector2(r.size.x + 4, -4), Color(0.7, 0.95, 1.0), 3.0)
			draw_line(r.position + Vector2(-4, r.size.y + 8), r.position + Vector2(r.size.x + 4, 0), Color(0.9, 0.5, 1.0, 0.7), 1.0)
		if sel:
			_heart(r.position + Vector2(18, 20), 8.0, Color.RED)
