extends RefCounted
## Keras, wielder of the Dominion Breaker - a sword that cuts through ANYTHING, even
## things that aren't physical. In the story he is as fast as Katashi; here he fights deliberately
## (long, readable warnings) purely for balance - but every cut is huge.
##
## Moves (a turn is a chain of 2-3, with long gaps):
##   heavy      Heavy Slash   two big line-cuts, one after the other; the cut stays open as a crack
##   cross      Cross Cut     an X through the arena - hide in a wedge
##   judgment   Judgment      a vertical cut that follows you, then locks and falls
##   edge       Falling Edge  a blade sweeps the whole arena with one gap to slip through
##   partition  Partition     he cuts the ARENA itself - one half is severed (void) for a moment
##   sever      Sever Slash   thin violet cut: if it touches you it severs your buffs + Frost Armor
##   metronome  Metronome     cuts swing from a pivot in a fixed sweep, then the return sweep lands in the gaps
##                            you were hiding in - identical every time, so it can be learned
## Phase 2 (mode): at 40% HP he SPARES you and waits. If you keep fighting he goes ALL-OUT -
## the speed he always had: warnings about half as long, longer chains, bigger/more frequent
## Dominion attacks, and a new move: Flurry (rapid thin cuts).
## Big attack - Dominion: a rhythm of overlapping cuts, ending in one enormous diagonal that,
## if it connects, also cuts one of your menu options away for a turn.
## And just before each of his turns, the sword cuts the poison off him.

const CENTER := Vector2(320, 265)
const HALF := Vector2(110, 75)
const BOSS_BASE := Vector2(320, 186)

const D_HEAVY := 34
const D_CROSS := 34
const D_JUDGMENT := 44
const D_EDGE := 30
const D_PART := 22
const D_SEVER := 18
const D_FINAL := 50
const D_CRACK := 8

const SLASH_LIVE := 0.2
const SLASH_FADE := 0.3
const CRACK_LIFE := 2.0

var b   # battle node (untyped on purpose)

# ---- art (assets/Keras). Pose frames are cropped to different sizes, so each is aligned by where its
# coat starts (COAT_TOP = row of the coat's top edge in that file). Head and legs are separate pieces.
const SPR_SCALE := 3.0
const SPRITES := {
	"idle": "Keras", "out": "Kerasswordslightout", "down": "Kerassworddown", "down2": "Kerassworddown2",
	"moveup": "Kerasswordmoveup", "up": "Kerasswordup", "head": "KerasHead", "legs": "KerasLegs",
	"back": "KerasBodyBack",
}
const COAT_TOP := {"idle": 2, "out": 2, "down": 2, "down2": 10, "moveup": 16, "up": 16}
# Everything is placed in sprite pixels relative to the idle frame's top-left. His neck and coat
# buttons sit on column 8 of the body frame, so the head's face/chin (col 6.5 of the head) and the
# hips (gap between the legs, col 6.5 of the legs) are both lined up on that column.
const HEAD_AT := Vector2(2, -9)
const LEGS_AT := Vector2(2, 14)
const BACK_AT := Vector2(2, 7)    # the shirt: sits behind the whole torso, showing through the open coat
const FEET := Vector2(8.5, 31.0)  # the point that sits on BOSS_BASE
var tex: Dictionary = {}

# interface the battle expects from a boss engine
var morph: float = 0.0
var circle_mode: bool = false
var finished: bool = false

var phase: String = "chain"
var queue: Array = []
var cur: Dictionary = {}
var gap: float = 0.0
var linger: float = 0.0
var big_phase: String = "windup"
var big_t: float = 0.0
var big_spawn: float = 0.0
var big_cuts: int = 0
var big_sever_done: bool = false
var turn_t: float = 0.0
var turns_since_big: int = 0
var last_kind: String = ""
var clock: float = 0.0
var mode: String = "fight"       # fight | spared | allout
var sword_pose: String = ""      # drawn-blade moments only (all-out): up | swing | down
var sword_t: float = 0.0
var boss_x: float = 320.0
var boss_tx: float = 320.0
var boss_vx: float = 0.0

