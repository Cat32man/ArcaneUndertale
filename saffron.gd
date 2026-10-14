extends RefCounted
## Saffron (Vae'kes boss): attack engine + placeholder art, all drawn in code.
## The battle node owns the soul/HP; this object drives attacks and draws them.
##
## A normal turn is a CHAIN of 2-4 short attacks:
##   throw         seeking dagger that accelerates
##   punch         fist hits a random third of the arena (row or column), afterimage lingers ~1s
##   circle_push   ring of swords closes in -> be near the CENTER
##   outside_push  ring of swords expands out -> be near the EDGES
##   waltz         Blade Waltz: blades stab inward from the rim one after another, clockwise, on a steady beat
## Every few turns he does a BIG attack: the arena becomes a circle (blue-heart style:
## left/right run around the rim, up jumps toward the middle). Inside it:
##   swords from the middle, fists from the edge, seeking daggers, random edge daggers,
##   and the Rim Chorus: fists erupt around the rim in a fixed sweep, twice (second sweep starts in the safe gap).

const CENTER := Vector2(320, 265)
const HALF := Vector2(110, 75)          # normal arena half-size
const CIRCLE_R := 72.0
const REST_R := 64.0                    # soul radius while standing on the rim
const BOSS_BASE := Vector2(320, 184)    # bottom-center of Saffron
const HAND := Vector2(354, 120)         # where thrown daggers appear

const JUMP_V := 380.0
const JUMP_G := 1500.0
const BIG_DUR := 9.0
const FIST_DEPTH := 34.0
const FIST_HALFW := 15.0
# Punch afterimage: punch -> slight ghost effect -> holds ~1s -> rapidly disappears
const GHOST_IN := 0.2                   # solid fist blurs into a ghost
const GHOST_HOLD := 1.0                 # ghost stays put and keeps hurting
const GHOST_OUT := 0.15                 # then vanishes fast (harmless while vanishing)
const STRIKE_T := 0.15

const D_DAGGER := 14
const D_PUNCH := 18
const D_PUSH := 15
const D_SWORD := 11
const D_FIST := 14

var b   # the battle node (untyped on purpose: we call into it dynamically)

var circle_mode: bool = false
var morph: float = 0.0                  # 0 = square arena, 1 = full circle
var phase: String = "chain"             # chain | big
var queue: Array = []
var cur: Dictionary = {}
var gap: float = 0.0
var linger: float = 0.0
var big_phase: String = "morph_in"
var big_t: float = 0.0
var big_spawn: float = 0.0
var turn_t: float = 0.0
var turns_since_big: int = 0
var finished: bool = false
var last_kind: String = ""
var last_big: String = ""
var clock: float = 0.0
var form: int = 1                       # 2 = simulacra form
var clone_alpha: float = 0.0

const CLONE_DX := 86.0                 # simulacra stand this far left/right of Saffron

var daggers: Array = []
var swords: Array = []
var fists: Array = []
var bands: Array = []
var rings: Array = []
var blades: Array = []

# polar soul state for circle mode
var a: float = PI * 0.5
var r: float = REST_R
var vr: float = 0.0

var pose: String = "idle"
var pose_t: float = 0.0


func _init(battle) -> void:
	b = battle


# ------------------------------------------------------------------ geometry
func arena_rect() -> Rect2:
	return Rect2(CENTER - HALF, HALF * 2.0)


func box_rect() -> Rect2:
	var half: Vector2 = HALF.lerp(Vector2(CIRCLE_R, CIRCLE_R), morph)
	return Rect2(CENTER - half, half * 2.0)


func _down(k1: Key, k2: Key) -> bool:
	return Input.is_physical_key_pressed(k1) or Input.is_physical_key_pressed(k2)


# ------------------------------------------------------------------ turn control
func start_turn() -> void:
	daggers.clear()
	swords.clear()
	fists.clear()
	bands.clear()
	rings.clear()
	blades.clear()
	queue.clear()
	cur = {}
	gap = 0.35
	linger = 0.0
	turn_t = 0.0
	finished = false
	morph = 0.0
	circle_mode = false
	pose = "idle"
	b.soul = CENTER
	var big: bool = turns_since_big >= 3 and (turns_since_big >= 6 or randf() < 0.3)
	if big:
		phase = "big"
		big_phase = "morph_in"
		big_t = 0.0
		turns_since_big = 0
	else:
		phase = "chain"
		turns_since_big += 1
		for i in (randi_range(4, 5) if form == 2 else randi_range(3, 4)):
			queue.append(_pick_kind())


func _pick_kind() -> String:
	var kinds: Array = ["throw", "punch", "circle_push", "outside_push", "waltz"]
	var k: String = kinds.pick_random()
	while k == last_kind:
		k = kinds.pick_random()
	last_kind = k
	return k


