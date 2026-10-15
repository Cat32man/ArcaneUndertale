extends RefCounted
## Katashi, a Visage (demi-god) of LIGHT, with a little fire. His thing is SPEED:
## short warnings, rapid chains, and he gets faster as he is hurt.
##
## Moves (a turn is a chain of 3-5):
##   flash    Flash Step    a thin line of light appears, then he streaks along it
##   barrage  Blink Barrage three Flash Steps in quick rhythm
##   volley   Ember Volley  fans of fireballs aimed at you, twice (his one fire move)
##   wave     Dawn Pillars  columns of light flash across the floor with one gap (twice)
##   prism    Prism Burst   an orb charges, then fires rays of light in every direction
##   pursuit  Sunstreak     bright streaks dash across at the height/column you stand in
##   spiral   Radiant Spiral  an orb at the center fires beams of light round and round, on a fixed beat
##   rhythm   Dawn Chorus     columns of light in a fixed 6-beat phrase (the same every time - learn it)
## Big attack:
##   Eclipse  the arena goes dark - only a small lantern around you reveals the light orbs;
##            warnings stay visible, so listen for the pattern.

const CENTER := Vector2(320, 265)
const HALF := Vector2(110, 75)
const BOSS_BASE := Vector2(320, 184)
const LANTERN_R := 62.0

const D_SLASH := 14
const D_BALL := 10
const D_PILLAR := 15
const D_PRISM := 13
const D_STREAK := 12

const SLASH_LIVE := 0.16
const SLASH_FADE := 0.3
const PILLAR_LIVE := 0.28
# the Dawn Chorus phrase: which of the 5 columns light up on each beat (safe column is always adjacent)
const RHYTHM := [[0, 2, 4], [0, 1, 3, 4], [0, 2, 4], [1, 3], [0, 2, 3, 4], [1, 2, 3, 4]]
const SPIRAL_RAYS := 26   # 0.5 rad apart = a bit over two full turns, so each turn lands off the last

var b   # battle node (untyped on purpose; called dynamically)

# interface the battle expects from a boss engine
var morph: float = 0.0
var circle_mode: bool = false
var finished: bool = false

var phase: String = "chain"
var queue: Array = []
var cur: Dictionary = {}
var gap: float = 0.0
var linger: float = 0.0
var big_phase: String = "dim_in"
var big_t: float = 0.0
var big_spawn: float = 0.0
var turn_t: float = 0.0
var turns_since_big: int = 0
var last_kind: String = ""
var last_eclipse: String = ""
var clock: float = 0.0
var eclipse: float = 0.0          # 0..1 darkness

var boss_x: float = 320.0
var boss_tx: float = 320.0
var boss_vx: float = 0.0
var pose: String = "idle"
var pose_t: float = 0.0

var slashes: Array = []
var balls: Array = []
var pillars: Array = []
var prisms: Array = []
var streaks: Array = []
var spirals: Array = []
var spiral_count: int = 0


func _init(battle) -> void:
	b = battle


# ------------------------------------------------------------------ helpers
func arena_rect() -> Rect2:
	return Rect2(CENTER - HALF, HALF * 2.0)


func box_rect() -> Rect2:
	return arena_rect()


func draw_arena() -> void:
	pass   # never morphs


func tempo() -> float:
	# telegraphs shrink as he gets hurt (down to 65%)
	var frac: float = float(b.enemy_hp) / float(b.enemy_max)
	return 1.0 - 0.35 * (1.0 - frac)


func _down(k1: Key, k2: Key) -> bool:
	return Input.is_physical_key_pressed(k1) or Input.is_physical_key_pressed(k2)


func vis(p: Vector2) -> float:
	# how visible a LIVE hazard is: full near the lantern, dim far away (only in Eclipse)
	if eclipse <= 0.0:
		return 1.0
	var d: float = p.distance_to(b.soul)
	var v: float = clampf(1.0 - (d - LANTERN_R) / 45.0, 0.12, 1.0)
	return lerpf(1.0, v, eclipse)


func _clip(p: Vector2, dir: Vector2, ray: bool) -> Array:
	# clip the line (or ray from p) to the arena rect -> [a, b] or [] if it misses
	var ar: Rect2 = arena_rect()
	var tmin: float = 0.0 if ray else -1000.0
	var tmax: float = 1000.0
	for axis in 2:
		var d: float = dir.x if axis == 0 else dir.y
		var o: float = p.x if axis == 0 else p.y
		var lo: float = ar.position.x if axis == 0 else ar.position.y
		var hi: float = ar.end.x if axis == 0 else ar.end.y
		if absf(d) < 0.0001:
			if o < lo or o > hi:
				return []
		else:
			var t1: float = (lo - o) / d
			var t2: float = (hi - o) / d
			tmin = maxf(tmin, minf(t1, t2))
			tmax = minf(tmax, maxf(t1, t2))
	if tmin > tmax:
		return []
	return [p + dir * tmin, p + dir * tmax]