var pose: String = "idle"
var pose_t: float = 0.0

var slashes: Array = []
var edges: Array = []
var parts: Array = []
var cracks: Array = []


func _init(battle) -> void:
	b = battle
	for key: String in SPRITES:
		tex[key] = load("res://assets/Keras/%s.png" % SPRITES[key])


# ------------------------------------------------------------------ helpers
func arena_rect() -> Rect2:
	return Rect2(CENTER - HALF, HALF * 2.0)


func box_rect() -> Rect2:
	return arena_rect()


func draw_arena() -> void:
	pass   # the arena is never reshaped (partition only darkens a half of it)


func pace() -> float:
	return 0.5 if mode == "allout" else 1.0   # all-out warnings last about half as long


func begin_spared() -> void:
	mode = "spared"
	slashes.clear()
	edges.clear()
	parts.clear()
	cracks.clear()
	pose = "idle"


func begin_allout() -> void:
	mode = "allout"
	turns_since_big = 2   # a Dominion attack can come right away
	b.add_shake(0.9)
	sword_pose = "up"   # he draws the blade all the way as he stops holding back
	sword_t = 1.0


func tick(delta: float) -> void:
	clock += delta
	sword_t = maxf(0.0, sword_t - delta)
	if sword_t <= 0.0:
		sword_pose = ""
	var old: float = boss_x
	boss_x = move_toward(boss_x, boss_tx, 1300.0 * delta)
	boss_vx = lerpf(boss_vx, (boss_x - old) / maxf(delta, 0.0001), 0.5)


func _down(k1: Key, k2: Key) -> bool:
	return Input.is_physical_key_pressed(k1) or Input.is_physical_key_pressed(k2)


func _clip(p: Vector2, dir: Vector2) -> Array:
	# clip the infinite line through p (direction dir) to the arena -> [a, b] or []
	var ar: Rect2 = arena_rect()
	var tmin: float = -1000.0
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


func _dir(kind: int) -> Vector2:
	match kind:
		0:
			return Vector2(1, 0)
		1:
			return Vector2(0, 1)
		_:
			return Vector2.from_angle((PI * 0.25 + randf_range(-0.18, 0.18)) * (1.0 if randf() < 0.5 else -1.0))


# ------------------------------------------------------------------ turn control
func start_turn() -> void:
	slashes.clear()
	edges.clear()
	parts.clear()
	cracks.clear()
	queue.clear()
	cur = {}
	gap = 0.5 * pace()
	linger = 0.0
	turn_t = 0.0
	finished = false
	pose = "idle"
	b.soul = CENTER
	boss_tx = 320.0
	var big: bool = turns_since_big >= 2 and (turns_since_big >= 4 or randf() < 0.4)
	if mode == "allout":
		big = turns_since_big >= 1 and (turns_since_big >= 3 or randf() < 0.5)
	if big:
		phase = "big"
		big_phase = "windup"
		big_t = 0.0
		big_cuts = 0
		big_sever_done = false
		turns_since_big = 0
	else:
		phase = "chain"
		turns_since_big += 1
		for i in (randi_range(5, 7) if mode == "allout" else randi_range(2, 3)):
			queue.append(_pick_kind())


func _pick_kind() -> String:
	var kinds: Array = ["heavy", "cross", "judgment", "edge", "partition", "sever", "metronome"]
	if mode == "allout":
		kinds.append("flurry")
		kinds.append("flurry")
	var k: String = kinds.pick_random()
	while k == last_kind:
		k = kinds.pick_random()
	last_kind = k
	return k


func _all_clear() -> bool:
	return slashes.is_empty() and edges.is_empty() and parts.is_empty() and cracks.is_empty()