func _clear_all() -> void:
	daggers.clear()
	swords.clear()
	fists.clear()
	bands.clear()
	rings.clear()
	blades.clear()
	circle_mode = false
	morph = 0.0


func tick(delta: float) -> void:
	clock += delta
	if form == 2:
		clone_alpha = minf(1.0, clone_alpha + delta * 1.2)


func begin_form2() -> void:
	form = 2
	clone_alpha = 0.0
	b.add_shake(0.8)


func update(delta: float) -> bool:
	turn_t += delta
	pose_t = maxf(0.0, pose_t - delta)
	if phase == "chain":
		_move_soul_rect(delta, arena_rect().grow(-10.0))
		_update_chain(delta)
	else:
		_update_big(delta)
	_update_daggers(delta)
	_update_bands(delta)
	_update_rings(delta)
	_update_blades(delta)
	_update_swords(delta)
	_update_fists(delta)
	if turn_t > 24.0:
		_clear_all()
		finished = true
	return finished


# ------------------------------------------------------------------ soul movement
func _move_soul_rect(delta: float, inner: Rect2) -> void:
	var spd: float = b.SOUL_SPEED_HASTE if b.haste_left > 0 else b.SOUL_SPEED
	var dir := Vector2(
		float(_down(KEY_RIGHT, KEY_D)) - float(_down(KEY_LEFT, KEY_A)),
		float(_down(KEY_DOWN, KEY_S)) - float(_down(KEY_UP, KEY_W)))
	if dir.length() > 0.0:
		dir = dir.normalized()
	if _down(KEY_X, KEY_SHIFT):
		spd *= 0.5
	var p: Vector2 = b.soul + dir * spd * delta
	b.soul = p.clamp(inner.position, inner.end)


func _move_soul_circle(delta: float) -> void:
	var spd: float = b.SOUL_SPEED_HASTE if b.haste_left > 0 else b.SOUL_SPEED
	if _down(KEY_X, KEY_SHIFT):
		spd *= 0.5
	# right = counter-clockwise around the rim; keeps working upside down
	var dx: float = float(_down(KEY_RIGHT, KEY_D)) - float(_down(KEY_LEFT, KEY_A))
	a -= dx * (spd / CIRCLE_R) * delta
	var up: bool = _down(KEY_UP, KEY_W)
	var grounded: bool = r >= REST_R - 0.5
	if up and grounded:
		vr = -JUMP_V
	var g: float = JUMP_G
	if vr < 0.0 and not up:
		g *= 2.4   # let go early -> short hop
	vr += g * delta
	r += vr * delta
	if r >= REST_R:
		r = REST_R
		vr = minf(vr, 0.0) if vr < 0.0 else 0.0
	if r < 4.0:
		r = 4.0
		vr = maxf(vr, 0.0)
	b.soul = CENTER + Vector2(cos(a), sin(a)) * r


func _clamp_morph_soul() -> void:
	# while the arena morphs, gently pull the soul inside the shrinking shape
	var d: Vector2 = b.soul - CENTER
	var lim: float = lerpf(125.0, REST_R, morph)
	if d.length() > lim:
		b.soul = CENTER + d.normalized() * lim


# ------------------------------------------------------------------ chain attacks
func _update_chain(delta: float) -> void:
	if cur.is_empty():
		if not queue.is_empty():
			gap -= delta
			if gap <= 0.0:
				_begin_attack(queue.pop_front())
		elif bands.is_empty() and rings.is_empty() and daggers.is_empty() and blades.is_empty():
			linger += delta
			if linger >= 0.5:
				finished = true
		return
	_run_attack(delta)


func _begin_attack(kind: String) -> void:
	cur = {"kind": kind, "t": 0.0, "spawned": 0, "n": 1}
	match kind:
		"throw":
			cur["n"] = randi_range(2, 3)
		"punch":
			_spawn_band()
			pose = "punch"
			pose_t = 0.8
		"circle_push":
			rings.append({"mode": "in", "t": 0.0, "tele": 0.4, "travel": 1.1, "hold": 0.25})
			pose = "push"
			pose_t = 1.2
		"outside_push":
			rings.append({"mode": "out", "t": 0.0, "tele": 0.45, "travel": 0.9, "hold": 0.4})
			pose = "push"
			pose_t = 1.2
		"waltz":
			cur["end"] = _spawn_waltz()
			pose = "push"
			pose_t = 2.0


func _end_attack() -> void:
	cur = {}
	gap = randf_range(0.15, 0.4)


