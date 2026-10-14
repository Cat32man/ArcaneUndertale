extends RefCounted
## Pixel-font text helpers (static). Uses assets/font/pixel_font.png, made by tools/make_pixel_font.py.
## `size` keeps the old point-size meaning; it just picks an integer pixel scale.
## All draw calls go through the CanvasItem you pass in, so call them from inside its _draw().

const CELL_W := 6
const CELL_H := 9
const COLS := 16
const BODY := 7   # rows above the baseline


static func scale_for(size: int) -> int:
	if size >= 32:
		return 4
	if size >= 22:
		return 3
	if size >= 14:
		return 2
	return 1


static func width(s: String, sc: int) -> float:
	return float(maxi(0, s.length() * CELL_W - 1) * sc)


# pos is the BASELINE-left, like draw_string.
static func draw(canvas: CanvasItem, tex: Texture2D, s: String, pos: Vector2, size: int = 16, col: Color = Color.WHITE, w: float = -1.0, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var sc: int = scale_for(size)
	var x: float = pos.x
	if w > 0.0:
		if align == HORIZONTAL_ALIGNMENT_CENTER:
			x += (w - width(s, sc)) * 0.5
		elif align == HORIZONTAL_ALIGNMENT_RIGHT:
			x += w - width(s, sc)
	x = roundf(x)
	var y: float = roundf(pos.y) - float(BODY * sc)
	for i in s.length():
		var code: int = s.unicode_at(i)
		if code == 32:
			continue
		if code < 33 or code > 127:
			code = 63   # '?'
		var idx: int = code - 32
		var src := Rect2(float((idx % COLS) * CELL_W), float((idx / COLS) * CELL_H), 5.0, float(CELL_H))
		var dst := Rect2(x + float(i * CELL_W * sc), y, float(5 * sc), float(CELL_H * sc))
		canvas.draw_texture_rect_region(tex, dst, src, col)


static func wrap_text(s: String, max_w: float, sc: int) -> Array:
	var per_line: int = maxi(1, int((max_w + float(sc)) / float(CELL_W * sc)))
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


# Draws a (possibly wrapped) paragraph, revealing `shown` characters (-1 = all).
static func paragraph(canvas: CanvasItem, tex: Texture2D, s: String, top_left: Vector2, max_w: float, size: int = 20, col: Color = Color.WHITE, shown: int = -1) -> void:
	var sc: int = scale_for(size)
	var lines: Array = wrap_text(s, max_w, sc)
	var left: int = shown if shown >= 0 else 1000000
	for i in lines.size():
		if left <= 0:
			break
		var line: String = lines[i]
		draw(canvas, tex, line.substr(0, left), top_left + Vector2(0, float(BODY * sc) + 6.0 + float(i) * float(CELL_H * sc + 6)), size, col)
		left -= line.length() + 1