func update(delta: float) -> bool:
	turn_t += delta
	pose_t = maxf(0.0, pose_t - delta)
	_move_soul(delta)
	if phase == "chain":
		_update_chain(delta)
	else:
		_update_big(delta)
	_update_slashes(delta)
	_update_edges(delta)
	_update_parts(delta)
	_update_cracks(delta)
	if turn_t > 28.0:
		slashes.clear()
		edges.clear()
		parts.clear()
		cracks.clear()
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
			if linger >= 0.6:
				finished = true
		return
	_run_attack(delta)


func _begin_attack(kind: String) -> void:
	cur = {"kind": kind, "t": 0.0, "step": 0}
	pose = "raise"
	pose_t = 1.0 * pace()
	if mode == "allout":
		boss_tx = randf_range(250.0, 390.0)   # he blinks about above the arena


func _end_attack() -> void:
	cur = {}
	gap = randf_range(0.5, 0.9) * pace()


func _run_attack(delta: float) -> void:
	cur["t"] += delta
	var t: float = cur["t"]
	var step: int = cur["step"]
	var pc: float = pace()
	match cur["kind"]:
		"heavy":
			if step < 2 and t >= float(step) * 0.85 * pc:
				_spawn_heavy(step == 1)
				cur["step"] = step + 1
			if step >= 2 and t >= (0.85 + 1.0) * pc:
				_end_attack()
		"cross":
			if step == 0:
				_spawn_cross()
				cur["step"] = 1
			if t >= 1.2 * pc:
				_end_attack()
		"judgment":
			if step == 0:
				_spawn_judgment()
				cur["step"] = 1
			if t >= 1.4 * pc:
				_end_attack()
		"edge":
			if step == 0:
				_spawn_edge()
				cur["step"] = 1
			if t >= 2.2 * pc:
				_end_attack()
		"partition":
			if step == 0:
				_spawn_partition()
				cur["step"] = 1
			if t >= 1.9 * pc:
				_end_attack()
		"sever":
			if step == 0:
				_spawn_sever()
				cur["step"] = 1
			if t >= 1.2 * pc:
				_end_attack()
		"metronome":
			if step == 0:
				cur["end"] = _spawn_metronome()
				cur["step"] = 1
			if step >= 1 and t >= float(cur["end"]):
				_end_attack()
		"flurry":
			# all-out only: six thin, fast cuts raining through the area around you
			if step < 6 and t >= float(step) * 0.2:
				_spawn_flurry_cut()
				pose = "slash"
				pose_t = 0.15
				cur["step"] = step + 1
			if step >= 6 and t >= 1.2 + 0.3:
				_end_attack()


# ------------------------------------------------------------------ slashes
func _add_slash(p: Vector2, dir: Vector2, w: float, tele: float, dmg: int, kind: String, track: String = "", delay: float = 0.0) -> void:
	var seg: Array = _clip(p, dir)
	if seg.is_empty():
		return
	slashes.append({"a": seg[0], "b": seg[1], "dir": dir, "w": w, "t": -delay, "tele": tele, "dmg": dmg,
		"kind": kind, "track": track})


func _spawn_heavy(second: bool) -> void:
	var ar: Rect2 = arena_rect()
	var p: Vector2 = b.soul + Vector2(randf_range(-22.0, 22.0), randf_range(-18.0, 18.0))
	if randf() < 0.4:
		p = Vector2(randf_range(ar.position.x + 10.0, ar.end.x - 10.0), randf_range(ar.position.y + 10.0, ar.end.y - 10.0))
	_add_slash(p, _dir(randi_range(0, 2)), 16.0, 0.95 * pace(), D_HEAVY, "heavy")


func _spawn_cross() -> void:
	var c: Vector2 = CENTER + Vector2(randf_range(-35.0, 35.0), randf_range(-25.0, 25.0))
	_add_slash(c, Vector2.from_angle(PI * 0.25), 14.0, 1.1 * pace(), D_CROSS, "heavy")
	_add_slash(c, Vector2.from_angle(-PI * 0.25), 14.0, 1.1 * pace(), D_CROSS, "heavy")


