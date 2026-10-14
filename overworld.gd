extends Node2D
## Top-down overworld. Walk around, read signs, and bump into (or talk to) the four fighters.
## Tiles and Corin's sprite are generated in code from tiny pixel recipes - no external assets
## (except the Slime sprite you drew). Fighters are drawn with their battle figures, scaled down.
##
## Controls: arrows/WASD walk, Shift run, Z/Enter talk/read.
## Emits `encounter(id)` when a fight starts; the game node calls `resume(id, outcome)` afterwards.

signal encounter(enemy_id: String)

const SaffronFight := preload("res://saffron.gd")
const KatashiFight := preload("res://katashi.gd")
const KerasFight := preload("res://keras.gd")
const PixelUI := preload("res://pixel_ui.gd")

const TILE := 32   # 16px art drawn at 2x
const MAP_W := 48
const MAP_H := 36
const SCREEN := Vector2(640, 480)

const T_GRASS := 0
const T_STONE := 1
const T_WALL := 2
const T_TREE := 3
const T_WATER := 4
const T_PILLAR := 5
const T_PATH := 6

const WALK_SPEED := 110.0
const RUN_SPEED := 175.0
const FIGHTER_SCALE := 0.4

# Placeholder lines - rewrite freely. `tile` is where each fighter stands (feet, in tiles).
const FIGHTERS := {
	"slime": {"tile": Vector2(24.5, 29.9), "pre": ["* A Slime blocks the way."], "spared": ["* The Slime burbles happily."]},
	"saffron": {"tile": Vector2(7.5, 18.9), "pre": ["* Saffron watches you approach.", "* \"Show me what you've learned.\""], "spared": ["* Saffron nods at Corin."]},
	"katashi": {"tile": Vector2(40.5, 18.9), "pre": ["* Katashi is already looking at you.", "* \"Finally. Try to keep up.\""], "spared": ["* Katashi grins. \"Not bad.\""]},
	"keras": {"tile": Vector2(24.5, 6.9), "pre": ["* Keras stands with the Dominion Breaker point-down in the stone.", "* \"Come.\""], "spared": ["* Keras gives a short nod."]},
}

# Corin, 12x16, as pixel recipes. Palette keys below.
const PAL := {
	"H": Color(0.36, 0.20, 0.10), "S": Color(0.96, 0.80, 0.65), "E": Color(0.10, 0.10, 0.16),
	"T": Color(0.20, 0.35, 0.78), "B": Color(0.62, 0.42, 0.15), "L": Color(0.20, 0.20, 0.30),
	"K": Color(0.10, 0.08, 0.08), "W": Color(0.85, 0.92, 1.0),
}
const SPR_DOWN := [
	"....HHHH....", "...HHHHHH...", "..HHHHHHHH..", "..HSSSSSSH..", "..HSESSESH..", "..SSSSSSSS..",
	"...SSSSSS...", "..TTTTTTTT..", ".STTTTTTTTS.", ".STTBBBBTTS.", ".STTTTTTTTS.", "..TTTTTTTT..",
]
const SPR_UP := [
	"....HHHH....", "...HHHHHH...", "..HHHHHHHH..", "..HHHHHHHH..", "..HHHHHHHH..", "..HHHHHHHH..",
	"...HHHHHH...", "..TTTTTTTT..", ".STTWTTTTTS.", ".STTBBBBTTS.", ".STTTTTTTTS.", "..TTTTTTTT..",
]
const SPR_SIDE := [
	"....HHHH....", "...HHHHHH...", "..HHHHHHHH..", "..HHHSSSSH..", "..HHHSSESH..", "...HHSSSSS..",
	"....SSSS....", "...TTTTTT...", "...TTTTTTS..", "...TTBBTTS..", "...TTTTTTS..", "...TTTTTT...",
]
const LEGS_IDLE := ["..LLL..LLL..", "..LLL..LLL..", "..KKK..KKK.."]
const LEGS_A := ["...LL..LLL..", "...LL..LLL..", "...KK..KKK.."]
const LEGS_B := ["..LLL..LL...", "..LLL..LL...", "..KKK..KK..."]
const LEGS_SIDE_IDLE := ["...LLLLLL...", "...LLLLLL...", "...KKKKKK..."]
const LEGS_SIDE_A := ["...LLL.LL...", "...LLL.LL...", "...KKK.KK..."]
const LEGS_SIDE_B := ["...LL.LLL...", "...LL.LLL...", "...KK.KKK..."]