func _run_attack(delta: float) -> void:
	cur["t"] += delta
	var t: float = cur["t"]
	match cur["kind"]:
		"throw":
			var n: int = cur["n"]
			var sp: int = cur["spawned"]
			if sp < n and t >= float(sp) * 0.75:
				_spawn_seek_dagger()
				cur["spawned"] = sp + 1
			elif sp >= n and t >= float(n - 1) * 0.75 + 0.35:
				_end_attack()
		"punch":
			if t >= 0.95 / b._slow() + 0.15:
				_end_attack()
		"circle_push":
			if t >= 1.6:
				_end_attack()
		"outside_push":
			if t >= 1.5:
				_end_attack()
		"waltz":
			if t >= float(cur["end"]):
				_end_attack()


# ---- punch bands
func _spawn_band() -> void:
	var ar: Rect2 = arena_rect()
	var vertical: bool = randf() < 0.5
	var sp: Vector2 = b.soul
	# which third of the arena is the SOUL standing in?
	var f: float = ((sp.x - ar.position.x) / ar.size.x) if vertical else ((sp.y - ar.position.y) / ar.size.y)
	var si: int = clampi(int(f * 3.0), 0, 2)
	var idxs: Array = []
	if form == 2:
		# two fists -> one third stays safe, and it is always right next to the SOUL's
		# third, so there is time to reach it
		var safe: int = 1 if si != 1 else [0, 2].pick_random()
		for k in 3:
			if k != safe:
				idxs.append(k)
	else:
		idxs.append(si if randf() < 0.7 else randi_range(0, 2))
	for k: int in idxs:
		var rect: Rect2
		if vertical:
			var w: float = ar.size.x / 3.0
			rect = Rect2(ar.position.x + float(k) * w, ar.position.y, w, ar.size.y)
		else:
			var h: float = ar.size.y / 3.0
			rect = Rect2(ar.position.x, ar.position.y + float(k) * h, ar.size.x, h)
		bands.append({"rect": rect, "t": 0.0, "tele": 0.95 / b._slow(), "vertical": vertical})


func _update_bands(delta: float) -> void:
	var keep: Array = []
	for bd: Dictionary in bands:
		bd["t"] += delta
		var t: float = bd["t"]
		var tele: float = bd["tele"]
		var rect: Rect2 = bd["rect"]
		if t >= tele and not bd.has("struck"):
			bd["struck"] = true
			b.add_shake(0.6)
		var gt: float = t - tele - STRIKE_T   # time since the strike ended
		if t >= tele and gt < GHOST_IN + GHOST_HOLD and rect.grow(1.0).has_point(b.soul):
			b.hurt(D_PUNCH)
		if gt < GHOST_IN + GHOST_HOLD + GHOST_OUT:
			keep.append(bd)
	bands = keep


# ---- push rings
func _ring_radius(rg: Dictionary) -> float:
	var t: float = rg["t"]
	var tele: float = rg["tele"]
	var p: float = clampf((t - tele) / float(rg["travel"]), 0.0, 1.0)
	if rg["mode"] == "in":
		return lerpf(165.0, 26.0, p)
	return lerpf(0.0, 60.0, p)


func _update_rings(delta: float) -> void:
	var keep: Array = []
	for rg: Dictionary in rings:
		rg["t"] += delta
		var t: float = rg["t"]
		var tele: float = rg["tele"]
		var end_t: float = tele + float(rg["travel"]) + float(rg["hold"])
		if t >= tele and t < end_t:
			var rad: float = _ring_radius(rg)
			var d: float = (b.soul as Vector2).distance_to(CENTER)
			if rg["mode"] == "in" and d > rad - 3.0:
				b.hurt(D_PUSH)
			elif rg["mode"] == "out" and d < rad + 3.0:
				b.hurt(D_PUSH)
		if t < end_t:
			keep.append(rg)
	rings = keep


# ---- Blade Waltz (rhythmic): 16 points around the arena edge, clockwise from the top-left.
# One blade stabs toward the center on every beat, in order - the same every time.
# Form 2: the simulacrum on the other side joins in, so two blades stab each beat.
func _perimeter_point(d: float) -> Vector2:
	var ar: Rect2 = arena_rect()
	var w: float = ar.size.x
	var h: float = ar.size.y
	var m: float = fposmod(d, 2.0 * (w + h))
	if m < w:
		return Vector2(ar.position.x + m, ar.position.y)
	m -= w
	if m < h:
		return Vector2(ar.end.x, ar.position.y + m)
	m -= h
	if m < w:
		return Vector2(ar.end.x - m, ar.end.y)
	m -= w
	return Vector2(ar.position.x, ar.end.y - m)