func _spawn_judgment() -> void:
	var vertical: bool = randf() < 0.8
	var sp: Vector2 = b.soul
	var dir: Vector2 = Vector2(0, 1) if vertical else Vector2(1, 0)
	_add_slash(sp, dir, 32.0, 1.35 * pace(), D_JUDGMENT, "heavy", "x" if vertical else "y")


func _spawn_sever() -> void:
	var sp: Vector2 = b.soul
	var vertical: bool = randf() < 0.5
	_add_slash(sp + Vector2(randf_range(-15.0, 15.0), randf_range(-12.0, 12.0)), Vector2(0, 1) if vertical else Vector2(1, 0), 10.0, 1.0 * pace(), D_SEVER, "sever")


func _spawn_flurry_cut() -> void:
	var p: Vector2 = (b.soul as Vector2) + Vector2(randf_range(-30.0, 30.0), randf_range(-24.0, 24.0))
	_add_slash(p, _dir(randi_range(0, 2)), 12.0, 0.4, 26, "flurry")


# Metronome (rhythmic): cuts swing out from a pivot at the bottom-center in a fixed sweep:
# -60, -30, 0, +30, +60 degrees, then the RETURN sweep lands exactly in the gaps you were hiding in:
# +45, +15, -15, -45. One cut per beat, same every time - hop into the next gap on the beat.
func _spawn_metronome() -> float:
	var ar: Rect2 = arena_rect()
	var pivot := Vector2(CENTER.x, ar.end.y + 6.0)
	var beat: float = 0.5 * pace()
	var tele: float = 0.8 * pace()
	var angs: Array = [-60.0, -30.0, 0.0, 30.0, 60.0, 45.0, 15.0, -15.0, -45.0]
	for i in angs.size():
		var a: float = deg_to_rad(angs[i])
		_add_slash(pivot, Vector2(sin(a), -cos(a)), 14.0, tele, D_HEAVY - 4, "metro", "", float(i) * beat)
	pose = "raise"
	pose_t = 1.0
	return float(angs.size() - 1) * beat + tele * 0.6


func _spawn_final() -> void:
	var c: Vector2 = CENTER + Vector2(randf_range(-20.0, 20.0), randf_range(-15.0, 15.0))
	var ang: float = (0.55 + randf_range(-0.1, 0.1)) * (1.0 if randf() < 0.5 else -1.0)
	_add_slash(c, Vector2.from_angle(ang), 64.0, 1.5 * (0.7 if mode == "allout" else 1.0), D_FINAL, "final")


func _quad(s: Dictionary, extra: float = 0.0) -> PackedVector2Array:
	var a: Vector2 = s["a"]
	var bb: Vector2 = s["b"]
	var d: Vector2 = s["dir"]
	var n := Vector2(-d.y, d.x) * (float(s["w"]) * 0.5 + extra)
	return PackedVector2Array([a + n, bb + n, bb - n, a - n])


func _update_slashes(delta: float) -> void:
	var keep: Array = []
	for s: Dictionary in slashes:
		s["t"] += delta
		var t: float = s["t"]
		var tele: float = s["tele"]
		# Judgment follows the SOUL until shortly before it falls
		if s["track"] != "" and t < tele - minf(0.45, tele * 0.4):
			var sp: Vector2 = b.soul
			var seg: Array = _clip(Vector2(sp.x if s["track"] == "x" else CENTER.x, sp.y if s["track"] == "y" else CENTER.y), s["dir"])
			if not seg.is_empty():
				s["a"] = seg[0]
				s["b"] = seg[1]
		if t >= tele and t < tele + SLASH_LIVE:
			var near: Vector2 = Geometry2D.get_closest_point_to_segment(b.soul, s["a"], s["b"])
			if near.distance_to(b.soul) < float(s["w"]) * 0.5 + 3.0:
				if b.hurt(int(s["dmg"])):
					if s["kind"] == "sever":
						b.sever()
					elif s["kind"] == "final":
						b.cut_menu()
			if not s.has("struck"):
				s["struck"] = true
				b.add_shake(0.5 if s["kind"] != "sever" else 0.25)
				pose = "slash"
				pose_t = 0.3
				if s["kind"] == "heavy" and float(s["w"]) < 20.0:
					cracks.append({"a": s["a"], "b": s["b"], "t": 0.0})
		if t < tele + SLASH_LIVE + SLASH_FADE:
			keep.append(s)
	slashes = keep