var results: Dictionary = {}          # fighter id -> "won" / "spared" (fled/lost stay unfought)
var pixel_font: Texture2D = load("res://assets/font/pixel_font.png")

var grid: PackedInt32Array = PackedInt32Array()
var tiles: Dictionary = {}            # tile type -> Array[Texture2D] (variants)
var water: Array[Texture2D] = []
var corin: Dictionary = {}            # facing -> Array[Texture2D] [idle, walkA, walkB]
var slime_idle: Array[Texture2D] = []

var start_pos: Vector2 = Vector2.ZERO
var pos: Vector2 = Vector2.ZERO       # Corin's feet
var facing: int = 0                   # 0 down, 1 up, 2 right, 3 left
var anim_t: float = 0.0
var moving: bool = false
var t: float = 0.0
var cam: Vector2 = Vector2.ZERO
var state: String = "walk"            # walk | alert | talk
var cooldown: float = 0.0
var alert_t: float = 0.0
var alert_id: String = ""
var npcs: Array = []                  # {id, pos, eng}
var sign_tile: Vector2i = Vector2i(22, 31)

var dlg_lines: Array = []
var dlg_cb: Callable
var dlg_cur: String = ""
var dlg_shown: float = 0.0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build_tiles()
	_build_corin()
	for n in ["SlimeIdle1", "SlimeIdle2"]:
		slime_idle.append(load("res://assets/Slime/%s.png" % n))
	_build_map()
	start_pos = Vector2((24.0 + 0.5) * TILE, 33.0 * TILE)
	pos = start_pos
	for id: String in FIGHTERS:
		var fpos: Vector2 = (FIGHTERS[id]["tile"] as Vector2) * float(TILE)
		var eng = null
		match id:
			"saffron":
				eng = SaffronFight.new(self)
			"katashi":
				eng = KatashiFight.new(self)
			"keras":
				eng = KerasFight.new(self)
		npcs.append({"id": id, "pos": fpos, "eng": eng})
	# dev: godot --path . -- --at=24,20
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--at="):
			var xy: PackedStringArray = arg.substr(5).split(",")
			if xy.size() == 2:
				pos = Vector2((float(xy[0]) + 0.5) * TILE, (float(xy[1]) + 1.0) * TILE)
	_update_cam()


# ------------------------------------------------------------------ art
func _h(x: int, y: int, k: int = 0) -> int:
	return absi((x * 73856093) ^ (y * 19349663) ^ (k * 83492791)) % 1000


func _img() -> Image:
	return Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)


func _tex(img: Image) -> Texture2D:
	return ImageTexture.create_from_image(img)


func _grass_img(v: int) -> Image:
	var img: Image = _img()
	for y in 16:
		for x in 16:
			var r: int = _h(x, y, v + 1)
			var c := Color(0.30, 0.56, 0.28)
			if r < 110:
				c = Color(0.25, 0.49, 0.24)
			elif r > 930:
				c = Color(0.38, 0.65, 0.33)
			img.set_pixel(x, y, c)
	if v == 3:   # a few flowers
		for f in [Vector2i(4, 5), Vector2i(11, 9), Vector2i(7, 12)]:
			img.set_pixel(f.x, f.y, Color(1.0, 0.9, 0.3) if (f.x + v) % 2 == 0 else Color(1.0, 0.55, 0.7))
	return img