func _spawn_waltz() -> float:
	var ar: Rect2 = arena_rect()
	var per: float = 2.0 * (ar.size.x + ar.size.y)
	var n: int = 16
	var beat: float = 0.3 if form == 2 else 0.22
	var count: int = n / 2 if form == 2 else n
	var start: float = randf_range(0.0, per)   # where the waltz begins varies; the order never does
	for i in count:
		var idxs: Array = [i]
		if form == 2:
			idxs.append(i + n / 2)
		for k: int in idxs:
			var pt: Vector2 = _perimeter_point(start + per * float(k) / float(n))
			var dirv: Vector2 = (CENTER - pt).normalized()
			blades.append({"p": pt, "dir": dirv, "t": -0.5 - float(i) * beat, "tele": 0.5, "len": 85.0})
	return 0.5 + float(count - 1) * beat + 0.5


func _blade_ext(bl: Dictionary) -> float:
	var t: float = float(bl["t"]) - float(bl["tele"])
	if t < 0.0:
		return 0.0
	if t < 0.1:
		return t / 0.1
	if t < 0.25:
		return 1.0
	if t < 0.4:
		return 1.0 - (t - 0.25) / 0.15
	return -1.0


func _update_blades(delta: float) -> void:
	var keep: Array = []
	for bl: Dictionary in blades:
		bl["t"] += delta
		var ext: float = _blade_ext(bl)
		if ext < 0.0:
			continue
		if ext > 0.3:
			var p: Vector2 = bl["p"]
			var tip: Vector2 = p + (bl["dir"] as Vector2) * float(bl["len"]) * ext
			var near: Vector2 = Geometry2D.get_closest_point_to_segment(b.soul, p, tip)
			if near.distance_to(b.soul) < 6.0:
				b.hurt(D_SWORD + 3)
			if not bl.has("struck"):
				bl["struck"] = true
				b.add_shake(0.08)
		keep.append(bl)
	blades = keep


# ---- daggers
func _spawn_dagger(pos: Vector2, ang: float, seek: bool, wind: float, speed: float) -> void:
	daggers.append({"pos": pos, "ang": ang, "t": 0.0, "seek": seek, "wind": wind, "speed": speed, "life": 3.6})


func _spawn_seek_dagger() -> void:
	var hands: Array = [HAND]
	if form == 2:
		hands.append(HAND + Vector2(-CLONE_DX, 0))
		hands.append(HAND + Vector2(CLONE_DX, 0))
	for i in hands.size():
		var o: Vector2 = hands[i]
		_spawn_dagger(o, ((b.soul as Vector2) - o).angle(), true, 0.4 + float(i) * 0.18, 0.0)
	pose = "throw"
	pose_t = 0.45


func _update_daggers(delta: float) -> void:
	var slow: float = b._slow()
	var keep: Array = []
	for d: Dictionary in daggers:
		d["t"] += delta
		var t: float = d["t"]
		var wind: float = d["wind"]
		var ang: float = d["ang"]
		var pos: Vector2 = d["pos"]
		if d["seek"]:
			var turn: float = 7.0 if t < wind else 1.0
			var want: float = ((b.soul as Vector2) - pos).angle()
			ang += clampf(angle_difference(ang, want), -turn * delta, turn * delta)
			d["ang"] = ang
		var dir := Vector2(cos(ang), sin(ang))
		if t >= wind:
			var spd: float = d["speed"]
			if d["seek"]:
				spd = minf(100.0 + 190.0 * (t - wind), 470.0)   # keeps getting faster
			pos += dir * spd * slow * delta
			d["pos"] = pos
		var hit: bool = false
		if t >= wind and (pos + dir * 10.0).distance_to(b.soul) < 7.0:
			hit = b.hurt(D_DAGGER)
		var alive: bool = t < float(d["life"]) + wind and not hit
		if alive and Rect2(-40, -40, 720, 560).has_point(pos):
			keep.append(d)
	daggers = keep


# ------------------------------------------------------------------ big attack
func _update_big(delta: float) -> void:
	big_t += delta
	pose = "big"
	match big_phase:
		"morph_in":
			morph = clampf(big_t / 0.7, 0.0, 1.0)
			b.rumble(0.35)
			_move_soul_rect(delta, box_rect().grow(-10.0))
			_clamp_morph_soul()
			if big_t >= 0.7:
				big_phase = "play"
				big_t = 0.0
				circle_mode = true
				morph = 1.0
				var d: Vector2 = (b.soul as Vector2) - CENTER
				if d.length() < 2.0:
					d = Vector2(0, 1)
				a = d.angle()
				r = minf(d.length(), REST_R)
				vr = 0.0
				big_spawn = 0.7
		"play":
			_move_soul_circle(delta)
			big_spawn -= delta
			if big_t < BIG_DUR and big_spawn <= 0.0:
				_spawn_big_attack()
				big_spawn = randf_range(0.8, 1.45)
			var clear: bool = swords.is_empty() and fists.is_empty() and daggers.is_empty()
			if big_t >= BIG_DUR + 0.2 and (clear or big_t > BIG_DUR + 3.0):
				big_phase = "morph_out"
				big_t = 0.0
				circle_mode = false
				swords.clear()
				fists.clear()
				daggers.clear()
		"morph_out":
			morph = 1.0 - clampf(big_t / 0.6, 0.0, 1.0)
			b.rumble(0.25)
			_move_soul_rect(delta, box_rect().grow(-10.0))
			if big_t >= 0.6:
				morph = 0.0
				pose = "idle"
				finished = true