func _update_cracks(delta: float) -> void:
	var keep: Array = []
	for c: Dictionary in cracks:
		c["t"] += delta
		if float(c["t"]) >= SLASH_LIVE * 0.5:   # starts hurting once the cut has landed
			var near: Vector2 = Geometry2D.get_closest_point_to_segment(b.soul, c["a"], c["b"])
			if near.distance_to(b.soul) < 5.0:
				b.hurt(D_CRACK)
		if float(c["t"]) < CRACK_LIFE:
			keep.append(c)
	cracks = keep


# ------------------------------------------------------------------ Falling Edge
func _spawn_edge() -> void:
	var ar: Rect2 = arena_rect()
	var gw: float = 64.0
	var gx: float = clampf(float(b.soul.x) + randf_range(-45.0, 45.0), ar.position.x + gw * 0.5 + 6.0, ar.end.x - gw * 0.5 - 6.0)
	var down: bool = randf() < 0.5
	edges.append({"gx": gx, "gw": gw, "down": down, "t": 0.0, "tele": 0.85 * pace(), "speed": 100.0 / pace(), "y": ar.position.y if down else ar.end.y, "hit": false})


func _update_edges(delta: float) -> void:
	var ar: Rect2 = arena_rect()
	var keep: Array = []
	for e: Dictionary in edges:
		e["t"] += delta
		var tele: float = e["tele"]
		var done: bool = false
		if float(e["t"]) >= tele:
			var dirn: float = 1.0 if e["down"] else -1.0
			e["y"] += dirn * float(e["speed"]) * delta
			var y: float = e["y"]
			var sp: Vector2 = b.soul
			var half_gap: float = float(e["gw"]) * 0.5
			if absf(sp.y - y) < 10.0 and absf(sp.x - float(e["gx"])) > half_gap - 2.0:
				b.hurt(D_EDGE)
			done = y < ar.position.y - 20.0 or y > ar.end.y + 20.0
			if not e.has("struck"):
				e["struck"] = true
				b.add_shake(0.2)
		if not done:
			keep.append(e)
	edges = keep


# ------------------------------------------------------------------ Partition
func _spawn_partition() -> void:
	var c: Vector2 = CENTER + Vector2(randf_range(-30.0, 30.0), randf_range(-22.0, 22.0))
	var dir: Vector2 = _dir(randi_range(0, 2))
	var seg: Array = _clip(c, dir)
	if seg.is_empty():
		return
	var n := Vector2(-dir.y, dir.x)
	# severed side: usually the one the SOUL is standing on, so it has to move
	var side: float = signf(((b.soul as Vector2) - c).dot(n))
	if side == 0.0 or randf() > 0.75:
		side = 1.0 if randf() < 0.5 else -1.0
	parts.append({"c": c, "a": seg[0], "b": seg[1], "n": n * side, "t": 0.0, "tele": 1.0 * pace(), "life": 1.6})


func _half_poly(pt: Dictionary) -> PackedVector2Array:
	# the arena rect clipped to the severed half-plane (Sutherland-Hodgman, one plane)
	var ar: Rect2 = arena_rect()
	var corners: Array = [ar.position, Vector2(ar.end.x, ar.position.y), ar.end, Vector2(ar.position.x, ar.end.y)]
	var c: Vector2 = pt["c"]
	var n: Vector2 = pt["n"]
	var out := PackedVector2Array()
	for i in corners.size():
		var p: Vector2 = corners[i]
		var q: Vector2 = corners[(i + 1) % corners.size()]
		var dp: float = (p - c).dot(n)
		var dq: float = (q - c).dot(n)
		if dp >= 0.0:
			out.append(p)
		if (dp >= 0.0) != (dq >= 0.0):
			out.append(p.lerp(q, dp / (dp - dq)))
	return out