# ------------------------------------------------------------------ turn control
func tick(delta: float) -> void:
	clock += delta
	var old: float = boss_x
	boss_x = move_toward(boss_x, boss_tx, 1100.0 * delta)
	boss_vx = lerpf(boss_vx, (boss_x - old) / maxf(delta, 0.0001), 0.5)


func start_turn() -> void:
	_clear_all()
	queue.clear()
	cur = {}
	gap = 0.25
	linger = 0.0
	turn_t = 0.0
	finished = false
	eclipse = 0.0
	pose = "idle"
	b.soul = CENTER
	var big: bool = turns_since_big >= 2 and (turns_since_big >= 5 or randf() < 0.35)
	if big:
		phase = "big"
		big_phase = "dim_in"
		b.sfx("dim")
		big_t = 0.0
		turns_since_big = 0
		boss_tx = 320.0
	else:
		phase = "chain"
		turns_since_big += 1
		for i in randi_range(3, 5):
			queue.append(_pick_kind())


func _pick_kind() -> String:
	var kinds: Array = ["flash", "barrage", "volley", "wave", "prism", "pursuit", "spiral", "rhythm"]
	var k: String = kinds.pick_random()
	while k == last_kind:
		k = kinds.pick_random()
	last_kind = k
	return k


func _clear_all() -> void:
	slashes.clear()
	balls.clear()
	pillars.clear()
	prisms.clear()
	streaks.clear()
	spirals.clear()


func _all_clear() -> bool:
	return slashes.is_empty() and balls.is_empty() and pillars.is_empty() and prisms.is_empty() and streaks.is_empty() and spirals.is_empty()


func update(delta: float) -> bool:
	turn_t += delta
	pose_t = maxf(0.0, pose_t - delta)
	if phase == "chain":
		_move_soul(delta)
		_update_chain(delta)
	else:
		_move_soul(delta)
		_update_big(delta)
	_update_slashes(delta)
	_update_balls(delta)
	_update_pillars(delta)
	_update_prisms(delta)
	_update_streaks(delta)
	_update_spirals(delta)
	if turn_t > 24.0:
		_clear_all()
		eclipse = 0.0
		finished = true
	return finished


func _move_soul(delta: float) -> void:
	var spd: float = b.SOUL_SPEED_HASTE if b.haste_left > 0 else b.SOUL_SPEED
	var dir := Vector2(
		float(_down(KEY_RIGHT, KEY_D)) - float(_down(KEY_LEFT, KEY_A)),
		float(_down(KEY_DOWN, KEY_S)) - float(_down(KEY_UP, KEY_W)))
	if dir.length() > 0.0:
		dir = dir.normalized()
	if _down(KEY_X, KEY_SHIFT):
		spd *= 0.5
	var inner: Rect2 = arena_rect().grow(-10.0)
	var p: Vector2 = b.soul + dir * spd * delta
	b.soul = p.clamp(inner.position, inner.end)


# ------------------------------------------------------------------ chain
func _update_chain(delta: float) -> void:
	if cur.is_empty():
		if not queue.is_empty():
			gap -= delta
			if gap <= 0.0:
				_begin_attack(queue.pop_front())
		elif _all_clear():
			linger += delta
			if linger >= 0.35:
				finished = true
		return
	_run_attack(delta)


func _begin_attack(kind: String) -> void:
	cur = {"kind": kind, "t": 0.0, "step": 0}
	boss_tx = randf_range(250.0, 390.0)   # he blinks to a new spot above the arena
	pose = "cast"
	pose_t = 0.5
	if kind == "flash" or kind == "barrage" or kind == "pursuit":
		pose = "slash"
	if kind == "spiral" or kind == "rhythm":
		pose = "cast"
		pose_t = 1.5
		boss_tx = 320.0


func _end_attack() -> void:
	cur = {}
	gap = randf_range(0.1, 0.3) * tempo()


func _run_attack(delta: float) -> void:
	cur["t"] += delta
	var t: float = cur["t"]
	var step: int = cur["step"]
	match cur["kind"]:
		"flash":
			if step == 0:
				_spawn_slash()
				cur["step"] = 1
			if t >= 0.3:
				_end_attack()
		"barrage":
			if step < 3 and t >= float(step) * 0.28 * tempo():
				_spawn_slash()
				cur["step"] = step + 1
			if step >= 3 and t >= 0.84 * tempo() + 0.15:
				_end_attack()
		"volley":
			if step < 2 and t >= float(step) * 0.55 * tempo():
				_spawn_volley()
				cur["step"] = step + 1
			if step >= 2 and t >= 0.55 * tempo() + 0.3:
				_end_attack()
		"wave":
			if step < 2 and t >= float(step) * 0.95 * tempo():
				_spawn_wave(step)
				cur["step"] = step + 1
			if step >= 2 and t >= 0.95 * tempo() + 0.5:
				_end_attack()
		"prism":
			if step < 2 and t >= float(step) * 0.5:
				_spawn_prism(step)
				cur["step"] = step + 1
			if step >= 2 and t >= 0.5 + 0.2:
				_end_attack()
		"spiral":
			if step == 0:
				cur["end"] = _spawn_spiral()
				cur["step"] = 1
			if step >= 1 and t >= float(cur["end"]):
				_end_attack()
		"rhythm":
			if step == 0:
				cur["end"] = _spawn_rhythm()
				cur["step"] = 1
			if step >= 1 and t >= float(cur["end"]):
				_end_attack()
		"pursuit":
			if step < 3 and t >= float(step) * 0.35 * tempo():
				_spawn_streak()
				cur["step"] = step + 1
			if step >= 3 and t >= 1.05 * tempo() + 0.2:
				_end_attack()