func _spawn_big_attack() -> void:
	var opts: Array = ["swords", "fists", "seek", "edge", "chorus"]
	var k: String = opts.pick_random()
	while k == last_big:
		k = opts.pick_random()
	last_big = k
	var sa: float = ((b.soul as Vector2) - CENTER).angle()
	match k:
		"swords":
			for i in randi_range(3, 4):
				var ang: float = sa + randf_range(-0.3, 0.3) if i == 0 else randf() * TAU
				swords.append({"ang": ang, "t": -float(i) * 0.12, "d": 0.0})
		"fists":
			for i in (randi_range(2, 3) if form == 2 else randi_range(1, 2)):
				var ang2: float = sa + randf_range(-0.4, 0.4) if i == 0 else sa + PI * randf_range(0.5, 1.5)
				fists.append({"ang": ang2, "t": 0.0, "tele": 0.6 / b._slow()})
		"chorus":
			_spawn_chorus(sa)
		"seek":
			_spawn_seek_dagger()
		"edge":
			var n: int = randi_range(5, 8) if form == 2 else randi_range(3, 5)
			var stagger: float = 0.15 if form == 2 else 0.22
			for i in n:
				var ang3: float = randf() * TAU
				var pos: Vector2 = CENTER + Vector2(cos(ang3), sin(ang3)) * (CIRCLE_R + 2.0)
				var aim: Vector2 = CENTER + Vector2(randf_range(-28, 28), randf_range(-28, 28))
				_spawn_dagger(pos, (aim - pos).angle(), false, 0.45 + float(i) * stagger, 200.0)


# Rim Chorus (rhythmic): six fists erupt around the rim one after another (a fixed 0.9 rad apart),
# leaving one safe arc. Then a second sweep runs the OTHER way starting from that safe arc.
func _spawn_chorus(sa: float) -> void:
	var step: float = 0.9
	var beat: float = 0.3
	var start: float = sa + 0.35
	for i in 6:
		fists.append({"ang": start + step * float(i), "t": -float(i) * beat, "tele": 0.5})
	var safe_c: float = start + step * 5.0 + (TAU - step * 5.0) * 0.5   # middle of the arc the first sweep skips
	var second: float = 6.0 * beat + 0.9
	for i in 6:
		fists.append({"ang": safe_c - step * float(i), "t": -(second + float(i) * beat), "tele": 0.5})
	if form == 2:   # a simulacrum adds a mirrored first sweep
		for i in 6:
			fists.append({"ang": start + PI - step * float(i), "t": -float(i) * beat, "tele": 0.5})


func _update_swords(delta: float) -> void:
	var slow: float = b._slow()
	var keep: Array = []
	for s: Dictionary in swords:
		s["t"] += delta
		var t: float = s["t"]
		var ang: float = s["ang"]
		var dir := Vector2(cos(ang), sin(ang))
		if t >= 0.55:
			s["d"] += 250.0 * slow * delta
			var d: float = s["d"]
			var p0: Vector2 = CENTER + dir * maxf(d - 24.0, 0.0)
			var p1: Vector2 = CENTER + dir * d
			var near: Vector2 = Geometry2D.get_closest_point_to_segment(b.soul, p0, p1)
			if near.distance_to(b.soul) < 7.0:
				b.hurt(D_SWORD)
		if float(s["d"]) < CIRCLE_R + 18.0:
			keep.append(s)
	swords = keep


func _fist_depth(f: Dictionary) -> float:
	var t: float = float(f["t"]) - float(f["tele"])
	if t < 0.0:
		return 0.0
	if t < 0.08:
		return FIST_DEPTH * t / 0.08
	if t < 0.43:
		return FIST_DEPTH
	if t < 0.68:
		return FIST_DEPTH * (1.0 - (t - 0.43) / 0.25)
	return -1.0


func _update_fists(delta: float) -> void:
	var keep: Array = []
	for f: Dictionary in fists:
		f["t"] += delta
		var depth: float = _fist_depth(f)
		if depth < 0.0:
			continue
		if depth >= FIST_DEPTH * 0.9 and not f.has("thud"):
			f["thud"] = true
			b.add_shake(0.3)
		if depth > 6.0:
			var d: Vector2 = (b.soul as Vector2) - CENTER
			var rr: float = d.length()
			var tang: float = absf(angle_difference(float(f["ang"]), d.angle())) * rr
			if tang < FIST_HALFW + 4.0 and rr > CIRCLE_R - depth - 4.0:
				b.hurt(D_FIST)
		keep.append(f)
	fists = keep


