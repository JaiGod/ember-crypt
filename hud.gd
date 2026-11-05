extends Control
## Ember Crypt — HUD, menus, touch controls and minimap, all drawn in _draw().
## Buttons register their rects in g.buttons so the game can hit-test
## mouse clicks and touch taps with one code path.

const Game = preload("res://game.gd")

var g: Game = null
var font: Font
var map_img: Image
var map_tex: ImageTexture
var map_t := 0.0

const ORANGE := Color(1.0, 0.58, 0.18)
const GOLD := Color(1.0, 0.84, 0.36)
const PAPER := Color(0.96, 0.9, 0.8)
const DIM := Color(0.7, 0.62, 0.56)
const PANEL := Color(0.07, 0.05, 0.06, 0.92)


func _ready() -> void:
	font = ThemeDB.fallback_font
	map_img = Image.create(72, 52, false, Image.FORMAT_RGBA8)
	map_tex = ImageTexture.create_from_image(map_img)


func _process(delta: float) -> void:
	map_t -= delta
	if map_t <= 0.0 and g != null and g.state == Game.St.PLAY:
		map_t = 0.25
		refresh_map()


func refresh_map() -> void:
	map_img.fill(Color(0, 0, 0, 0))
	var grid: PackedByteArray = g.grid
	var seen: PackedByteArray = g.seen
	if grid.size() != 72 * 52:
		return
	for y in 52:
		for x in 72:
			var i := y * 72 + x
			if seen[i] == 1:
				map_img.set_pixel(x, y, Color(0.75, 0.6, 0.5, 0.85) if grid[i] == 1 else Color(0.3, 0.22, 0.2, 0.85))
	map_tex.update(map_img)


func _draw() -> void:
	if g == null:
		return
	g.buttons.clear()
	var vs := get_viewport_rect().size
	match g.state:
		Game.St.TITLE:
			draw_title(vs)
		Game.St.PLAY:
			draw_hud(vs)
			if g.touch_mode:
				draw_touch(vs)
		Game.St.PAUSE:
			draw_hud(vs)
			draw_pause(vs)
		Game.St.UPGRADE:
			draw_hud(vs)
			draw_upgrade(vs)
		Game.St.DEAD, Game.St.WIN:
			draw_hud(vs)
			draw_summary(vs)
	if g.fade > 0.0:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, g.fade))


# ---------------------------------------------------------------- helpers
func text(pos: Vector2, s: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, outline := 3) -> void:
	if outline > 0:
		draw_string_outline(font, pos, s, align, width, size, outline, Color(0, 0, 0, col.a * 0.9))
	draw_string(font, pos, s, align, width, size, col)


func ctext(y: float, s: String, size: int, col: Color, vs: Vector2, outline := 3) -> void:
	text(Vector2(0, y), s, size, col, HORIZONTAL_ALIGNMENT_CENTER, vs.x, outline)


func btn(r: Rect2, id: String, label: String, primary := false) -> void:
	var hover := r.has_point(get_local_mouse_position()) and not g.touch_mode
	var bg := Color(0.45, 0.16, 0.08, 0.95) if primary else Color(0.13, 0.09, 0.1, 0.95)
	if hover:
		bg = bg.lightened(0.18)
	draw_rect(r, bg)
	draw_rect(r, ORANGE if primary or hover else Color(0.5, 0.38, 0.32), false, 1.0)
	draw_rect(Rect2(r.position + Vector2(1, 1), Vector2(r.size.x - 2, 1)), Color(1, 1, 1, 0.12))
	var fs := 11 if r.size.y >= 22 else 9
	text(Vector2(r.position.x, r.position.y + r.size.y * 0.5 + fs * 0.36), label, fs, PAPER, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 2)
	g.buttons.append({"rect": r, "id": id})


func panel(r: Rect2) -> void:
	draw_rect(r, PANEL)
	draw_rect(r, Color(0.55, 0.32, 0.18), false, 1.0)
	draw_rect(r.grow(-3), Color(0.3, 0.18, 0.12, 0.6), false, 1.0)