# ------------------------------------------------------------------ Flash Step
func _spawn_slash() -> void:
	var ar: Rect2 = arena_rect()
	var sp: Vector2 = b.soul
	var p := Vector2(randf_range(ar.position.x + 10.0, ar.end.x - 10.0), randf_range(ar.position.y + 10.0, ar.end.y - 10.0))
	if randf() < 0.65:
		p = sp + Vector2(randf_range(-25.0, 25.0), randf_range(-20.0, 20.0))   # lean toward the SOUL
	var dir: Vector2
	match randi_range(0, 2):
		0:
			dir = Vector2(1, 0)
		1:
			dir = Vector2(0, 1)
		_:
			dir = Vector2.from_angle((PI * 0.25 + randf_range(-0.2, 0.2)) * (1.0 if randf() < 0.5 else -1.0))
	var seg: Array = _clip(p, dir, false)
	if seg.is_empty():
		return
	slashes.append({"a": seg[0], "b": seg[1], "t": 0.0, "tele": 0.45 * tempo()})


func _update_slashes(delta: float) -> void:
	var keep: Array = []
	for s: Dictionary in slashes:
		s["t"] += delta
		var t: float = s["t"]
		var tele: float = s["tele"]
		if t >= tele and t < tele + SLASH_LIVE:
			var pa: Vector2 = s["a"]
			var pb: Vector2 = s["b"]
			var near: Vector2 = Geometry2D.get_closest_point_to_segment(b.soul, pa, pb)
			if near.distance_to(b.soul) < 6.0:
				b.hurt(D_SLASH)
			if not s.has("struck"):
				s["struck"] = true
				b.add_shake(0.25)
				b.sfx("flash")
		if t < tele + SLASH_LIVE + SLASH_FADE:
			keep.append(s)
	slashes = keep


# ------------------------------------------------------------------ Ember Volley
func _spawn_volley() -> void:
	b.sfx("fire")
	var origin := Vector2(boss_x, 132.0)
	var base: float = ((b.soul as Vector2) - origin).angle()
	var n: int = randi_range(3, 5)
	for i in n:
		var ang: float = base + (float(i) - float(n - 1) * 0.5) * 0.26
		balls.append({"pos": origin, "vel": Vector2(cos(ang), sin(ang)) * 250.0, "r": 6.0, "t": 0.0})
	pose = "cast"
	pose_t = 0.3


func _update_balls(delta: float) -> void:
	var slow: float = b._slow()
	var keep: Array = []
	var bounds: Rect2 = Rect2(-60, -60, 760, 600)
	for ball: Dictionary in balls:
		ball["t"] += delta
		var pos: Vector2 = ball["pos"]
		pos += (ball["vel"] as Vector2) * slow * delta
		ball["pos"] = pos
		var hit: bool = false
		if pos.distance_to(b.soul) < float(ball["r"]) + 4.0:
			hit = b.hurt(D_BALL)
		if not hit and bounds.has_point(pos):
			keep.append(ball)
	balls = keep


# ------------------------------------------------------------------ Flame Wave
func _spawn_wave(index: int) -> void:
	var ar: Rect2 = arena_rect()
	var cols: int = 5
	var w: float = ar.size.x / float(cols)
	var sc: int = clampi(int((float(b.soul.x) - ar.position.x) / w), 0, cols - 1)
	# the gap is the column you are in or one next to it, so it is always reachable
	var gap_col: int = clampi(sc + randi_range(-1, 1), 0, cols - 1)
	if index > 0 and cur.has("last_gap"):
		gap_col = clampi(int(cur["last_gap"]) + [-1, 1].pick_random(), 0, cols - 1)
	cur["last_gap"] = gap_col
	var from_left: bool = randf() < 0.5
	for i in cols:
		if i == gap_col:
			continue
		var order: int = i if from_left else cols - 1 - i
		pillars.append({"x": ar.position.x + (float(i) + 0.5) * w, "w": w, "t": -float(order) * 0.06, "tele": 0.55 * tempo()})
	pose = "cast"
	pose_t = 0.5


func _update_pillars(delta: float) -> void:
	var keep: Array = []
	for p: Dictionary in pillars:
		p["t"] += delta
		var t: float = p["t"]
		var tele: float = p["tele"]
		if t >= tele and t < tele + PILLAR_LIVE:
			if absf(float(b.soul.x) - float(p["x"])) < float(p["w"]) * 0.5 + 2.0:
				b.hurt(D_PILLAR)
			if not p.has("struck"):
				p["struck"] = true
				b.add_shake(0.12)
				b.sfx("pillar", 0.7)
		if t < tele + PILLAR_LIVE + 0.2:
			keep.append(p)
	pillars = keep