# ------------------------------------------------------------------ drawing: arena
func draw_arena() -> void:
	var half: Vector2 = HALF.lerp(Vector2(CIRCLE_R, CIRCLE_R), morph)
	var ex: float = 2.0 / lerpf(24.0, 2.0, morph)
	var pts := PackedVector2Array()
	for i in 72:
		var t: float = TAU * float(i) / 72.0
		var c: float = cos(t)
		var s: float = sin(t)
		pts.append(CENTER + Vector2(signf(c) * pow(absf(c), ex) * half.x, signf(s) * pow(absf(s), ex) * half.y))
	b.draw_colored_polygon(pts, Color.BLACK)
	pts.append(pts[0])
	b.draw_polyline(pts, Color.WHITE, 4.0)


# ------------------------------------------------------------------ drawing: attacks
func draw_attacks() -> void:
	for bd: Dictionary in bands:
		_draw_band(bd)
	for rg: Dictionary in rings:
		_draw_ring(rg)
	for s: Dictionary in swords:
		_draw_sword_ray(s)
	for f: Dictionary in fists:
		_draw_fist(f)
	for d: Dictionary in daggers:
		_draw_dagger(d)
	for bl: Dictionary in blades:
		_draw_blade(bl)


func _fist_glyph(c: Vector2, dir: Vector2, col: Color) -> void:
	# a chunky fist coming in along `dir` (unit), centered on c, with a forearm behind it
	var ang: float = dir.angle()
	b.draw_set_transform(c, ang, Vector2.ONE)
	b.draw_rect(Rect2(-90, -11, 80, 22), Color(col, col.a * 0.8))          # forearm
	b.draw_rect(Rect2(-12, -20, 36, 40), col)                              # fist
	for i in 4:
		b.draw_line(Vector2(8, -15 + 10 * i), Vector2(24, -15 + 10 * i), Color(0, 0, 0, col.a * 0.7), 2.0)
	b.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_band(bd: Dictionary) -> void:
	var t: float = bd["t"]
	var tele: float = bd["tele"]
	var rect: Rect2 = bd["rect"]
	var vertical: bool = bd["vertical"]
	var dir: Vector2 = Vector2(0, 1) if vertical else Vector2(1, 0)
	var ctr: Vector2 = rect.get_center()
	if t < tele:
		var blink: float = 0.5 + 0.5 * sin(t * 28.0)
		b.draw_rect(rect, Color(1, 0.2, 0.2, 0.08 + 0.12 * blink))
		b.draw_rect(rect.grow(-2), Color(1, 0.3, 0.3, 0.5 + 0.4 * blink), false, 2.0)
	elif t < tele + STRIKE_T:
		b.draw_rect(rect, Color(1, 1, 1, 0.9))
		_fist_glyph(ctr, dir, Color(0.85, 0.75, 0.65, 1.0))
	else:
		var gt: float = t - tele - STRIKE_T
		var al: float
		var mix: float = clampf(gt / GHOST_IN, 0.0, 1.0)
		if gt < GHOST_IN:
			al = lerpf(0.9, 0.5, mix)                       # solid -> ghostly
		elif gt < GHOST_IN + GHOST_HOLD:
			al = 0.5 + 0.05 * sin(gt * 18.0)                # steady, faint shimmer
		else:
			al = 0.5 * (1.0 - (gt - GHOST_IN - GHOST_HOLD) / GHOST_OUT)   # rapid fade
		var col: Color = Color(1.0, 0.95, 0.85).lerp(Color(0.5, 0.85, 1.0), mix)
		b.draw_rect(rect, Color(col, al * 0.5))
		_fist_glyph(ctr, dir, Color(col, al))


func _blade(ang: float, tip_r: float, outward: bool, col: Color) -> void:
	# one small sword whose tip sits at radius tip_r; points outward or inward
	var dir := Vector2(cos(ang), sin(ang))
	var tip: Vector2 = CENTER + dir * tip_r
	var sgn: float = -1.0 if outward else 1.0   # tail lies on the far side of the tip
	var tail: Vector2 = tip + dir * 28.0 * sgn
	var guard: Vector2 = tip + dir * 22.0 * sgn
	var perp := Vector2(-dir.y, dir.x)
	b.draw_line(tip, tail, col, 3.0)
	b.draw_line(guard - perp * 6.0, guard + perp * 6.0, col, 3.0)