func _update_parts(delta: float) -> void:
	var keep: Array = []
	for pt: Dictionary in parts:
		pt["t"] += delta
		var t: float = pt["t"]
		var tele: float = pt["tele"]
		var life: float = pt["life"]
		if t >= tele and t < tele + life:
			if not pt.has("struck"):
				pt["struck"] = true
				b.add_shake(0.35)
				pose = "slash"
				pose_t = 0.3
			if ((b.soul as Vector2) - (pt["c"] as Vector2)).dot(pt["n"]) > 0.0:
				b.hurt(D_PART)
		if t < tele + life + 0.3:
			keep.append(pt)
	parts = keep


# ------------------------------------------------------------------ Dominion (big attack)
func _update_big(delta: float) -> void:
	big_t += delta
	match big_phase:
		"windup":
			pose = "raise"
			pose_t = 0.5
			pass
			b.rumble(0.3)
			if big_t >= 1.0 * pace():
				big_phase = "play"
				big_t = 0.0
				big_spawn = 0.1
		"play":
			pose = "raise" if pose_t <= 0.0 else pose
			big_spawn -= delta
			if big_t < 8.0 and big_spawn <= 0.0:
				_spawn_big_cut()
				big_spawn = randf_range(0.6, 0.85) * pace()
			if big_t >= 8.0 and slashes.is_empty():
				big_phase = "final"
				big_t = 0.0
				_spawn_final()
				pass
				pose = "raise"
				pose_t = 1.8
		"final":
			b.rumble(0.3)
			if big_t >= 1.5 * (0.7 if mode == "allout" else 1.0) + SLASH_LIVE + SLASH_FADE + 0.2:
				big_phase = "recover"
				big_t = 0.0
		"recover":
			if big_t >= 0.8 and _all_clear():
				pose = "idle"
				finished = true


func _spawn_big_cut() -> void:
	big_cuts += 1
	if not big_sever_done and big_cuts >= 4 and randf() < 0.5:
		big_sever_done = true
		_spawn_sever()
	elif randf() < 0.3:
		_spawn_cross()
	else:
		_spawn_heavy(false)
	pose = "slash"
	pose_t = 0.25


# ------------------------------------------------------------------ drawing: attacks
func draw_attacks() -> void:
	for pt: Dictionary in parts:
		_draw_part(pt)
	for c: Dictionary in cracks:
		_draw_crack(c)
	for e: Dictionary in edges:
		_draw_edge(e)
	for s: Dictionary in slashes:
		_draw_slash(s)


func _edge_color(kind: String) -> Color:
	match kind:
		"sever":
			return Color(0.9, 0.5, 1.0)
		"final":
			return Color(1.0, 0.95, 0.85)
		_:
			return Color(0.6, 0.92, 1.0)


func _draw_slash(s: Dictionary) -> void:
	var t: float = s["t"]
	if t < 0.0:
		return
	var tele: float = s["tele"]
	var kind: String = s["kind"]
	var col: Color = _edge_color(kind)
	var d: Vector2 = s["dir"]
	var a: Vector2 = s["a"]
	var bb: Vector2 = s["b"]
	var n := Vector2(-d.y, d.x) * (float(s["w"]) * 0.5)
	if t < tele:
		var p: float = t / tele
		var blink: float = 0.5 + 0.5 * sin(t * 18.0)
		var fill: Color = Color(col, 0.04 + 0.16 * p)
		if kind == "final":
			fill = Color(1.0, 0.3, 0.3, 0.05 + 0.18 * p)
		b.draw_colored_polygon(_quad(s), fill)
		b.draw_line(a + n, bb + n, Color(col, 0.35 + 0.5 * p * blink), 2.0)
		b.draw_line(a - n, bb - n, Color(col, 0.35 + 0.5 * p * blink), 2.0)
		b.draw_line(a, bb, Color(col, 0.15 + 0.25 * p), 1.0)
	elif t < tele + SLASH_LIVE:
		# the cut itself: a tear with bright edges and a white core
		b.draw_colored_polygon(_quad(s), Color(0.08, 0.0, 0.14, 1.0))
		b.draw_line(a + n, bb + n, col, 3.0)
		b.draw_line(a - n, bb - n, col, 3.0)
		b.draw_line(a, bb, Color(1, 1, 1, 0.95), maxf(2.0, float(s["w"]) * 0.25))
	else:
		var f: float = 1.0 - (t - tele - SLASH_LIVE) / SLASH_FADE
		b.draw_colored_polygon(_quad(s), Color(0.08, 0.0, 0.14, 0.6 * f))
		b.draw_line(a + n, bb + n, Color(col, f), 2.0)
		b.draw_line(a - n, bb - n, Color(col, f), 2.0)