# ------------------------------------------------------------------ Prism Burst
func _spawn_prism(index: int) -> void:
	var ar: Rect2 = arena_rect().grow(-18.0)
	var sp: Vector2 = b.soul
	# orb sits 45-75px from the SOUL so there is room to slip between the rays
	var p: Vector2 = sp + Vector2.from_angle(randf() * TAU) * randf_range(45.0, 75.0)
	p = p.clamp(ar.position, ar.end)
	var n: int = 6
	var a0: float = randf() * TAU
	if index == 1:
		a0 += PI / float(n)   # second orb is offset so the first gaps are not safe
	var angs: Array = []
	for i in n:
		angs.append(a0 + TAU * float(i) / float(n))
	prisms.append({"pos": p, "t": 0.0, "tele": 0.7 * tempo(), "live": 0.22, "angs": angs})
	pose = "cast"
	pose_t = 0.6


func _update_prisms(delta: float) -> void:
	var keep: Array = []
	for pr: Dictionary in prisms:
		pr["t"] += delta
		var t: float = pr["t"]
		var tele: float = pr["tele"]
		var live: float = pr["live"]
		if t >= tele and t < tele + live:
			var pos: Vector2 = pr["pos"]
			for a: float in pr["angs"]:
				var tip: Vector2 = pos + Vector2(cos(a), sin(a)) * 300.0
				var near: Vector2 = Geometry2D.get_closest_point_to_segment(b.soul, pos, tip)
				if near.distance_to(b.soul) < 5.0:
					b.hurt(D_PRISM)
					break
			if not pr.has("struck"):
				pr["struck"] = true
				b.add_shake(0.2)
				b.sfx("beam")
		if t < tele + live + 0.2:
			keep.append(pr)
	prisms = keep


# ------------------------------------------------------------------ Sunstreak
func _spawn_streak() -> void:
	b.sfx("dash", 0.7)
	var ar: Rect2 = arena_rect()
	var horiz: bool = randf() < 0.6
	var sp: Vector2 = b.soul
	var sgn: float = 1.0 if randf() < 0.5 else -1.0
	var c: float = (sp.y if horiz else sp.x) + randf_range(-8.0, 8.0)
	var start: float = (ar.position.x if horiz else ar.position.y) - 40.0 if sgn > 0.0 else (ar.end.x if horiz else ar.end.y) + 40.0
	streaks.append({"horiz": horiz, "c": c, "sgn": sgn, "a": start, "t": 0.0, "tele": 0.4 * tempo()})
	pose = "slash"
	pose_t = 0.3


func _update_streaks(delta: float) -> void:
	var ar: Rect2 = arena_rect()
	var keep: Array = []
	for s: Dictionary in streaks:
		s["t"] += delta
		var t: float = s["t"]
		var tele: float = s["tele"]
		var sgn: float = s["sgn"]
		var horiz: bool = s["horiz"]
		var done: bool = false
		if t >= tele:
			s["a"] += sgn * 700.0 * b._slow() * delta
			var a: float = s["a"]
			var c: float = s["c"]
			var rect: Rect2
			if horiz:
				rect = Rect2(a - 40.0, c - 9.0, 80.0, 18.0)
			else:
				rect = Rect2(c - 9.0, a - 40.0, 18.0, 80.0)
			if rect.grow(3.0).has_point(b.soul):
				b.hurt(D_STREAK)
			var lo: float = (ar.position.x if horiz else ar.position.y) - 60.0
			var hi: float = (ar.end.x if horiz else ar.end.y) + 60.0
			done = a < lo or a > hi
		if not done:
			keep.append(s)
	streaks = keep


# ------------------------------------------------------------------ Radiant Spiral (rhythmic)
# One beam every beat, each a fixed 0.5 rad after the last, round and round for ~2 turns.
# Because 2*pi isn't a multiple of 0.5, the second turn lands in the gaps of the first - so a SOUL
# parked in a gap gets caught and has to shift over. Same pattern every time; direction flips each use.
func _spawn_spiral() -> float:
	var sgn: float = 1.0 if spiral_count % 2 == 0 else -1.0
	spiral_count += 1
	var beat: float = 0.2 * tempo()
	var intro: float = 0.9
	var tele: float = 0.4 * tempo()
	for i in SPIRAL_RAYS:
		var ang: float = -PI * 0.5 + sgn * 0.5 * float(i)
		spirals.append({"a": ang, "t": -intro - float(i) * beat, "tele": tele, "live": 0.14})
	var total: float = intro + float(SPIRAL_RAYS) * beat + tele + 0.3
	spirals.append({"orb": true, "t": 0.0, "dur": total})
	pose = "cast"
	pose_t = 1.5
	return intro + float(SPIRAL_RAYS - 1) * beat   # next attack may start as the last beams charge