func embers_bg(vs: Vector2, n: int) -> void:
	for i in n:
		var sp := 14.0 + float(i % 7) * 6.0
		var x := fmod(float(i) * 97.31, vs.x) + sin(g.time * 1.3 + i) * 6.0
		var y := vs.y + 10.0 - fmod(g.time * sp + float(i) * 53.7, vs.y + 30.0)
		var a := clampf(y / vs.y, 0.0, 1.0)
		var s := 1.0 + float(i % 3)
		draw_rect(Rect2(x, y, s, s), Color(1, 0.45 + 0.3 * float(i % 4) / 4.0, 0.1, a * 0.8))


# ---------------------------------------------------------------- title
func draw_title(vs: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.03, 0.02, 0.03))
	var c := Vector2(vs.x * 0.5, vs.y * 0.42)
	var fl := 0.9 + 0.1 * sin(g.time * 9.0) + 0.05 * sin(g.time * 23.0)
	for k in 7:
		draw_circle(c, (190.0 - k * 24.0) * fl, Color(1, 0.4, 0.1, 0.025 + k * 0.006))
	embers_bg(vs, 46)
	# crypt arch silhouette
	var aw := minf(vs.x * 0.6, 300.0)
	var ab := c.y + 34.0
	draw_rect(Rect2(c.x - aw * 0.5, ab, aw, 4), Color(0.25, 0.15, 0.12))
	draw_arc(Vector2(c.x, ab), aw * 0.45, PI, TAU, 40, Color(0.35, 0.2, 0.15, 0.7), 3.0)
	draw_arc(Vector2(c.x, ab), aw * 0.45 - 6.0, PI, TAU, 40, Color(0.2, 0.12, 0.1, 0.6), 2.0)
	g.draw_flame(Vector2(c.x - aw * 0.45, ab - 2), 1.6, 1.0, self)
	g.draw_flame(Vector2(c.x + aw * 0.45, ab - 2), 1.6, 2.0, self)
	if g.show_help:
		draw_help(vs)
		return
	var title_col := ORANGE.lerp(GOLD, 0.5 + 0.5 * sin(g.time * 3.0))
	ctext(c.y - 18.0, "EMBER CRYPT", 42, title_col, vs, 6)
	ctext(c.y + 4.0, "a torchlit roguelike descent", 11, DIM, vs, 2)
	var bw := 150.0
	var by := c.y + 48.0
	btn(Rect2(c.x - bw * 0.5, by, bw, 26), "start", "BEGIN DESCENT", true)
	btn(Rect2(c.x - bw * 0.5, by + 32, bw * 0.48, 20), "help", "HOW TO PLAY")
	btn(Rect2(c.x + bw * 0.02, by + 32, bw * 0.48, 20), "sound", "SOUND: " + ("ON" if g.sfx.enabled else "OFF"))
	var best := int(g.save.get("best", 0))
	if best > 0:
		ctext(by + 72.0, "Best score %d   ·   Deepest floor %d   ·   Runs %d" % [best, int(g.save.get("deepest", 0)), int(g.save.get("runs", 0))], 9, GOLD, vs, 2)
	ctext(vs.y - 8.0, "Made by Jaineil Rana (JaKing)  ·  JaiGod", 8, Color(0.6, 0.5, 0.45), vs, 2)
	if not g.touch_mode:
		ctext(by + 86.0, "Enter to begin  ·  H for help  ·  M toggles sound", 8, Color(0.6, 0.52, 0.48), vs, 2)