func _draw_crack(c: Dictionary) -> void:
	var t: float = c["t"]
	var f: float = clampf(1.0 - t / CRACK_LIFE, 0.0, 1.0)
	var flick: float = 0.7 + 0.3 * sin(t * 25.0)
	b.draw_line(c["a"], c["b"], Color(0.6, 0.92, 1.0, 0.5 * f * flick), 5.0)
	b.draw_line(c["a"], c["b"], Color(1, 1, 1, 0.9 * f * flick), 1.5)


func _draw_edge(e: Dictionary) -> void:
	var ar: Rect2 = arena_rect()
	var t: float = e["t"]
	var tele: float = e["tele"]
	var gx: float = e["gx"]
	var half_gap: float = float(e["gw"]) * 0.5
	var down: bool = e["down"]
	var col := Color(0.6, 0.92, 1.0)
	if t < tele:
		var blink: float = 0.5 + 0.5 * sin(t * 18.0)
		var y0: float = ar.position.y + 4.0 if down else ar.end.y - 4.0
		# the blade waiting at the edge, with the gap marked
		b.draw_line(Vector2(ar.position.x, y0), Vector2(gx - half_gap, y0), Color(col, 0.5 + 0.4 * blink), 3.0)
		b.draw_line(Vector2(gx + half_gap, y0), Vector2(ar.end.x, y0), Color(col, 0.5 + 0.4 * blink), 3.0)
		b.draw_rect(Rect2(gx - half_gap, ar.position.y, half_gap * 2.0, ar.size.y), Color(0.5, 1.0, 0.7, 0.06 + 0.06 * blink))
	else:
		var y: float = e["y"]
		for seg in [[ar.position.x, gx - half_gap], [gx + half_gap, ar.end.x]]:
			var x0: float = seg[0]
			var x1: float = seg[1]
			if x1 > x0:
				b.draw_rect(Rect2(x0, y - 7.0, x1 - x0, 14.0), Color(0.08, 0.0, 0.14))
				b.draw_line(Vector2(x0, y - 7.0), Vector2(x1, y - 7.0), col, 2.0)
				b.draw_line(Vector2(x0, y + 7.0), Vector2(x1, y + 7.0), col, 2.0)
				b.draw_line(Vector2(x0, y), Vector2(x1, y), Color(1, 1, 1, 0.9), 2.0)


func _draw_part(pt: Dictionary) -> void:
	var t: float = pt["t"]
	var tele: float = pt["tele"]
	var life: float = pt["life"]
	var poly: PackedVector2Array = _half_poly(pt)
	var a: Vector2 = pt["a"]
	var bb: Vector2 = pt["b"]
	if poly.size() < 3:
		return
	if t < tele:
		var p: float = t / tele
		var blink: float = 0.5 + 0.5 * sin(t * 16.0)
		b.draw_colored_polygon(poly, Color(0.7, 0.3, 1.0, 0.05 + 0.15 * p * blink))
		b.draw_line(a, bb, Color(0.9, 0.6, 1.0, 0.4 + 0.5 * p), 2.0)
	elif t < tele + life:
		var pulse: float = 0.5 + 0.5 * sin(t * 12.0)
		b.draw_colored_polygon(poly, Color(0.18, 0.0, 0.3, 0.85))
		b.draw_colored_polygon(poly, Color(0.8, 0.3, 1.0, 0.12 + 0.12 * pulse))
		b.draw_line(a, bb, Color(1, 1, 1, 0.95), 3.0)
	else:
		var f: float = 1.0 - (t - tele - life) / 0.3
		b.draw_colored_polygon(poly, Color(0.18, 0.0, 0.3, 0.7 * f))
		b.draw_line(a, bb, Color(1, 1, 1, f), 2.0)