func _update_spirals(delta: float) -> void:
	var keep: Array = []
	for r: Dictionary in spirals:
		r["t"] += delta
		var t: float = r["t"]
		if r.has("orb"):
			if t < float(r["dur"]):
				keep.append(r)
			continue
		var tele: float = r["tele"]
		var live: float = r["live"]
		if t >= tele and t < tele + live:
			var a: float = r["a"]
			var tip: Vector2 = CENTER + Vector2(cos(a), sin(a)) * 300.0
			var near: Vector2 = Geometry2D.get_closest_point_to_segment(b.soul, CENTER, tip)
			if near.distance_to(b.soul) < 7.0:
				b.hurt(D_PRISM)
			if not r.has("struck"):
				r["struck"] = true
				b.add_shake(0.08)
				b.sfx("beam", 0.35)
		if t < tele + live + 0.15:
			keep.append(r)
	spirals = keep


func _draw_spiral(r: Dictionary) -> void:
	var t: float = r["t"]
	if r.has("orb"):
		var pulse: float = 0.5 + 0.5 * sin(t * 12.0)
		b.draw_circle(CENTER, 9.0 + 3.0 * pulse, Color(1.0, 0.97, 0.75, 0.9))
		b.draw_arc(CENTER, 14.0 + 3.0 * pulse, 0.0, TAU, 24, Color(1.0, 0.9, 0.5, 0.7), 2.0)
		return
	if t < 0.0:
		return
	var a: float = r["a"]
	var seg: Array = _clip(CENTER, Vector2(cos(a), sin(a)), true)
	if seg.is_empty():
		return
	var tele: float = r["tele"]
	var live: float = r["live"]
	if t < tele:
		var p: float = t / tele
		b.draw_line(seg[0], seg[1], Color(1.0, 0.97, 0.75, 0.12 + 0.35 * p), 1.0)
	elif t < tele + live:
		var v: float = vis(Geometry2D.get_closest_point_to_segment(b.soul, seg[0], seg[1]))
		b.draw_line(seg[0], seg[1], Color(1.0, 0.9, 0.5, 0.6 * v), 9.0)
		b.draw_line(seg[0], seg[1], Color(1.0, 1.0, 0.95, v), 4.0)
	else:
		var f: float = 1.0 - (t - tele - live) / 0.15
		b.draw_line(seg[0], seg[1], Color(1.0, 0.95, 0.7, 0.5 * f), 5.0 * f + 1.0)


# ------------------------------------------------------------------ Dawn Chorus (rhythmic)
func _spawn_rhythm() -> float:
	var ar: Rect2 = arena_rect()
	var cols: int = 5
	var w: float = ar.size.x / float(cols)
	var beat: float = 0.7 * tempo()
	for i in RHYTHM.size():
		for c: int in RHYTHM[i]:
			pillars.append({"x": ar.position.x + (float(c) + 0.5) * w, "w": w, "t": -float(i) * beat, "tele": 0.55 * tempo()})
	pose = "cast"
	pose_t = 1.0
	return float(RHYTHM.size() - 1) * beat + 0.5


# ------------------------------------------------------------------ Eclipse (big attack)
func _update_big(delta: float) -> void:
	big_t += delta
	pose = "cast"
	match big_phase:
		"dim_in":
			eclipse = clampf(big_t / 0.6, 0.0, 1.0)
			b.rumble(0.25)
			if big_t >= 0.6:
				big_phase = "play"
				big_t = 0.0
				big_spawn = 0.5
		"play":
			big_spawn -= delta
			if big_t < 8.0 and big_spawn <= 0.0:
				_spawn_eclipse()
				big_spawn = randf_range(0.5, 0.9) * tempo()
			if big_t >= 8.2 and (_all_clear() or big_t > 11.0):
				big_phase = "dim_out"
				big_t = 0.0
				_clear_all()
		"dim_out":
			eclipse = 1.0 - clampf(big_t / 0.6, 0.0, 1.0)
			if big_t >= 0.6:
				eclipse = 0.0
				pose = "idle"
				finished = true


func _spawn_eclipse() -> void:
	var opts: Array = ["rows", "aimed", "slash", "prism", "spiral"]
	var k: String = opts.pick_random()
	while k == last_eclipse:
		k = opts.pick_random()
	last_eclipse = k
	var ar: Rect2 = arena_rect()
	match k:
		"rows":
			# a line of fireballs sweeps in from one side, gaps between them
			var side: int = randi_range(0, 3)
			var n: int = 4
			for i in n:
				var f: float = (float(i) + randf_range(0.2, 0.8)) / float(n)
				var pos: Vector2
				var vel: Vector2
				match side:
					0:
						pos = Vector2(ar.position.x - 10.0, ar.position.y + f * ar.size.y)
						vel = Vector2(1, 0)
					1:
						pos = Vector2(ar.end.x + 10.0, ar.position.y + f * ar.size.y)
						vel = Vector2(-1, 0)
					2:
						pos = Vector2(ar.position.x + f * ar.size.x, ar.position.y - 10.0)
						vel = Vector2(0, 1)
					_:
						pos = Vector2(ar.position.x + f * ar.size.x, ar.end.y + 10.0)
						vel = Vector2(0, -1)
				balls.append({"pos": pos, "vel": vel * 190.0, "r": 6.0, "t": 0.0, "light": true})
		"aimed":
			for i in 2:
				var pos2 := Vector2(randf_range(ar.position.x, ar.end.x), ar.position.y - 12.0 if randf() < 0.5 else ar.end.y + 12.0)
				var aim: Vector2 = ((b.soul as Vector2) - pos2).normalized().rotated(randf_range(-0.12, 0.12))
				balls.append({"pos": pos2, "vel": aim * 230.0, "r": 6.0, "t": 0.0, "light": true})
		"slash":
			_spawn_slash()
			_spawn_slash()
		"prism":
			_spawn_prism(0)
		"spiral":
			if spirals.is_empty():
				_spawn_spiral()