func _draw_ring(rg: Dictionary) -> void:
	var t: float = rg["t"]
	var tele: float = rg["tele"]
	var rad: float = _ring_radius(rg)
	var live: bool = t >= tele
	var col := Color(0.7, 0.9, 1.0, 1.0 if live else 0.4)
	var cull: Rect2 = arena_rect().grow(36.0)
	var n: int = 16
	var rot: float = clock * 0.6
	var outward: bool = rg["mode"] == "out"
	if outward and not live:
		# charging flash at the center
		var pulse: float = 0.5 + 0.5 * sin(t * 24.0)
		b.draw_circle(CENTER, 10.0 + 8.0 * pulse, Color(1, 0.4, 0.4, 0.5))
	for i in n:
		var ang: float = rot + TAU * float(i) / float(n)
		var tip: Vector2 = CENTER + Vector2(cos(ang), sin(ang)) * rad
		if cull.has_point(tip) or (not outward and cull.has_point(CENTER + Vector2(cos(ang), sin(ang)) * (rad + 14.0))):
			_blade(ang, rad, outward, col)
	if live and rad < 150.0:
		b.draw_arc(CENTER, rad, 0.0, TAU, 48, Color(0.6, 0.85, 1.0, 0.25), 2.0)


func _draw_sword_ray(s: Dictionary) -> void:
	var t: float = s["t"]
	var ang: float = s["ang"]
	var dir := Vector2(cos(ang), sin(ang))
	if t < 0.55:
		var blink: float = 0.5 + 0.5 * sin(t * 30.0)
		b.draw_line(CENTER, CENTER + dir * CIRCLE_R, Color(1, 0.3, 0.3, 0.2 + 0.3 * blink), 2.0)
		b.draw_circle(CENTER, 5.0, Color(1, 0.5, 0.5, 0.6))
	else:
		var d: float = s["d"]
		var tip: Vector2 = CENTER + dir * d
		var tail: Vector2 = CENTER + dir * maxf(d - 24.0, 0.0)
		var perp := Vector2(-dir.y, dir.x)
		b.draw_line(tail, tip, Color(0.8, 0.95, 1.0), 4.0)
		b.draw_line(tail - perp * 6.0, tail + perp * 6.0, Color(0.8, 0.95, 1.0), 3.0)


func _draw_fist(f: Dictionary) -> void:
	var ang: float = f["ang"]
	var t: float = f["t"]
	var tele: float = f["tele"]
	if t < 0.0:
		return
	if t < tele:
		var blink: float = 0.5 + 0.5 * sin(t * 28.0)
		var half_ang: float = FIST_HALFW / CIRCLE_R
		b.draw_arc(CENTER, CIRCLE_R - 3.0, ang - half_ang, ang + half_ang, 10, Color(1, 0.3, 0.3, 0.5 + 0.5 * blink), 6.0)
		return
	var depth: float = _fist_depth(f)
	if depth <= 0.0:
		return
	b.draw_set_transform(CENTER, ang, Vector2.ONE)
	var x0: float = CIRCLE_R - depth
	b.draw_rect(Rect2(x0, -FIST_HALFW, depth + 10.0, FIST_HALFW * 2.0), Color(0.88, 0.78, 0.68))
	b.draw_rect(Rect2(x0, -FIST_HALFW, depth + 10.0, FIST_HALFW * 2.0), Color.WHITE, false, 2.0)
	for i in 3:
		b.draw_line(Vector2(x0, -FIST_HALFW + 10.0 * float(i + 1)), Vector2(x0 + 12.0, -FIST_HALFW + 10.0 * float(i + 1)), Color(0, 0, 0, 0.6), 2.0)
	b.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_blade(bl: Dictionary) -> void:
	var t: float = bl["t"]
	if t < 0.0:
		return
	var p: Vector2 = bl["p"]
	var dirv: Vector2 = bl["dir"]
	var ln: float = bl["len"]
	var tele: float = bl["tele"]
	if t < tele:
		var f: float = t / tele
		var blink: float = 0.5 + 0.5 * sin(t * 30.0)
		b.draw_line(p, p + dirv * ln, Color(1.0, 0.35, 0.35, 0.10 + 0.3 * f * blink), 1.0)
		b.draw_circle(p, 3.0 + 3.0 * f, Color(1.0, 0.4, 0.4, 0.5 + 0.4 * f))
		return
	var ext: float = _blade_ext(bl)
	if ext <= 0.0:
		return
	var tip: Vector2 = p + dirv * ln * ext
	var perp := Vector2(-dirv.y, dirv.x)
	b.draw_line(p, tip, Color(0.88, 0.95, 1.0), 4.0)
	b.draw_line(p + dirv * 14.0 - perp * 6.0, p + dirv * 14.0 + perp * 6.0, Color(0.6, 0.4, 0.9), 3.0)
	b.draw_line(tip, tip - dirv * 8.0, Color.WHITE, 2.0)