# ------------------------------------------------------------------ drawing: Keras (placeholder art)
func draw_boss(shake: Vector2, alpha: float) -> void:
	var bob: float = sin(clock * (1.2 if mode != "allout" else 3.0)) * 2.0
	var o: Vector2 = Vector2(boss_x, BOSS_BASE.y) + shake + Vector2(0, bob)
	if mode == "allout":
		b.draw_circle(o + Vector2(0, -70), 70.0 + 5.0 * sin(clock * 9.0), Color(1.0, 0.1, 0.15, 0.10 * alpha))
		if absf(boss_vx) > 120.0:   # speed afterimages: the pace he always could keep
			var sg: float = -signf(boss_vx)
			for k in 3:
				_figure(o + Vector2(sg * (14.0 + 16.0 * float(k)), 0), alpha * (0.30 - 0.09 * float(k)), true)
	_figure(o, alpha, false)


func _is_attacking() -> bool:
	return (pose_t > 0.0 and (pose == "raise" or pose == "slash")) or (mode == "allout" and sword_t > 0.0)


func _frame_name() -> String:
	# HOLDING BACK (fight / spared): sheathed. At rest he is just Keras.png; when he attacks he only
	# goes to "sword slightly out" - he casts the cuts through the air without drawing the blade.
	if mode != "allout":
		if mode == "fight" and pose_t > 0.0 and (pose == "raise" or pose == "slash"):
			return "out"
		return "idle"
	# ALL-OUT: he draws the Dominion Breaker all the way.
	if sword_t > 0.0 and sword_pose == "up":
		return "up"   # the draw itself, right when he stops holding back
	if pose_t > 0.0:
		if pose == "raise":
			return "up"
		if pose == "slash":
			return "moveup" if pose_t > 0.2 else "down2"
	return "down"


func _spr(key: String, at: Vector2, o: Vector2, tint: Color) -> void:
	var t: Texture2D = tex[key]
	var tl: Vector2 = o + (at - FEET) * SPR_SCALE
	b.draw_texture_rect(t, Rect2(Vector2(roundf(tl.x), roundf(tl.y)), t.get_size() * SPR_SCALE), false, tint)


func _sway() -> Vector2:
	# From the Scratch script: x drifts -2 -> -4 -> -2 in a triangle wave while y bumps up by 1 at the
	# middle of each pass (y = 1 - |x - center|), 4 segments of ~10 frames. Only while he's not attacking.
	if _is_attacking():
		return Vector2.ZERO
	var u: float = fposmod(clock / 1.4, 1.0)
	var xr: float = 1.0 - 4.0 * u if u < 0.5 else -1.0 + 4.0 * (u - 0.5)   # +1 .. -1 .. +1
	var yr: float = 1.0 - absf(xr)
	return Vector2(roundf(xr * 2.0), -roundf(yr * 1.5))


func _figure(o: Vector2, alpha: float, ghost: bool) -> void:
	var tint := Color(1, 1, 1, alpha)
	if ghost:
		tint = Color(0.6, 0.85, 1.0, alpha)
	var frame: String = _frame_name()
	var oo: Vector2 = o
	var body_o: Vector2 = oo + _sway()
	_spr("back", BACK_AT, oo + _sway(), tint)   # furthest back of all
	_spr("legs", LEGS_AT, oo, tint)   # legs stay planted; the body sways above them
	_spr(frame, Vector2(0, float(2 - int(COAT_TOP[frame]))), body_o, tint)
	_spr("head", HEAD_AT, body_o, tint)