func draw_help(vs: Vector2) -> void:
	var w := minf(vs.x - 24.0, 400.0)
	var h := 214.0
	var r := Rect2((vs.x - w) * 0.5, (vs.y - h) * 0.5, w, h)
	panel(r)
	text(Vector2(r.position.x, r.position.y + 20), "HOW TO PLAY", 15, ORANGE, HORIZONTAL_ALIGNMENT_CENTER, w)
	var lines := [
		["Move", "WASD / arrows  ·  left thumb stick"],
		["Attack", "Click or J (aim with mouse)  ·  ATK button"],
		["Dash", "Space / Shift / right-click  ·  DASH button"],
		["Pause", "Esc or P  ·  pause icon    Minimap: Tab"],
	]
	var y := r.position.y + 42.0
	for l in lines:
		text(Vector2(r.position.x + 16, y), String(l[0]), 10, GOLD, HORIZONTAL_ALIGNMENT_LEFT, -1, 2)
		text(Vector2(r.position.x + 70, y), String(l[1]), 10, PAPER, HORIZONTAL_ALIGNMENT_LEFT, -1, 2)
		y += 15.0
	y += 4.0
	var tips := [
		"Your torch burns down. Grab embers to refuel; in darkness the crypt bites.",
		"Light braziers to rekindle fully and leave a light behind you.",
		"Swap weapons by walking over them: sword, axe, spear or wand.",
		"Find the stairs, pick a blessing. A boss waits every 5th floor.",
		"Death is permanent. Defeat the Ashen King on floor 10 to win.",
	]
	for t in tips:
		text(Vector2(r.position.x + 16, y), "-  " + String(t), 9, DIM, HORIZONTAL_ALIGNMENT_LEFT, w - 24, 2)
		y += 13.0
	btn(Rect2(vs.x * 0.5 - 50, r.end.y - 30, 100, 22), "help", "BACK", true)