func _build_tiles() -> void:
	var grass: Array[Texture2D] = []
	for v in 4:
		grass.append(_tex(_grass_img(v)))
	tiles[T_GRASS] = grass

	var stone: Array[Texture2D] = []
	for v in 2:
		var img: Image = _img()
		for y in 16:
			for x in 16:
				var c := Color(0.58, 0.58, 0.65)
				var off: int = 0 if (y / 8) % 2 == 0 else 8
				if y % 8 == 0 or (x + off) % 16 == 0:
					c = Color(0.45, 0.45, 0.53)
				elif _h(x, y, v + 7) < 80:
					c = Color(0.63, 0.63, 0.70)
				img.set_pixel(x, y, c)
		stone.append(_tex(img))
	tiles[T_STONE] = stone

	var wall: Array[Texture2D] = []
	var wimg: Image = _img()
	for y in 16:
		for x in 16:
			var c := Color(0.30, 0.29, 0.38)
			var off: int = 0 if (y / 8) % 2 == 0 else 8
			if y % 8 == 0 or (x + off) % 16 == 0:
				c = Color(0.20, 0.19, 0.27)
			elif y % 8 == 1:
				c = Color(0.38, 0.37, 0.47)
			wimg.set_pixel(x, y, c)
	wall.append(_tex(wimg))
	tiles[T_WALL] = wall

	var path: Array[Texture2D] = []
	for v in 2:
		var img2: Image = _img()
		for y in 16:
			for x in 16:
				var r: int = _h(x, y, v + 20)
				var c := Color(0.62, 0.47, 0.30)
				if r < 120:
					c = Color(0.55, 0.41, 0.26)
				elif r > 920:
					c = Color(0.70, 0.55, 0.36)
				img2.set_pixel(x, y, c)
		path.append(_tex(img2))
	tiles[T_PATH] = path

	var tree: Array[Texture2D] = []
	var timg: Image = _grass_img(0)
	for y in 16:
		for x in 16:
			if x >= 7 and x <= 8 and y >= 11:
				timg.set_pixel(x, y, Color(0.40, 0.26, 0.13))
			var d: float = Vector2(float(x) - 7.5, float(y) - 6.0).length()
			if d <= 6.4:
				var c := Color(0.12, 0.40, 0.16)
				if _h(x, y, 33) < 220:
					c = Color(0.17, 0.50, 0.21)
				if d > 5.2:
					c = Color(0.08, 0.30, 0.12)
				timg.set_pixel(x, y, c)
	tree.append(_tex(timg))
	tiles[T_TREE] = tree

	var pillar: Array[Texture2D] = []
	var pimg: Image = tiles[T_STONE][0].get_image()
	for y in range(1, 15):
		for x in range(4, 12):
			var c := Color(0.82, 0.82, 0.88)
			if x >= 10:
				c = Color(0.62, 0.62, 0.70)
			if y <= 2 or y >= 13:
				c = Color(0.92, 0.92, 0.96)
			pimg.set_pixel(x, y, c)
	pillar.append(_tex(pimg))
	tiles[T_PILLAR] = pillar

	for f in 2:
		var wi: Image = _img()
		for y in 16:
			for x in 16:
				var c := Color(0.20, 0.42, 0.78)
				if (x + y * 2 + f * 4) % 8 == 0 or (x + y * 2 + f * 4) % 8 == 1:
					c = Color(0.36, 0.60, 0.92)
				wi.set_pixel(x, y, c)
		water.append(_tex(wi))


func _sprite(rows: Array, legs: Array) -> Image:
	var img: Image = Image.create_empty(12, 16, false, Image.FORMAT_RGBA8)
	var all: Array = rows + legs
	for y in all.size():
		var row: String = all[y]
		for x in 12:
			var ch: String = row[x]
			if PAL.has(ch):
				img.set_pixel(x, y, PAL[ch])
	return img