# ------------------------------------------------------------------ drawing: attacks
func draw_attacks() -> void:
	for p: Dictionary in pillars:
		_draw_pillar(p)
	for s: Dictionary in slashes:
		_draw_slash(s)
	for pr: Dictionary in prisms:
		_draw_prism(pr)
	for s: Dictionary in streaks:
		_draw_streak(s)
	for r: Dictionary in spirals:
		_draw_spiral(r)
	for ball: Dictionary in balls:
		_draw_ball(ball)
	if eclipse > 0.0:
		_draw_lantern()


func _draw_lantern() -> void:
	# a faint ring showing how far you can see, clipped to the arena
	var inner: Rect2 = arena_rect().grow(-2.0)
	var n: int = 40
	var sp: Vector2 = b.soul
	for i in n:
		var a0: float = TAU * float(i) / float(n)
		var a1: float = TAU * float(i + 1) / float(n)
		var p0: Vector2 = sp + Vector2(cos(a0), sin(a0)) * LANTERN_R
		var p1: Vector2 = sp + Vector2(cos(a1), sin(a1)) * LANTERN_R
		if inner.has_point(p0) and inner.has_point(p1) and i % 2 == 0:
			b.draw_line(p0, p1, Color(1.0, 0.85, 0.5, 0.22 * eclipse), 1.5)


func _draw_slash(s: Dictionary) -> void:
	var t: float = s["t"]
	var tele: float = s["tele"]
	var pa: Vector2 = s["a"]
	var pb: Vector2 = s["b"]
	if t < tele:
		var p: float = t / tele
		var blink: float = 0.5 + 0.5 * sin(t * 40.0)
		b.draw_line(pa, pb, Color(1.0, 0.97, 0.75, 0.25 + 0.5 * p * blink), 1.5)
	elif t < tele + SLASH_LIVE:
		var v: float = vis((pa + pb) * 0.5) if eclipse <= 0.0 else vis(Geometry2D.get_closest_point_to_segment(b.soul, pa, pb))
		b.draw_line(pa, pb, Color(1.0, 0.9, 0.5, 0.7 * v), 12.0)
		b.draw_line(pa, pb, Color(1.0, 1.0, 0.9, v), 5.0)
	else:
		var f: float = 1.0 - (t - tele - SLASH_LIVE) / SLASH_FADE
		b.draw_line(pa, pb, Color(1.0, 0.95, 0.65, 0.45 * f), 8.0 * f + 1.0)


func _draw_ball(ball: Dictionary) -> void:
	var pos: Vector2 = ball["pos"]
	var vel: Vector2 = ball["vel"]
	var r: float = ball["r"]
	var v: float = vis(pos)
	var dir: Vector2 = vel.normalized()
	if ball.get("light", false):
		b.draw_line(pos, pos - dir * 16.0, Color(1.0, 0.95, 0.6, 0.45 * v), r * 1.4)
		b.draw_circle(pos, r + 1.5, Color(1.0, 0.92, 0.55, v))
		b.draw_circle(pos, r * 0.6, Color(1.0, 1.0, 0.95, v))
	else:   # ember: the only fire he throws
		b.draw_line(pos, pos - dir * 16.0, Color(1.0, 0.45, 0.1, 0.5 * v), r * 1.4)
		b.draw_circle(pos, r + 1.5, Color(1.0, 0.4, 0.1, v))
		b.draw_circle(pos, r * 0.6, Color(1.0, 0.95, 0.5, v))


func _draw_pillar(p: Dictionary) -> void:
	var ar: Rect2 = arena_rect()
	var t: float = p["t"]
	var tele: float = p["tele"]
	var x: float = p["x"]
	var w: float = p["w"]
	if t < 0.0:
		return
	if t < tele:
		var pr: float = t / tele
		var pulse: float = 0.5 + 0.5 * sin(t * 30.0)
		# ground glow growing, plus faint column outline
		b.draw_rect(Rect2(x - w * 0.5 + 2.0, ar.end.y - 8.0 - 10.0 * pr, w - 4.0, 8.0 + 10.0 * pr), Color(1.0, 0.92, 0.55, 0.25 + 0.35 * pulse))
		b.draw_rect(Rect2(x - w * 0.5 + 2.0, ar.position.y + 2.0, w - 4.0, ar.size.y - 4.0), Color(1.0, 0.95, 0.7, 0.05 + 0.1 * pr), false, 1.0)
	elif t < tele + PILLAR_LIVE:
		var f: float = (t - tele) / PILLAR_LIVE
		var h: float = ar.size.y
		b.draw_rect(Rect2(x - w * 0.5, ar.position.y, w, h), Color(1.0, 0.88, 0.45, 0.8))
		b.draw_rect(Rect2(x - w * 0.25, ar.position.y, w * 0.5, h), Color(1.0, 0.97, 0.75, 0.95))
		b.draw_rect(Rect2(x - w * 0.1, ar.position.y, w * 0.2, h), Color(1.0, 1.0, 0.9, 0.9 * (1.0 - f * 0.5)))
	else:
		var f2: float = 1.0 - (t - tele - PILLAR_LIVE) / 0.2
		b.draw_rect(Rect2(x - w * 0.3, ar.position.y, w * 0.6, ar.size.y), Color(1.0, 0.92, 0.6, 0.3 * f2))