# ---------------------------------------------------------------- in-game HUD
func draw_hud(vs: Vector2) -> void:
	# hearts
	for i in g.max_hp:
		var pos := Vector2(12 + i * 12, 12)
		g.draw_heart(self, pos + Vector2(1, 1), 1.15, Color(0, 0, 0, 0.6))
		g.draw_heart(self, pos, 1.15, Color(0.95, 0.2, 0.25) if i < g.hp else Color(0.25, 0.12, 0.14))
	# torch bar
	var tb := Rect2(18, 22, 82, 7)
	var frac: float = clampf(g.torch / g.torch_max, 0.0, 1.0)
	draw_rect(tb.grow(1), Color(0, 0, 0, 0.7))
	draw_rect(tb, Color(0.15, 0.08, 0.06))
	var low: bool = g.torch < 22.0
	var fill := ORANGE.lerp(GOLD, frac)
	if low and int(g.time * 6.0) % 2 == 0:
		fill = Color(1, 0.2, 0.15)
	draw_rect(Rect2(tb.position, Vector2(tb.size.x * frac, tb.size.y)), fill)
	draw_rect(Rect2(tb.position, Vector2(tb.size.x * frac, 2)), Color(1, 1, 0.8, 0.35))
	g.draw_flame(Vector2(10, 30), 0.8, 0.0, self)
	text(Vector2(104, 29), "TORCH", 8, DIM, HORIZONTAL_ALIGNMENT_LEFT, -1, 2)
	# weapon
	g.draw_weapon(self, Vector2(8, 44), g.weapon, -0.5, 0.9, Color.WHITE)
	text(Vector2(26, 44), String(Game.WEAPONS[g.weapon]["name"]), 9, PAPER, HORIZONTAL_ALIGNMENT_LEFT, -1, 2)
	# floor + gold
	ctext(14, "FLOOR %d" % g.floor_n, 10, GOLD, vs, 3)
	text(Vector2(vs.x * 0.5 - 40, 26), "%d gold   %d kills" % [g.gold, g.kills], 8, DIM, HORIZONTAL_ALIGNMENT_CENTER, 80, 2)
	# top-right buttons
	if g.state == Game.St.PLAY:
		var pr := Rect2(vs.x - 24, 4, 20, 20)
		btn(pr, "pause", "")
		draw_rect(Rect2(pr.position + Vector2(6, 5), Vector2(3, 10)), PAPER)
		draw_rect(Rect2(pr.position + Vector2(11, 5), Vector2(3, 10)), PAPER)
		var sr := Rect2(vs.x - 48, 4, 20, 20)
		btn(sr, "sound", "")
		var sc := sr.position + Vector2(5, 7)
		draw_rect(Rect2(sc, Vector2(3, 6)), PAPER)
		draw_colored_polygon(PackedVector2Array([sc + Vector2(3, 0), sc + Vector2(7, -3), sc + Vector2(7, 9), sc + Vector2(3, 6)]), PAPER)
		if not g.sfx.enabled:
			draw_line(sr.position + Vector2(4, 4), sr.end - Vector2(4, 4), Color(1, 0.3, 0.2), 2.0)
		var mr := Rect2(vs.x - 72, 4, 20, 20)
		btn(mr, "map", "")
		draw_rect(Rect2(mr.position + Vector2(5, 6), Vector2(10, 8)), Color(0, 0, 0, 0), false, 1.0)
		draw_rect(Rect2(mr.position + Vector2(5, 6), Vector2(10, 8)), PAPER, false, 1.0)
		draw_rect(Rect2(mr.position + Vector2(9, 9), Vector2(2, 2)), ORANGE)
	# minimap
	if g.show_map:
		var ms := 1.4
		var mpos := Vector2(vs.x - 72 * ms - 6, 30)
		var mr2 := Rect2(mpos - Vector2(2, 2), Vector2(72, 52) * ms + Vector2(4, 4))
		draw_rect(mr2, Color(0.05, 0.03, 0.03, 0.55))
		draw_rect(mr2, Color(0.4, 0.26, 0.2, 0.6), false, 1.0)
		draw_texture_rect(map_tex, Rect2(mpos, Vector2(72, 52) * ms), false)
		var pp: Vector2 = mpos + g.p_pos / Game.T * ms
		draw_rect(Rect2(pp - Vector2(1.5, 1.5), Vector2(3, 3)), ORANGE if int(g.time * 4.0) % 2 == 0 else GOLD)
		if g.stairs_open and g.seen_px(g.stairs):
			var sp: Vector2 = mpos + g.stairs / Game.T * ms
			draw_rect(Rect2(sp - Vector2(1.5, 1.5), Vector2(3, 3)), Color(0.4, 1.0, 0.6))
	# boss bar
	if g.boss != null and g.boss.active:
		var bw := minf(vs.x - 40.0, 260.0)
		var br := Rect2((vs.x - bw) * 0.5, vs.y - 22.0 if not g.touch_mode else 40.0, bw, 6)
		draw_rect(br.grow(1), Color(0, 0, 0, 0.8))
		draw_rect(Rect2(br.position, Vector2(bw * g.boss.hp / g.boss.maxhp, 6)), Color(1, 0.35, 0.1))
		text(Vector2(br.position.x, br.position.y - 3), "THE CINDER WARDEN" if g.boss.tier == 1 else "THE ASHEN KING", 9, ORANGE, HORIZONTAL_ALIGNMENT_CENTER, bw, 2)
	# low torch border
	if g.torch <= 0.0:
		var a := 0.35 + 0.25 * sin(g.time * 8.0)
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0.4, 0.4, 1.0, a), false, 3.0)
	elif g.hurt_t > 0.0:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(1, 0.1, 0.1, g.hurt_t * 1.4), false, 4.0)
	# banner
	if g.banner_t > 0.0 and g.state == Game.St.PLAY:
		var a2: float = clampf(g.banner_t, 0.0, 1.0)
		ctext(vs.y * 0.3, g.banner, 22, Color(ORANGE, a2), vs, 4)
		if g.floor_n == 1 and not g.touch_mode:
			ctext(vs.y * 0.3 + 16, "WASD move  ·  click / J attack  ·  Space dash", 9, Color(PAPER, a2), vs, 2)
		elif g.floor_n == 1:
			ctext(vs.y * 0.3 + 16, "left stick move  ·  ATK attack  ·  DASH dodge", 9, Color(PAPER, a2), vs, 2)