func _build_corin() -> void:
	corin[0] = [_tex(_sprite(SPR_DOWN, LEGS_IDLE)), _tex(_sprite(SPR_DOWN, LEGS_A)), _tex(_sprite(SPR_DOWN, LEGS_B))]
	corin[1] = [_tex(_sprite(SPR_UP, LEGS_IDLE)), _tex(_sprite(SPR_UP, LEGS_A)), _tex(_sprite(SPR_UP, LEGS_B))]
	var right: Array = []
	var left: Array = []
	for legs: Array in [LEGS_SIDE_IDLE, LEGS_SIDE_A, LEGS_SIDE_B]:
		var im: Image = _sprite(SPR_SIDE, legs)
		right.append(_tex(im))
		var fl: Image = im.duplicate()
		fl.flip_x()
		left.append(_tex(fl))
	corin[2] = right
	corin[3] = left


# ------------------------------------------------------------------ map
func _set_t(x: int, y: int, ty: int) -> void:
	if x >= 0 and y >= 0 and x < MAP_W and y < MAP_H:
		grid[y * MAP_W + x] = ty


func _get_t(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= MAP_W or y >= MAP_H:
		return T_TREE
	return grid[y * MAP_W + x]


func _fill(x0: int, y0: int, x1: int, y1: int, ty: int) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			_set_t(x, y, ty)


func _room(x0: int, y0: int, x1: int, y1: int, gate: Rect2i) -> void:
	_fill(x0, y0, x1, y1, T_WALL)
	_fill(x0 + 1, y0 + 1, x1 - 1, y1 - 1, T_STONE)
	_fill(gate.position.x, gate.position.y, gate.end.x - 1, gate.end.y - 1, T_STONE)


func _build_map() -> void:
	grid.resize(MAP_W * MAP_H)
	grid.fill(T_GRASS)
	# keep-clear areas so scattered trees never block anything important
	var clear: Array[Rect2i] = [Rect2i(2, 2, 44, 32)]
	# scattered trees on open grass
	for y in range(2, MAP_H - 2):
		for x in range(2, MAP_W - 2):
			if _h(x, y, 5) < 55:
				_set_t(x, y, T_TREE)
	# border of trees, two thick
	for y in MAP_H:
		for x in MAP_W:
			if x < 2 or y < 2 or x >= MAP_W - 2 or y >= MAP_H - 2:
				_set_t(x, y, T_TREE)
	# plaza + dirt paths
	_fill(16, 12, 32, 24, T_STONE)
	_fill(23, 25, 25, 33, T_PATH)   # south, to the start
	_fill(12, 17, 15, 19, T_PATH)   # west
	_fill(33, 17, 36, 19, T_PATH)   # east
	_fill(23, 9, 25, 11, T_PATH)    # north
	_fill(21, 25, 27, 28, T_PATH)   # little clearing in front of the Slime
	# rooms: west (Saffron), east (Katashi), north (Keras)
	_room(3, 12, 11, 24, Rect2i(11, 17, 1, 3))
	_room(37, 12, 45, 24, Rect2i(37, 17, 1, 3))
	_room(14, 2, 34, 9, Rect2i(23, 9, 3, 1))
	# keep the paths into the rooms clear of trees
	_fill(12, 16, 15, 20, T_PATH)
	_fill(33, 16, 36, 20, T_PATH)
	_fill(22, 9, 26, 11, T_PATH)
	# pillars: plaza corners + the north hall
	for p in [Vector2i(17, 13), Vector2i(31, 13), Vector2i(17, 23), Vector2i(31, 23), Vector2i(16, 4), Vector2i(16, 7), Vector2i(32, 4), Vector2i(32, 7), Vector2i(20, 4), Vector2i(28, 4)]:
		_set_t(p.x, p.y, T_PILLAR)
	# ponds
	_fill(6, 27, 13, 32, T_WATER)
	_fill(35, 27, 42, 32, T_WATER)
	# the room interiors should be clean
	for r in [Rect2i(4, 13, 7, 11), Rect2i(38, 13, 7, 11)]:
		_fill(r.position.x, r.position.y, r.end.x - 1, r.end.y - 1, T_STONE)
	_fill(15, 3, 33, 8, T_STONE)
	for p in [Vector2i(16, 4), Vector2i(16, 7), Vector2i(32, 4), Vector2i(32, 7), Vector2i(20, 4), Vector2i(28, 4)]:
		_set_t(p.x, p.y, T_PILLAR)
	# the start and the Slime's spot are open grass/dirt
	_fill(22, 30, 26, 33, T_PATH)


func _is_solid_tile(tx: int, ty: int) -> bool:
	var ty_: int = _get_t(tx, ty)
	return ty_ == T_WALL or ty_ == T_TREE or ty_ == T_WATER or ty_ == T_PILLAR


func _npc_visible(id: String) -> bool:
	return results.get(id, "") != "won"


func _blocked(p: Vector2) -> bool:
	var feet := Rect2(p.x - 7.0, p.y - 6.0, 14.0, 6.0)
	for corner in [feet.position, Vector2(feet.end.x, feet.position.y), Vector2(feet.position.x, feet.end.y), feet.end]:
		if _is_solid_tile(int(floorf(corner.x / TILE)), int(floorf(corner.y / TILE))):
			return true
	var sg := Rect2(float(sign_tile.x * TILE) + 4.0, float(sign_tile.y * TILE) + 8.0, 24.0, 20.0)
	if feet.intersects(sg):
		return true
	for n: Dictionary in npcs:
		if _npc_visible(n["id"]) and feet.intersects(_npc_solid(n)):
			return true
	return false


func _npc_solid(n: Dictionary) -> Rect2:
	var np: Vector2 = n["pos"]
	return Rect2(np.x - 9.0, np.y - 8.0, 18.0, 8.0)


func _npc_trigger(n: Dictionary) -> Rect2:
	var np: Vector2 = n["pos"]
	return Rect2(np.x - 22.0, np.y - 26.0, 44.0, 34.0)


# ------------------------------------------------------------------ input / state
func _key(k1: Key, k2: Key) -> bool:
	return Input.is_physical_key_pressed(k1) or Input.is_physical_key_pressed(k2)


func _input(ev: InputEvent) -> void:
	var e := ev as InputEventKey
	if e == null or not e.pressed or e.echo:
		return
	var k: int = e.physical_keycode
	if not (k == KEY_Z or k == KEY_ENTER or k == KEY_SPACE):
		return
	match state:
		"walk":
			_interact()
		"talk":
			if dlg_shown < dlg_cur.length():
				dlg_shown = dlg_cur.length()
			else:
				_next_line()


func _say(lines: Array, cb: Callable = Callable()) -> void:
	dlg_lines = lines.duplicate()
	dlg_cb = cb
	state = "talk"
	_next_line()


func _next_line() -> void:
	if dlg_lines.is_empty():
		state = "walk"
		if dlg_cb.is_valid():
			dlg_cb.call()
		return
	dlg_cur = dlg_lines.pop_front()
	dlg_shown = 0.0


func _facing_vec() -> Vector2:
	match facing:
		0:
			return Vector2(0, 1)
		1:
			return Vector2(0, -1)
		2:
			return Vector2(1, 0)
		_:
			return Vector2(-1, 0)


func _interact() -> void:
	var probe := Rect2(pos + _facing_vec() * 16.0 - Vector2(10, 14), Vector2(20, 18))
	var sg := Rect2(float(sign_tile.x * TILE), float(sign_tile.y * TILE) + 4.0, 32.0, 28.0)
	if probe.intersects(sg):
		_say(["* Arrow keys / WASD: walk.  Shift: run.", "* Z: talk or read.  Bump into someone to fight them."])
		return
	for n: Dictionary in npcs:
		var id: String = n["id"]
		if _npc_visible(id) and results.get(id, "") == "spared" and probe.intersects(_npc_trigger(n)):
			_say(FIGHTERS[id]["spared"])
			return


func _check_encounters() -> void:
	if cooldown > 0.0:
		return
	var feet := Rect2(pos.x - 7.0, pos.y - 6.0, 14.0, 6.0)
	for n: Dictionary in npcs:
		var id: String = n["id"]
		if not _npc_visible(id) or results.get(id, "") != "":
			continue
		if feet.intersects(_npc_trigger(n)):
			alert_id = id
			alert_t = 0.5
			state = "alert"
			moving = false
			return


func _start_encounter() -> void:
	var id: String = alert_id
	_say(FIGHTERS[id]["pre"], func(): encounter.emit(id))


## Called by the game after a fight. outcome: won / spared / fled / lost
func resume(id: String, outcome: String) -> void:
	state = "walk"
	cooldown = 1.5
	if outcome == "won" or outcome == "spared":
		results[id] = outcome
		for n: Dictionary in npcs:
			if n["id"] == id and id == "keras" and outcome == "spared":
				n["eng"].mode = "spared"   # calm eyes
	var np: Vector2 = Vector2.ZERO
	for n2: Dictionary in npcs:
		if n2["id"] == id:
			np = n2["pos"]
	if outcome == "lost":
		pos = start_pos
		facing = 1
		_say(["* Corin gets back up and returns to the start."])
	elif outcome == "fled" or outcome == "spared":
		# step back out of the trigger so you are not pulled straight back in
		var away: Vector2 = (pos - np).normalized()
		if away == Vector2.ZERO:
			away = Vector2(0, 1)
		for d in [56.0, 72.0, 90.0, 40.0]:
			var cand: Vector2 = pos + away * d
			if not _blocked(cand):
				pos = cand
				break


# ------------------------------------------------------------------ process
func _update_cam() -> void:
	var world := Vector2(float(MAP_W * TILE), float(MAP_H * TILE))
	cam = (pos - SCREEN * 0.5 + Vector2(0, -16)).clamp(Vector2.ZERO, world - SCREEN)
	cam = Vector2(roundf(cam.x), roundf(cam.y))
	position = -cam


func _process(delta: float) -> void:
	t += delta
	cooldown = maxf(0.0, cooldown - delta)
	for n: Dictionary in npcs:
		if n["eng"] != null:
			n["eng"].tick(delta)
	match state:
		"walk":
			_move(delta)
			_check_encounters()
		"alert":
			alert_t -= delta
			if alert_t <= 0.0:
				_start_encounter()
		"talk":
			dlg_shown = minf(float(dlg_cur.length()), dlg_shown + delta * 45.0)
	_update_cam()
	queue_redraw()


func _move(delta: float) -> void:
	var dir := Vector2(float(_key(KEY_RIGHT, KEY_D)) - float(_key(KEY_LEFT, KEY_A)), float(_key(KEY_DOWN, KEY_S)) - float(_key(KEY_UP, KEY_W)))
	moving = dir.length() > 0.0
	if not moving:
		anim_t = 0.0
		return
	dir = dir.normalized()
	var spd: float = RUN_SPEED if (_key(KEY_SHIFT, KEY_X)) else WALK_SPEED
	if absf(dir.x) > absf(dir.y) + 0.01:
		facing = 2 if dir.x > 0.0 else 3
	elif absf(dir.y) > 0.0:
		facing = 0 if dir.y > 0.0 else 1
	anim_t += delta * (spd / WALK_SPEED)
	var nx: Vector2 = pos + Vector2(dir.x * spd * delta, 0)
	if not _blocked(nx):
		pos = nx
	var ny: Vector2 = pos + Vector2(0, dir.y * spd * delta)
	if not _blocked(ny):
		pos = ny


# ------------------------------------------------------------------ drawing
func _draw() -> void:
	var x0: int = maxi(0, int(cam.x / TILE))
	var y0: int = maxi(0, int(cam.y / TILE))
	var x1: int = mini(MAP_W - 1, int((cam.x + SCREEN.x) / TILE))
	var y1: int = mini(MAP_H - 1, int((cam.y + SCREEN.y) / TILE))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var ty: int = _get_t(x, y)
			var tex: Texture2D
			if ty == T_WATER:
				tex = water[int(t * 2.0) % 2]
			else:
				var variants: Array = tiles[ty]
				var v: int = 0
				if ty == T_GRASS:
					var r: int = _h(x, y, 2)
					v = 3 if r < 25 else r % 3
				elif variants.size() > 1:
					v = _h(x, y, 4) % variants.size()
				tex = variants[v]
			draw_texture_rect(tex, Rect2(float(x * TILE), float(y * TILE), float(TILE), float(TILE)), false)

	# y-sorted things: sign, fighters, Corin
	var items: Array = []
	items.append({"y": float(sign_tile.y * TILE + 28), "kind": "sign"})
	for n: Dictionary in npcs:
		if _npc_visible(n["id"]):
			items.append({"y": (n["pos"] as Vector2).y, "kind": "npc", "n": n})
	items.append({"y": pos.y, "kind": "corin"})
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["y"]) < float(b["y"]))
	for it: Dictionary in items:
		match it["kind"]:
			"sign":
				_draw_sign()
			"npc":
				_draw_npc(it["n"])
			"corin":
				_draw_corin()

	if state == "alert":
		for n: Dictionary in npcs:
			if n["id"] == alert_id:
				var np: Vector2 = n["pos"]
				PixelUI.draw(self, pixel_font, "!", np + Vector2(-8, -72 - 4.0 * sin(t * 30.0)), 36, Color(1, 0.2, 0.2), 16.0, HORIZONTAL_ALIGNMENT_CENTER)
	if state == "talk":
		_draw_dialog()