func _draw_prism(pr: Dictionary) -> void:
	var t: float = pr["t"]
	var tele: float = pr["tele"]
	var live: float = pr["live"]
	var pos: Vector2 = pr["pos"]
	if t < tele:
		var p: float = t / tele
		var pulse: float = 0.5 + 0.5 * sin(t * 26.0)
		for a: float in pr["angs"]:
			var seg: Array = _clip(pos, Vector2(cos(a), sin(a)), true)
			if not seg.is_empty():
				b.draw_line(seg[0], seg[1], Color(1.0, 0.95, 0.6, 0.15 + 0.3 * p * pulse), 1.0)
		b.draw_circle(pos, 4.0 + 6.0 * p, Color(1.0, 0.95, 0.6, 0.9))
		b.draw_arc(pos, 9.0 + 6.0 * (1.0 - p), 0.0, TAU, 20, Color(1.0, 0.9, 0.5, 0.7), 1.5)
	elif t < tele + live:
		for a2: float in pr["angs"]:
			var seg2: Array = _clip(pos, Vector2(cos(a2), sin(a2)), true)
			if seg2.is_empty():
				continue
			var v: float = vis(Geometry2D.get_closest_point_to_segment(b.soul, seg2[0], seg2[1]))
			b.draw_line(seg2[0], seg2[1], Color(1.0, 0.85, 0.4, 0.6 * v), 9.0)
			b.draw_line(seg2[0], seg2[1], Color(1.0, 1.0, 0.95, v), 4.0)
		b.draw_circle(pos, 11.0, Color(1, 1, 1, 1))
	else:
		var f: float = 1.0 - (t - tele - live) / 0.2
		b.draw_circle(pos, 11.0 * f, Color(1.0, 0.9, 0.6, f))


func _draw_streak(s: Dictionary) -> void:
	var ar: Rect2 = arena_rect()
	var horiz: bool = s["horiz"]
	var c: float = s["c"]
	var sgn: float = s["sgn"]
	var t: float = s["t"]
	var tele: float = s["tele"]
	if t < tele:
		# warning: chevrons on the edge it will enter from + a faint lane
		var blink: float = 0.5 + 0.5 * sin(t * 36.0)
		var edge: float
		var lane: Rect2
		if horiz:
			edge = ar.position.x + 6.0 if sgn > 0.0 else ar.end.x - 6.0
			lane = Rect2(ar.position.x, c - 9.0, ar.size.x, 18.0)
			for k in 3:
				var xx: float = edge + sgn * float(k) * 9.0
				b.draw_line(Vector2(xx, c - 7.0), Vector2(xx + sgn * 7.0, c), Color(1.0, 0.92, 0.55, 0.4 + 0.5 * blink), 2.0)
				b.draw_line(Vector2(xx, c + 7.0), Vector2(xx + sgn * 7.0, c), Color(1.0, 0.92, 0.55, 0.4 + 0.5 * blink), 2.0)
		else:
			edge = ar.position.y + 6.0 if sgn > 0.0 else ar.end.y - 6.0
			lane = Rect2(c - 9.0, ar.position.y, 18.0, ar.size.y)
			for k in 3:
				var yy: float = edge + sgn * float(k) * 9.0
				b.draw_line(Vector2(c - 7.0, yy), Vector2(c, yy + sgn * 7.0), Color(1.0, 0.92, 0.55, 0.4 + 0.5 * blink), 2.0)
				b.draw_line(Vector2(c + 7.0, yy), Vector2(c, yy + sgn * 7.0), Color(1.0, 0.92, 0.55, 0.4 + 0.5 * blink), 2.0)
		b.draw_rect(lane, Color(1.0, 0.92, 0.55, 0.06 + 0.06 * blink))
	else:
		var a: float = s["a"]
		var pa: Vector2 = Vector2(a, c) if horiz else Vector2(c, a)
		var dir: Vector2 = (Vector2(sgn, 0) if horiz else Vector2(0, sgn))
		var inside: Rect2 = ar
		# trail + head, only drawn inside the arena
		for k in 8:
			var p: Vector2 = pa - dir * float(k) * 9.0
			if inside.has_point(p):
				var f: float = 1.0 - float(k) / 8.0
				b.draw_circle(p, 9.0 * f + 2.0, Color(1.0, 0.9 + 0.1 * f, 0.5 + 0.45 * f, 0.25 + 0.7 * f))