func _draw_dagger(d: Dictionary) -> void:
	var ang: float = d["ang"]
	var pos: Vector2 = d["pos"]
	var dir := Vector2(cos(ang), sin(ang))
	var perp := Vector2(-dir.y, dir.x)
	var t: float = d["t"]
	var wind: float = d["wind"]
	var al: float = 0.6 if t < wind else 1.0
	var steel := Color(0.85, 0.92, 1.0, al)
	b.draw_line(pos - dir * 8.0, pos + dir * 12.0, steel, 4.0)
	b.draw_line(pos + dir * 12.0, pos + dir * 16.0, steel, 2.0)
	b.draw_line(pos - dir * 8.0 - perp * 5.0, pos - dir * 8.0 + perp * 5.0, Color(0.6, 0.4, 0.9, al), 3.0)
	b.draw_line(pos - dir * 8.0, pos - dir * 15.0, Color(0.6, 0.4, 0.9, al), 3.0)
	if t < wind and bool(d["seek"]):
		b.draw_line(pos, pos + dir * 40.0, Color(1, 0.4, 0.4, 0.25), 1.0)


# ------------------------------------------------------------------ drawing: Saffron (placeholder art)
func draw_boss(shake: Vector2, alpha: float) -> void:
	var bob: float = sin(clock * 2.0) * 2.0
	var o: Vector2 = BOSS_BASE + shake + Vector2(0, bob)
	if form == 2 and clone_alpha > 0.0:
		for sx: float in [-CLONE_DX, CLONE_DX]:
			_figure(o + Vector2(sx, sin(clock * 2.0 + sx) * 2.0), alpha * clone_alpha * 0.6, true)
	_figure(o, alpha, false)


func _figure(o: Vector2, alpha: float, ghost: bool) -> void:
	var cloak := Color(0.22, 0.12, 0.34, alpha)
	var cloak2 := Color(0.34, 0.18, 0.5, alpha)
	var skin := Color(0.92, 0.82, 0.72, alpha)
	var glow := Color(0.5, 0.95, 1.0, alpha)
	if ghost:   # simulacra: icy, translucent copies
		var ice := Color(0.15, 0.45, 0.8, alpha)
		cloak = cloak.lerp(ice, 0.6)
		cloak2 = cloak2.lerp(ice, 0.6)
		skin = skin.lerp(Color(0.8, 0.95, 1.0, alpha), 0.6)
	var p: String = pose if pose_t > 0.0 or pose == "big" else "idle"
	if p == "big":
		b.draw_circle(o + Vector2(0, -70), 58.0 + 4.0 * sin(clock * 8.0), Color(0.4, 0.5, 1.0, 0.12 * alpha))
	# cloak + torso
	b.draw_colored_polygon(PackedVector2Array([o + Vector2(-36, 0), o + Vector2(36, 0), o + Vector2(24, -70), o + Vector2(-24, -70)]), cloak)
	b.draw_colored_polygon(PackedVector2Array([o + Vector2(-26, -66), o + Vector2(26, -66), o + Vector2(17, -98), o + Vector2(-17, -98)]), cloak2)
	# sword on his back
	b.draw_line(o + Vector2(14, -96), o + Vector2(30, -128), Color(0.8, 0.85, 0.95, alpha), 3.0)
	b.draw_line(o + Vector2(10, -100), o + Vector2(20, -92), Color(0.6, 0.4, 0.9, alpha), 3.0)
	# arms
	var lh := Vector2(-34, -58)
	var rh := Vector2(34, -58)
	match p:
		"throw":
			rh = Vector2(46, -122)
		"punch":
			rh = Vector2(8, -34)
			lh = Vector2(-30, -78)
		"push":
			lh = Vector2(-46, -120)
			rh = Vector2(46, -120)
		"big":
			lh = Vector2(-52, -96)
			rh = Vector2(52, -96)
	var armc := Color(0.3, 0.16, 0.45, alpha)
	b.draw_line(o + Vector2(-20, -92), o + lh, armc, 8.0)
	b.draw_line(o + Vector2(20, -92), o + rh, armc, 8.0)
	b.draw_circle(o + lh, 6.0, skin)
	b.draw_circle(o + rh, 6.0, skin)
	if p == "big":
		b.draw_circle(o + lh, 9.0, Color(glow, 0.5 * alpha))
		b.draw_circle(o + rh, 9.0, Color(glow, 0.5 * alpha))
	# head: hood + face + glowing eyes
	b.draw_circle(o + Vector2(0, -112), 20.0, cloak)
	b.draw_circle(o + Vector2(0, -108), 14.0, skin)
	b.draw_rect(Rect2(o + Vector2(-8, -112), Vector2(5, 4)), glow)
	b.draw_rect(Rect2(o + Vector2(3, -112), Vector2(5, 4)), glow)
	b.draw_line(o + Vector2(-5, -102), o + Vector2(5, -102), Color(0.35, 0.2, 0.2, alpha), 2.0)