func _draw_corin() -> void:
	var frames: Array = corin[facing]
	var f: int = 0
	if moving:
		f = 1 if int(anim_t * 6.0) % 2 == 0 else 2
	var tex: Texture2D = frames[f]
	var bob: float = -1.0 if (moving and f != 0) else 0.0
	draw_circle(pos + Vector2(0, -2), 9.0, Color(0, 0, 0, 0.25))   # shadow
	draw_texture_rect(tex, Rect2(roundf(pos.x - 12.0), roundf(pos.y - 32.0 + bob), 24.0, 32.0), false)


func _draw_sign() -> void:
	var p := Vector2(float(sign_tile.x * TILE), float(sign_tile.y * TILE))
	draw_rect(Rect2(p + Vector2(14, 14), Vector2(4, 16)), Color(0.40, 0.26, 0.13))
	draw_rect(Rect2(p + Vector2(4, 4), Vector2(24, 14)), Color(0.62, 0.42, 0.20))
	draw_rect(Rect2(p + Vector2(4, 4), Vector2(24, 14)), Color(0.35, 0.22, 0.10), false, 2.0)
	for i in 2:
		draw_line(p + Vector2(8, 9 + 4 * i), p + Vector2(24, 9 + 4 * i), Color(0.30, 0.18, 0.08), 2.0)


func _draw_npc(n: Dictionary) -> void:
	var id: String = n["id"]
	var np: Vector2 = n["pos"]
	draw_circle(np + Vector2(0, -2), 14.0, Color(0, 0, 0, 0.25))
	if id == "slime":
		var tex: Texture2D = slime_idle[int(t * 2.0) % 2]
		var size: Vector2 = tex.get_size() * 3.0
		var tint := Color(1, 1, 0.8) if results.get(id, "") == "spared" else Color.WHITE
		draw_texture_rect(tex, Rect2(np - Vector2(size.x * 0.5, size.y), size), false, tint)
		return
	var sc: float = FIGHTER_SCALE
	draw_set_transform(np - Vector2(320.0, 184.0) * sc, 0.0, Vector2(sc, sc))
	n["eng"].draw_boss(Vector2.ZERO, 1.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_dialog() -> void:
	var box := Rect2(cam + Vector2(40, 340), Vector2(560, 120))
	draw_rect(box, Color.BLACK)
	draw_rect(box, Color.WHITE, false, 4.0)
	PixelUI.paragraph(self, pixel_font, dlg_cur, box.position + Vector2(18, 14), box.size.x - 36.0, 20, Color.WHITE, int(dlg_shown))