func draw_touch(vs: Vector2) -> void:
	var jc: Vector2 = g.joy_center if g.joy_idx >= 0 else Vector2(64, vs.y - 60)
	draw_circle(jc, 34.0, Color(1, 1, 1, 0.07))
	draw_arc(jc, 34.0, 0, TAU, 32, Color(1, 0.8, 0.6, 0.25), 1.5)
	draw_circle(jc + g.joy_vec * 30.0, 13.0, Color(1, 0.7, 0.4, 0.35))
	var ap: Vector2 = g.atk_btn_pos()
	draw_circle(ap, 28.0, Color(0.6, 0.15, 0.08, 0.45 if g.atk_idx < 0 else 0.75))
	draw_arc(ap, 28.0, 0, TAU, 32, Color(1, 0.6, 0.3, 0.6), 1.5)
	g.draw_weapon(self, ap + Vector2(-8, 6), g.weapon, -0.8, 1.1, Color.WHITE)
	var dp: Vector2 = g.dash_btn_pos()
	var ready: bool = g.dash_cd <= 0.0
	draw_circle(dp, 20.0, Color(0.2, 0.15, 0.3, 0.5 if ready else 0.25))
	if not ready:
		var k: float = clampf(1.0 - g.dash_cd / (0.8 * float(g.stats["dash"])), 0.0, 1.0)
		draw_arc(dp, 20.0, -PI * 0.5, -PI * 0.5 + TAU * k, 24, Color(0.8, 0.7, 1.0, 0.7), 2.0)
	else:
		draw_arc(dp, 20.0, 0, TAU, 24, Color(0.8, 0.7, 1.0, 0.7), 1.5)
	text(Vector2(dp.x - 20, dp.y + 3), "DASH", 8, PAPER, HORIZONTAL_ALIGNMENT_CENTER, 40, 2)


# ---------------------------------------------------------------- overlays
func draw_pause(vs: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.6))
	var w := 200.0
	var r := Rect2((vs.x - w) * 0.5, vs.y * 0.5 - 80, w, 160)
	panel(r)
	text(Vector2(r.position.x, r.position.y + 24), "PAUSED", 18, ORANGE, HORIZONTAL_ALIGNMENT_CENTER, w)
	var x := r.position.x + 30
	btn(Rect2(x, r.position.y + 38, w - 60, 22), "resume", "RESUME", true)
	btn(Rect2(x, r.position.y + 66, w - 60, 22), "sound", "SOUND: " + ("ON" if g.sfx.enabled else "OFF"))
	btn(Rect2(x, r.position.y + 94, w - 60, 22), "restart", "NEW RUN")
	btn(Rect2(x, r.position.y + 122, w - 60, 22), "title", "QUIT TO TITLE")