# ------------------------------------------------------------------ drawing: Katashi (placeholder art)
func draw_boss(shake: Vector2, alpha: float) -> void:
	var bob: float = sin(clock * 3.0) * 2.0
	var o: Vector2 = Vector2(boss_x, BOSS_BASE.y) + shake + Vector2(0, bob)
	var sp: float = absf(boss_vx)
	if sp > 120.0:
		var sg: float = -signf(boss_vx)
		for k in 3:
			_figure(o + Vector2(sg * (14.0 + 16.0 * float(k)), 0), alpha * (0.32 - 0.09 * float(k)), true)
	_figure(o, alpha, false)


func _figure(o: Vector2, alpha: float, ghost: bool) -> void:
	var gold := Color(1.0, 0.82, 0.3, alpha)
	var robe := Color(0.96, 0.93, 0.85, alpha)
	var robe2 := Color(0.85, 0.5, 0.2, alpha)
	var skin := Color(0.95, 0.8, 0.65, alpha)
	var flame1 := Color(1.0, 0.75, 0.3, alpha)
	var flame2 := Color(1.0, 0.98, 0.8, alpha)
	if ghost:
		gold = Color(1.0, 0.9, 0.5, alpha)
		robe = Color(1.0, 0.95, 0.7, alpha)
		robe2 = Color(1.0, 0.7, 0.3, alpha)
	var p: String = pose if pose_t > 0.0 or pose == "cast" else "idle"
	# halo
	var hc: Vector2 = o + Vector2(0, -126)
	b.draw_circle(hc, 26.0, Color(1.0, 0.9, 0.5, 0.10 * alpha))
	b.draw_arc(hc, 22.0, 0.0, TAU, 36, gold, 3.0)
	b.draw_arc(hc, 26.0, 0.0, TAU, 36, Color(gold, gold.a * 0.35), 2.0)
	for i in 12:   # radiant rays
		var ra: float = TAU * float(i) / 12.0 + clock * 0.5
		b.draw_line(hc + Vector2(cos(ra), sin(ra)) * 30.0, hc + Vector2(cos(ra), sin(ra)) * (36.0 + 5.0 * sin(clock * 5.0 + float(i))), Color(gold, gold.a * 0.6), 2.0)
	# robe + sash
	b.draw_colored_polygon(PackedVector2Array([o + Vector2(-34, 0), o + Vector2(34, 0), o + Vector2(20, -72), o + Vector2(-20, -72)]), robe)
	b.draw_colored_polygon(PackedVector2Array([o + Vector2(-22, -68), o + Vector2(22, -68), o + Vector2(15, -98), o + Vector2(-15, -98)]), robe2)
	b.draw_line(o + Vector2(-18, -70), o + Vector2(18, -70), gold, 4.0)
	b.draw_line(o + Vector2(0, -70), o + Vector2(0, -2), Color(gold, gold.a * 0.7), 3.0)
	# arms
	var lh := Vector2(-32, -58)
	var rh := Vector2(32, -58)
	match p:
		"slash":
			rh = Vector2(46, -84)
			lh = Vector2(-26, -70)
		"cast":
			lh = Vector2(-42, -122)
			rh = Vector2(42, -122)
	var armc := Color(0.95, 0.75, 0.45, alpha)
	b.draw_line(o + Vector2(-17, -92), o + lh, armc, 7.0)
	b.draw_line(o + Vector2(17, -92), o + rh, armc, 7.0)
	b.draw_circle(o + lh, 6.0, skin)
	b.draw_circle(o + rh, 6.0, skin)
	if p == "slash":   # blade of light
		b.draw_line(o + rh, o + rh + Vector2(34, -34), Color(1, 1, 0.9, alpha), 4.0)
		b.draw_line(o + rh, o + rh + Vector2(34, -34), Color(1.0, 0.9, 0.5, alpha * 0.5), 9.0)
	if p == "cast":
		b.draw_circle(o + lh, 10.0, Color(1.0, 0.95, 0.7, alpha * 0.55))
		b.draw_circle(o + rh, 10.0, Color(1.0, 0.95, 0.7, alpha * 0.55))
	# head + flame hair
	b.draw_circle(o + Vector2(0, -108), 14.0, skin)
	for i in 5:
		var fx: float = -12.0 + 6.0 * float(i)
		var fl: float = 14.0 + 6.0 * sin(clock * 9.0 + float(i) * 1.7) + (4.0 if i == 2 else 0.0)
		b.draw_colored_polygon(PackedVector2Array([o + Vector2(fx - 5, -116), o + Vector2(fx + 5, -116), o + Vector2(fx, -116 - fl)]), flame1 if i % 2 == 0 else flame2)
	b.draw_rect(Rect2(o + Vector2(-8, -111), Vector2(5, 4)), gold)
	b.draw_rect(Rect2(o + Vector2(3, -111), Vector2(5, 4)), gold)
	b.draw_line(o + Vector2(-5, -101), o + Vector2(6, -102), Color(0.5, 0.25, 0.2, alpha), 2.0)