func draw_upgrade(vs: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.72))
	embers_bg(vs, 20)
	var cy := vs.y * 0.5
	ctext(cy - 72, "FLOOR %d CLEARED" % g.floor_n, 18, ORANGE, vs, 4)
	ctext(cy - 56, "Choose a blessing for the descent", 10, DIM, vs, 2)
	var n: int = g.choices.size()
	var gap := 10.0
	var cw := minf(128.0, (vs.x - 20.0 - gap * 2.0) / 3.0)
	var total := n * cw + (n - 1) * gap
	var x0 := (vs.x - total) * 0.5
	for i in n:
		var u: Dictionary = g.choices[i]
		var r := Rect2(x0 + i * (cw + gap), cy - 40, cw, 96)
		var sel: bool = i == g.choice_sel or (r.has_point(get_local_mouse_position()) and not g.touch_mode)
		draw_rect(r, Color(0.16, 0.08, 0.06, 0.95) if sel else Color(0.09, 0.06, 0.07, 0.95))
		draw_rect(r, ORANGE if sel else Color(0.45, 0.3, 0.25), false, 1.5 if sel else 1.0)
		g.draw_flame(Vector2(r.position.x + cw * 0.5, r.position.y + 26), 1.4, float(i), self)
		text(Vector2(r.position.x, r.position.y + 46), String(u["name"]), 11, GOLD, HORIZONTAL_ALIGNMENT_CENTER, cw, 2)
		draw_multiline_string(font, Vector2(r.position.x + 8, r.position.y + 62), String(u["desc"]), HORIZONTAL_ALIGNMENT_CENTER, cw - 16, 9, -1, PAPER)
		text(Vector2(r.position.x, r.end.y - 6), "[%d]" % (i + 1), 8, DIM, HORIZONTAL_ALIGNMENT_CENTER, cw, 2)
		g.buttons.append({"rect": r, "id": "up%d" % i})
	if g.taken.size() > 0:
		ctext(cy + 74, "Blessings: " + ", ".join(g.taken), 8, Color(0.65, 0.55, 0.5), vs, 2)


func draw_summary(vs: Vector2) -> void:
	var won: bool = g.state == Game.St.WIN
	var k: float = clampf(g.end_t / 0.8, 0.0, 1.0)
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.78 * k))
	if won:
		embers_bg(vs, 40)
	var w := minf(vs.x - 24.0, 300.0)
	var h := 196.0
	var r := Rect2((vs.x - w) * 0.5, (vs.y - h) * 0.5 + (1.0 - k) * 20.0, w, h)
	panel(r)
	var title := "THE CRYPT IS CLEANSED" if won else "YOUR TORCH GUTTERS OUT"
	text(Vector2(r.position.x, r.position.y + 24), title, 15, GOLD if won else Color(1, 0.4, 0.3), HORIZONTAL_ALIGNMENT_CENTER, w)
	var sub := "The Ashen King is ash. You walk out into dawn." if won else "Permadeath. The crypt keeps your bones."
	text(Vector2(r.position.x, r.position.y + 38), sub, 9, DIM, HORIZONTAL_ALIGNMENT_CENTER, w, 2)
	var t: float = g.run_time
	var rows := [
		["Floor reached", str(g.floor_n)],
		["Foes slain", str(g.kills)],
		["Gold", str(g.gold)],
		["Weapon", String(Game.WEAPONS[g.weapon]["name"])],
		["Time", "%d:%02d" % [int(t) / 60, int(t) % 60]],
		["Blessings", str(g.taken.size())],
	]
	var y := r.position.y + 56.0
	for row in rows:
		text(Vector2(r.position.x + 24, y), String(row[0]), 10, DIM, HORIZONTAL_ALIGNMENT_LEFT, -1, 2)
		text(Vector2(r.position.x + 24, y), String(row[1]), 10, PAPER, HORIZONTAL_ALIGNMENT_RIGHT, w - 48, 2)
		y += 13.0
	text(Vector2(r.position.x, y + 8), "SCORE  %d" % g.score, 14, ORANGE, HORIZONTAL_ALIGNMENT_CENTER, w)
	if g.new_best:
		text(Vector2(r.position.x, y + 20), "NEW BEST!", 9, GOLD.lerp(Color.WHITE, 0.5 + 0.5 * sin(g.time * 8.0)), HORIZONTAL_ALIGNMENT_CENTER, w, 2)
	else:
		text(Vector2(r.position.x, y + 20), "Best %d" % int(g.save.get("best", 0)), 9, DIM, HORIZONTAL_ALIGNMENT_CENTER, w, 2)
	if g.end_t > 0.8:
		btn(Rect2(r.position.x + 20, r.end.y - 30, w * 0.5 - 26, 22), "restart", "DESCEND AGAIN", true)
		btn(Rect2(r.position.x + w * 0.5 + 6, r.end.y - 30, w * 0.5 - 26, 22), "title", "TITLE")
