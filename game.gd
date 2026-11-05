extends Node2D
## Ember Crypt — core game: state machine, player, enemies, lighting, world drawing.
## Everything you see is drawn in _draw() with primitives; no image assets.

const Gen = preload("res://gen.gd")
const T := 16
const MW := 72
const MH := 52
const P_R := 5.0
const FINAL_FLOOR := 10
const SAVE_PATH := "user://ember_crypt.save"

enum St { TITLE, PLAY, PAUSE, UPGRADE, DEAD, WIN }

const WEAPONS := {
	"sword": {"name": "Ember Sword", "dmg": 2.0, "range": 23.0, "arc": 120.0, "cd": 0.30, "kb": 90.0, "col": Color(0.88, 0.92, 1.0)},
	"axe": {"name": "Cleaver Axe", "dmg": 4.0, "range": 25.0, "arc": 180.0, "cd": 0.66, "kb": 180.0, "col": Color(1.0, 0.62, 0.4)},
	"spear": {"name": "Bone Spear", "dmg": 3.0, "range": 40.0, "arc": 40.0, "cd": 0.42, "kb": 120.0, "col": Color(0.96, 0.9, 0.72)},
	"wand": {"name": "Cinder Wand", "dmg": 2.0, "range": 0.0, "arc": 0.0, "cd": 0.36, "kb": 60.0, "col": Color(1.0, 0.5, 0.9)},
}

const UPGRADES := [
	{"id": "heart", "name": "Ember Heart", "desc": "+1 max HP, heal fully"},
	{"id": "whet", "name": "Whetstone", "desc": "+20% weapon damage"},
	{"id": "pitch", "name": "Pitch Torch", "desc": "+30 torch fuel capacity"},
	{"id": "wick", "name": "Slow Wick", "desc": "Torch burns 20% slower"},
	{"id": "boots", "name": "Fleet Boots", "desc": "+12% move speed"},
	{"id": "step", "name": "Shadowstep", "desc": "Dash recharges 25% faster"},
	{"id": "magnet", "name": "Ember Lure", "desc": "Pull pickups from afar"},
	{"id": "spark", "name": "Kindled Blade", "desc": "Attacks throw a spark"},
	{"id": "vamp", "name": "Bloodflame", "desc": "Heal 1 HP every 6 kills"},
	{"id": "mend", "name": "Mend", "desc": "Heal 3 HP"},
]

class Enemy:
	var kind := ""
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var kb := Vector2.ZERO
	var aim := Vector2.RIGHT
	var hp := 1.0
	var maxhp := 1.0
	var r := 5.0
	var spd := 30.0
	var t := 0.0
	var cd := 1.0
	var mode := 0
	var flash := 0.0
	var active := false
	var small := false
	var dead := false
	var fired := false
	var dmg := 1
	var tier := 1
	var sd := 0.0
	var pattern := 0

class Proj:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var dmg := 1.0
	var mine := false
	var life := 2.5
	var r := 3.0
	var col := Color.WHITE
	var dead := false

class Pick:
	var kind := ""
	var pos := Vector2.ZERO
	var val := ""
	var amount := 1
	var t := 0.0
	var dead := false

class Part:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var life := 0.5
	var maxl := 0.5
	var col := Color.WHITE
	var size := 2.0
	var grav := 0.0
	var text := ""

@onready var cam: Camera2D = $Cam
@onready var sfx: Node = $Sfx
@onready var hud: Control = $UI/HUD

var rng := RandomNumberGenerator.new()
var font: Font
var state := St.TITLE
var show_help := false
var time := 0.0
var grid := PackedByteArray()
var seen := PackedByteArray()
var lightmap := PackedFloat32Array()
var lit_idx := PackedInt32Array()
var rooms: Array[Rect2i] = []
var floor_n := 1
var enemies: Array[Enemy] = []
var projs: Array[Proj] = []
var picks: Array[Pick] = []
var parts: Array[Part] = []
var braziers: Array = []  # [{pos, lit}]
var stairs := Vector2(-9999, -9999)
var stairs_open := true
var boss: Enemy = null

# player
var p_pos := Vector2.ZERO
var p_vel := Vector2.ZERO
var p_kb := Vector2.ZERO
var p_face := Vector2.RIGHT
var aim := Vector2.RIGHT
var hp := 5
var max_hp := 5
var torch := 100.0
var torch_max := 100.0
var weapon := "sword"
var atk_cd := 0.0
var swing_t := 0.0
var swing_dir := Vector2.RIGHT
var dash_t := 0.0
var dash_cd := 0.0
var dash_dir := Vector2.RIGHT
var inv_t := 0.0
var dark_t := 0.0
var hurt_t := 0.0
var swap_cd := 0.0
var walk_t := 0.0
var stats := {}
var taken: Array[String] = []

# run stats
var kills := 0
var gold := 0
var run_time := 0.0
var score := 0
var new_best := false
var save := {"best": 0, "deepest": 0, "runs": 0, "sound": true}

# feel
var shake := 0.0
var hitstop := 0.0
var fade := 0.0
var banner := ""
var banner_t := 0.0
var end_t := 0.0
var win_pending := -1.0

# upgrade menu
var choices: Array = []
var choice_sel := 0

# input
var buttons: Array = []  # [{rect, id}] rebuilt by HUD each frame
var touch_mode := false
var joy_idx := -1
var joy_center := Vector2.ZERO
var joy_vec := Vector2.ZERO
var atk_idx := -1
var mouse_down := false
var mouse_block := false
var mouse_aim_t := 0.0
var want_dash := false
var show_map := true

# smoke test bot
var smoke := false
var smoke_t := 0.0
var smoke_phase := 0
var demo := false  # web dev hook (?demo=1): auto-pilot used for README screenshots
var shot_times: Array = []  # web dev hook (?shots=2,5): capture JPEGs into window.__shots


func _ready() -> void:
	rng.randomize()
	font = ThemeDB.fallback_font
	load_save()
	sfx.enabled = bool(save.get("sound", true))
	hud.g = self
	smoke = "--smoke" in OS.get_cmdline_user_args()
	if smoke:
		print("[smoke] starting")
	# dev hook for testing the web build: ?floor=N starts a run on floor N
	if OS.has_feature("web"):
		var st = JavaScriptBridge.eval("new URLSearchParams(location.search).get('shots') || ''")
		if st is String:
			for t in String(st).split(",", false):
				if t.is_valid_float():
					shot_times.append(float(t))
		var q = JavaScriptBridge.eval("new URLSearchParams(location.search).get('floor') || ''")
		if q is String and String(q).is_valid_int():
			new_run()
			floor_n = clampi(int(q), 1, FINAL_FLOOR)
			build_floor()
			if JavaScriptBridge.eval("new URLSearchParams(location.search).get('demo') || ''") == "1":
				demo = true
				if boss != null:
					p_pos = room_center(rooms[1]) + Vector2(0, 5 * T)
				else:
					for i in mini(5, enemies.size()):
						enemies[i].pos = rand_floor_in(rooms[0])
					inv_t = 3.0
				cam.position = p_pos
				cam.reset_smoothing()


# ---------------------------------------------------------------- save
func load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if data is Dictionary:
		for k in data:
			save[k] = data[k]


func write_save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(save))


func toggle_sound() -> void:
	sfx.enabled = not sfx.enabled
	save["sound"] = sfx.enabled
	write_save()
	sfx.play("click")


# ---------------------------------------------------------------- run flow
func new_run() -> void:
	stats = {"dmg": 1.0, "speed": 1.0, "burn": 1.0, "dash": 1.0, "magnet": 0.0, "spark": 0, "vamp": 0}
	taken.clear()
	max_hp = 5
	hp = max_hp
	torch_max = 100.0
	torch = torch_max
	weapon = "sword"
	kills = 0
	gold = 0
	run_time = 0.0
	floor_n = 1
	new_best = false
	win_pending = -1.0
	state = St.PLAY
	build_floor()
	sfx.play("stairs")


func build_floor() -> void:
	var is_boss := floor_n % 5 == 0
	var d: Dictionary = Gen.make(rng, MW, MH, floor_n, is_boss)
	grid = d["grid"]
	rooms.clear()
	for r in d["rooms"]:
		rooms.append(r)
	seen = PackedByteArray()
	seen.resize(MW * MH)
	seen.fill(0)
	lightmap = PackedFloat32Array()
	lightmap.resize(MW * MH)
	lightmap.fill(0.0)
	lit_idx.clear()
	enemies.clear()
	projs.clear()
	picks.clear()
	parts.clear()
	braziers.clear()
	boss = null
	p_pos = room_center(rooms[0])
	p_vel = Vector2.ZERO
	p_kb = Vector2.ZERO
	dash_t = 0.0
	inv_t = 1.0
	if is_boss:
		var arena := rooms[1]
		var e := make_enemy("boss", room_center(arena))
		e.tier = floor_n / 5
		e.maxhp = 70.0 + 50.0 * (e.tier - 1)
		e.hp = e.maxhp
		boss = e
		stairs = room_center(arena)
		stairs_open = false
		for c in [Vector2(-10, -7), Vector2(10, -7), Vector2(-10, 7), Vector2(10, 7)]:
			braziers.append({"pos": room_center(arena) + c * T, "lit": false})
		for i in 4:
			add_pick("ember", rand_floor_in(arena))
		add_pick("heart", room_center(rooms[0]) + Vector2(20, 0))
		banner = "THE CINDER WARDEN" if e.tier == 1 else "THE ASHEN KING"
	else:
		var far := 1
		var fd := 0.0
		for i in range(1, rooms.size()):
			var dd := room_center(rooms[i]).distance_to(p_pos)
			if dd > fd:
				fd = dd
				far = i
		stairs = room_center(rooms[far])
		stairs_open = true
		for i in range(1, rooms.size()):
			var n := rng.randi_range(1, 2 + floor_n / 4)
			for k in n:
				make_enemy(pick_kind(), rand_floor_in(rooms[i]))
		for i in 4 + rng.randi_range(0, 2):
			add_pick("ember", rand_floor_in(rooms[rng.randi_range(0, rooms.size() - 1)]))
		for i in rng.randi_range(1, 2):
			var rr := rooms[rng.randi_range(1, rooms.size() - 1)]
			braziers.append({"pos": room_center(rr) + Vector2(T, 0), "lit": false})
		for i in 1 + (floor_n % 2):
			add_pick("chest", rand_floor_in(rooms[rng.randi_range(1, rooms.size() - 1)]))
		if rng.randf() < 0.45:
			var wp := add_pick("weapon", rand_floor_in(rooms[rng.randi_range(1, rooms.size() - 1)]))
			wp.val = random_weapon_not(weapon)
		for i in rng.randi_range(3, 6):
			var gp := add_pick("gold", rand_floor_in(rooms[rng.randi_range(0, rooms.size() - 1)]))
			gp.amount = rng.randi_range(1, 3)
		banner = "FLOOR %d" % floor_n
	banner_t = 2.6
	fade = 1.0
	cam.position = p_pos
	cam.reset_smoothing()


func pick_kind() -> String:
	var pool: Array[String] = ["skitter", "skitter", "ooze"]
	if floor_n >= 2:
		pool.append_array(["knight", "ooze"])
	if floor_n >= 3:
		pool.append_array(["wisp", "knight"])
	if floor_n >= 4:
		pool.append_array(["shade", "wisp"])
	if floor_n >= 7:
		pool.append_array(["shade", "knight"])
	return pool[rng.randi_range(0, pool.size() - 1)]


func random_weapon_not(w: String) -> String:
	var ks: Array = WEAPONS.keys()
	ks.erase(w)
	return ks[rng.randi_range(0, ks.size() - 1)]


func make_enemy(kind: String, pos: Vector2) -> Enemy:
	var e := Enemy.new()
	e.kind = kind
	e.pos = pos
	e.sd = rng.randf() * 100.0
	e.cd = rng.randf_range(0.5, 1.5)
	var sc := 1.0 + 0.14 * (floor_n - 1)
	match kind:
		"skitter":
			e.hp = 2.0; e.r = 4.0; e.spd = 58.0
		"ooze":
			e.hp = 5.0; e.r = 6.0; e.spd = 0.0
		"knight":
			e.hp = 8.0; e.r = 6.0; e.spd = 26.0
		"wisp":
			e.hp = 4.0; e.r = 5.0; e.spd = 40.0
		"shade":
			e.hp = 6.0; e.r = 5.0; e.spd = 34.0; e.cd = 2.0
		"boss":
			e.hp = 70.0; e.r = 13.0; e.spd = 22.0; e.cd = 2.0; e.dmg = 2
	if kind != "boss":
		e.hp *= sc
	e.maxhp = e.hp
	enemies.append(e)
	return e


func add_pick(kind: String, pos: Vector2) -> Pick:
	var p := Pick.new()
	p.kind = kind
	p.pos = pos
	p.t = rng.randf() * 6.0
	picks.append(p)
	return p


func room_center(r: Rect2i) -> Vector2:
	var c := r.get_center()
	return Vector2(c.x * T + T * 0.5, c.y * T + T * 0.5)


func rand_floor_in(r: Rect2i) -> Vector2:
	for i in 30:
		var x := rng.randi_range(r.position.x + 1, r.end.x - 2)
		var y := rng.randi_range(r.position.y + 1, r.end.y - 2)
		if grid[y * MW + x] == 1:
			return Vector2(x * T + T * 0.5, y * T + T * 0.5)
	return room_center(r)


func reach_stairs() -> void:
	sfx.play("stairs")
	if floor_n >= FINAL_FLOOR:
		finish(true)
		return
	state = St.UPGRADE
	choices.clear()
	var pool := UPGRADES.duplicate()
	pool.shuffle()
	for u in pool:
		if choices.size() >= 3:
			break
		if u["id"] == "mend" and hp >= max_hp:
			continue
		choices.append(u)
	choice_sel = 0


func choose_upgrade(i: int) -> void:
	if i < 0 or i >= choices.size():
		return
	var u: Dictionary = choices[i]
	match String(u["id"]):
		"heart":
			max_hp += 1; hp = max_hp
		"whet":
			stats["dmg"] = float(stats["dmg"]) * 1.2
		"pitch":
			torch_max += 30.0
		"wick":
			stats["burn"] = float(stats["burn"]) * 0.8
		"boots":
			stats["speed"] = float(stats["speed"]) * 1.12
		"step":
			stats["dash"] = float(stats["dash"]) * 0.75
		"magnet":
			stats["magnet"] = float(stats["magnet"]) + 34.0
		"spark":
			stats["spark"] = int(stats["spark"]) + 1
		"vamp":
			stats["vamp"] = int(stats["vamp"]) + 1
		"mend":
			hp = mini(max_hp, hp + 3)
	taken.append(String(u["name"]))
	torch = torch_max
	sfx.play("upgrade")
	floor_n += 1
	state = St.PLAY
	build_floor()


func finish(won: bool) -> void:
	score = floor_n * 100 + kills * 10 + gold * 5 + (1500 if won else 0)
	save["runs"] = int(save.get("runs", 0)) + 1
	new_best = score > int(save.get("best", 0))
	if new_best:
		save["best"] = score
	save["deepest"] = maxi(int(save.get("deepest", 0)), floor_n)
	write_save()
	end_t = 0.0
	state = St.WIN if won else St.DEAD
	sfx.play("win" if won else "death", 0.0)
	if not won:
		burst(p_pos, 40, Color(1, 0.5, 0.15), 110.0, 1.2, 3.0, -20.0)
		shake = 8.0


# ---------------------------------------------------------------- input
func _input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		touch_mode = true
		var st := ev as InputEventScreenTouch
		if st.pressed:
			on_tap(st.position, st.index)
		else:
			if st.index == joy_idx:
				joy_idx = -1
				joy_vec = Vector2.ZERO
			if st.index == atk_idx:
				atk_idx = -1
	elif ev is InputEventScreenDrag:
		var sd := ev as InputEventScreenDrag
		if sd.index == joy_idx:
			joy_vec = (sd.position - joy_center).limit_length(34.0) / 34.0
	elif ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				touch_mode = false
				mouse_aim_t = 3.0
				if hit_button(mb.position) != "":
					mouse_block = true
					press_button(hit_button(mb.position))
				else:
					mouse_block = false
					mouse_down = true
					if state != St.PLAY:
						default_tap()
			else:
				mouse_down = false
				mouse_block = false
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and state == St.PLAY:
			want_dash = true
	elif ev is InputEventMouseMotion:
		mouse_aim_t = 3.0
	elif ev is InputEventKey:
		var k := ev as InputEventKey
		if k.pressed and not k.echo:
			on_key(k.physical_keycode)


func on_key(code: int) -> void:
	if code == KEY_M:
		toggle_sound()
		return
	match state:
		St.TITLE:
			if code == KEY_H:
				show_help = not show_help
				sfx.play("click")
			elif code in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_J, KEY_Z]:
				if show_help:
					show_help = false
				new_run()
			elif code == KEY_ESCAPE:
				show_help = false
		St.PLAY:
			if code in [KEY_ESCAPE, KEY_P]:
				state = St.PAUSE
				sfx.play("click")
			elif code in [KEY_SPACE, KEY_SHIFT, KEY_K, KEY_X]:
				want_dash = true
			elif code == KEY_TAB:
				show_map = not show_map
		St.PAUSE:
			if code in [KEY_ESCAPE, KEY_P, KEY_ENTER]:
				state = St.PLAY
			elif code == KEY_R:
				new_run()
			elif code == KEY_Q:
				state = St.TITLE
		St.UPGRADE:
			if code in [KEY_1, KEY_KP_1]: choose_upgrade(0)
			elif code in [KEY_2, KEY_KP_2]: choose_upgrade(1)
			elif code in [KEY_3, KEY_KP_3]: choose_upgrade(2)
			elif code in [KEY_LEFT, KEY_A]: choice_sel = maxi(0, choice_sel - 1)
			elif code in [KEY_RIGHT, KEY_D]: choice_sel = mini(choices.size() - 1, choice_sel + 1)
			elif code in [KEY_ENTER, KEY_SPACE, KEY_J]: choose_upgrade(choice_sel)
		St.DEAD, St.WIN:
			if end_t < 0.8:
				return
			if code in [KEY_R, KEY_ENTER, KEY_SPACE]:
				new_run()
			elif code == KEY_ESCAPE:
				state = St.TITLE


func on_tap(pos: Vector2, idx: int) -> void:
	var b := hit_button(pos)
	if b != "":
		press_button(b)
		return
	if state != St.PLAY:
		default_tap()
		return
	var vs := get_viewport_rect().size
	if pos.distance_to(atk_btn_pos()) < 34.0:
		atk_idx = idx
	elif pos.distance_to(dash_btn_pos()) < 26.0:
		want_dash = true
	elif pos.x < vs.x * 0.55:
		joy_idx = idx
		joy_center = pos
		joy_vec = Vector2.ZERO
	else:
		atk_idx = idx


func atk_btn_pos() -> Vector2:
	var vs := get_viewport_rect().size
	return Vector2(vs.x - 50, vs.y - 52)


func dash_btn_pos() -> Vector2:
	var vs := get_viewport_rect().size
	return Vector2(vs.x - 104, vs.y - 30)


func default_tap() -> void:
	match state:
		St.TITLE:
			if show_help:
				show_help = false
			else:
				new_run()
		St.DEAD, St.WIN:
			if end_t > 0.8:
				new_run()


func hit_button(pos: Vector2) -> String:
	for b in buttons:
		var r: Rect2 = b["rect"]
		if r.has_point(pos):
			return String(b["id"])
	return ""


func press_button(id: String) -> void:
	sfx.play("click")
	match id:
		"start": new_run()
		"help": show_help = not show_help
		"sound": toggle_sound()
		"pause": state = St.PAUSE
		"resume": state = St.PLAY
		"restart": new_run()
		"title": state = St.TITLE; show_help = false
		"map": show_map = not show_map
		"up0": choose_upgrade(0)
		"up1": choose_upgrade(1)
		"up2": choose_upgrade(2)


func input_vector() -> Vector2:
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): v.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): v.x += 1
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): v.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): v.y += 1
	if v != Vector2.ZERO:
		return v.normalized()
	if joy_idx >= 0 and joy_vec.length() > 0.15:
		return joy_vec
	return Vector2.ZERO


func wants_attack() -> bool:
	if Input.is_physical_key_pressed(KEY_J) or Input.is_physical_key_pressed(KEY_Z):
		return true
	if mouse_down and not mouse_block:
		return true
	return atk_idx >= 0


# ---------------------------------------------------------------- loop
func _process(delta: float) -> void:
	var dt := minf(delta, 1.0 / 30.0)
	time += dt
	# portrait phones get a taller base resolution so pixels stay big
	var win := get_window()
	var want := Vector2i(360, 480) if win.size.y > win.size.x * 1.1 else Vector2i(480, 270)
	if win.content_scale_size != want:
		win.content_scale_size = want
		cam.zoom = Vector2(1.6, 1.6) if want.y > want.x else Vector2(1.3, 1.3)
	if smoke:
		smoke_step(dt)
	elif demo and state == St.PLAY:
		demo_step()
	if not shot_times.is_empty() and time >= float(shot_times[0]):
		shot_times.pop_front()
		capture_shot()
	if state == St.PLAY:
		if hitstop > 0.0:
			hitstop -= dt
		else:
			run_time += dt
			update_player(dt)
			for e in enemies:
				update_enemy(e, dt)
			separate()
			update_projs(dt)
			update_picks(dt)
			enemies.assign(enemies.filter(func(e: Enemy) -> bool: return not e.dead))
			projs.assign(projs.filter(func(p: Proj) -> bool: return not p.dead))
			picks.assign(picks.filter(func(p: Pick) -> bool: return not p.dead))
			if win_pending > 0.0:
				win_pending -= dt
				if win_pending <= 0.0:
					finish(true)
	if state in [St.DEAD, St.WIN]:
		end_t += dt
	if state != St.TITLE and state != St.PAUSE:
		update_parts(dt)
	if state != St.TITLE:
		compute_light()
		cam.position = p_pos
		shake = maxf(0.0, shake - dt * 18.0)
		cam.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake
	fade = maxf(0.0, fade - dt * 1.8)
	hurt_t = maxf(0.0, hurt_t - dt)
	banner_t = maxf(0.0, banner_t - dt)
	mouse_aim_t = maxf(0.0, mouse_aim_t - dt)
	queue_redraw()
	hud.queue_redraw()


func light_radius() -> float:
	return 26.0 + torch * 0.78 + sin(time * 11.0) * 1.5 + sin(time * 23.0) * 1.0


func update_player(dt: float) -> void:
	var mv := input_vector()
	atk_cd -= dt
	dash_cd -= dt
	inv_t -= dt
	swing_t -= dt
	swap_cd -= dt
	if dash_t > 0.0:
		dash_t -= dt
		p_pos = move_circle(p_pos, dash_dir * 270.0 * dt, P_R)
		if rng.randf() < 0.8:
			spawn_part(p_pos + Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3)), Vector2.ZERO, Color(1, 0.55, 0.2, 0.8), 0.3, 3.0, 0.0)
	else:
		var spd := 74.0 * float(stats["speed"])
		p_vel = p_vel.lerp(mv * spd, minf(1.0, dt * 14.0))
		p_pos = move_circle(p_pos, (p_vel + p_kb) * dt, P_R)
	p_kb = p_kb.move_toward(Vector2.ZERO, 700.0 * dt)
	if mv.length() > 0.1:
		p_face = mv.normalized()
		walk_t += dt
	# aim: mouse on desktop, auto-aim nearest foe on touch, else facing
	aim = p_face
	if not touch_mode and mouse_aim_t > 0.0:
		var m := get_global_mouse_position() - p_pos
		if m.length() > 2.0:
			aim = m.normalized()
	else:
		var best: Enemy = null
		var bd := 90.0
		for e in enemies:
			var d := e.pos.distance_to(p_pos)
			if d < bd and light_px(e.pos) > 0.05:
				bd = d
				best = e
		if best != null:
			aim = (best.pos - p_pos).normalized()
	# torch
	torch -= 1.35 * float(stats["burn"]) * dt
	if torch <= 0.0:
		torch = 0.0
		dark_t += dt
		if dark_t > 2.2:
			dark_t = 0.0
			hurt(1, Vector2.ZERO)
			popup(p_pos + Vector2(0, -12), "the dark bites", Color(0.6, 0.6, 1.0))
	else:
		dark_t = 0.0
	if wants_attack() and atk_cd <= 0.0:
		do_attack()
	if want_dash:
		want_dash = false
		if dash_cd <= 0.0:
			dash_t = 0.17
			dash_cd = 0.8 * float(stats["dash"])
			dash_dir = mv if mv.length() > 0.1 else p_face
			sfx.play("dash")
	# braziers
	for b in braziers:
		if not b["lit"] and (b["pos"] as Vector2).distance_to(p_pos) < 22.0:
			b["lit"] = true
			torch = torch_max
			sfx.play("brazier")
			burst(b["pos"], 26, Color(1, 0.6, 0.2), 70.0, 0.9, 2.5, -60.0)
			popup(b["pos"] + Vector2(0, -14), "torch rekindled", Color(1, 0.8, 0.4))
	if stairs_open and p_pos.distance_to(stairs) < 10.0 and win_pending < 0.0:
		reach_stairs()


func do_attack() -> void:
	var w: Dictionary = WEAPONS[weapon]
	atk_cd = float(w["cd"])
	swing_t = 0.16
	swing_dir = aim
	var dmg := float(w["dmg"]) * float(stats["dmg"])
	if weapon == "wand":
		sfx.play("shoot")
		shoot(p_pos + aim * 6.0, aim * 220.0, dmg, true, Color(1.0, 0.45, 0.9), 3.0)
		torch = maxf(0.0, torch - 0.5)
	else:
		sfx.play("swing")
		var rng_len := float(w["range"])
		var arc := float(w["arc"])
		for e in enemies:
			var to := e.pos - p_pos
			var dist := to.length()
			if dist > rng_len + e.r:
				continue
			var ang := rad_to_deg(absf(aim.angle_to(to)))
			if dist < e.r + 5.0 or ang <= arc * 0.5:
				damage_enemy(e, dmg, to.normalized() * float(w["kb"]))
	for i in int(stats["spark"]):
		shoot(p_pos + aim * 4.0, aim.rotated(rng.randf_range(-0.25, 0.25)) * 180.0, 1.0 * float(stats["dmg"]), true, Color(1, 0.7, 0.25), 2.0)


func shoot(pos: Vector2, vel: Vector2, dmg: float, mine: bool, col: Color, r: float) -> void:
	var p := Proj.new()
	p.pos = pos
	p.vel = vel
	p.dmg = dmg
	p.mine = mine
	p.col = col
	p.r = r
	p.life = 1.4 if mine else 4.0
	projs.append(p)


func hurt(d: int, dir: Vector2) -> void:
	if inv_t > 0.0 or dash_t > 0.0 or state != St.PLAY:
		return
	hp -= d
	inv_t = 0.9
	hurt_t = 0.45
	p_kb = dir * 160.0
	shake = 5.0
	hitstop = 0.06
	sfx.play("hurt")
	burst(p_pos, 12, Color(0.9, 0.15, 0.15), 70.0, 0.5, 2.0, 0.0)
	popup(p_pos + Vector2(0, -10), "-%d" % d, Color(1, 0.3, 0.3))
	if hp <= 0:
		hp = 0
		finish(false)


func damage_enemy(e: Enemy, d: float, kbv: Vector2) -> void:
	if e.dead:
		return
	e.hp -= d
	e.flash = 0.12
	e.active = true
	if e.kind != "boss":
		e.kb += kbv
	else:
		e.kb += kbv * 0.15
	hitstop = maxf(hitstop, 0.025)
	shake = maxf(shake, 2.0)
	sfx.play("hit")
	burst(e.pos, 6, enemy_color(e), 60.0, 0.35, 2.0, 0.0)
	popup(e.pos + Vector2(0, -e.r - 4), str(snappedf(d, 0.1)).trim_suffix(".0"), Color(1, 0.9, 0.5))
	if e.hp <= 0.0:
		kill_enemy(e)


func kill_enemy(e: Enemy) -> void:
	e.dead = true
	kills += 1
	sfx.play("kill")
	burst(e.pos, 18, enemy_color(e), 90.0, 0.7, 2.5, 30.0)
	shake = maxf(shake, 3.5)
	if int(stats["vamp"]) > 0 and kills % maxi(1, 7 - int(stats["vamp"])) == 0 and hp < max_hp:
		hp += 1
		popup(p_pos + Vector2(0, -12), "+1 HP", Color(1, 0.4, 0.4))
	if e.kind == "ooze" and not e.small:
		for i in 2:
			var s := make_enemy("ooze", e.pos + Vector2(rng.randf_range(-5, 5), rng.randf_range(-5, 5)))
			s.small = true
			s.r = 4.0
			s.hp = 2.0
			s.maxhp = 2.0
			s.active = true
			s.cd = 0.4
	if e.kind == "boss":
		boss = null
		stairs_open = true
		shake = 12.0
		sfx.play("boss", 0.0)
		burst(e.pos, 80, Color(1, 0.5, 0.1), 160.0, 1.6, 3.5, -30.0)
		banner = "THE FLAME YIELDS"
		banner_t = 3.0
		for i in 6:
			add_pick("ember", e.pos + Vector2.from_angle(i * TAU / 6.0) * 22.0)
		add_pick("heart", e.pos + Vector2(0, 26))
		var gp := add_pick("gold", e.pos + Vector2(0, -26))
		gp.amount = 25
		if floor_n >= FINAL_FLOOR:
			win_pending = 2.2
		return
	var roll := rng.randf()
	if roll < 0.32:
		add_pick("ember", e.pos)
	elif roll < 0.62:
		var gp := add_pick("gold", e.pos)
		gp.amount = rng.randi_range(1, 2)
	elif roll < 0.67:
		add_pick("heart", e.pos)


func enemy_color(e: Enemy) -> Color:
	match e.kind:
		"skitter": return Color(0.55, 0.42, 0.3)
		"ooze": return Color(1.0, 0.45, 0.15)
		"knight": return Color(0.85, 0.83, 0.75)
		"wisp": return Color(0.45, 0.6, 1.0)
		"shade": return Color(0.55, 0.3, 0.8)
		"boss": return Color(1.0, 0.4, 0.1)
	return Color.WHITE


func update_enemy(e: Enemy, dt: float) -> void:
	e.t += dt
	e.flash -= dt
	e.kb = e.kb.move_toward(Vector2.ZERO, 500.0 * dt)
	var to := p_pos - e.pos
	var dist := maxf(to.length(), 0.001)
	var dir := to / dist
	var desired := Vector2.ZERO
	if not e.active:
		if (dist < 125.0 and los_px(e.pos, p_pos)) or (e.kind == "boss" and dist < 190.0):
			e.active = true
			popup(e.pos + Vector2(0, -e.r - 6), "!", Color(1, 0.3, 0.2))
			if e.kind == "boss":
				sfx.play("boss", 0.0)
				shake = 6.0
	else:
		match e.kind:
			"skitter":
				e.cd -= dt
				if e.cd <= 0.0:
					e.cd = rng.randf_range(0.2, 0.45)
					e.aim = dir.rotated(rng.randf_range(-0.9, 0.9))
				desired = e.aim * e.spd
			"ooze":
				e.cd -= dt
				if e.cd <= 0.0:
					e.cd = rng.randf_range(0.8, 1.25)
					e.vel = dir * (135.0 if e.small else 115.0)
				e.vel = e.vel.move_toward(Vector2.ZERO, 220.0 * dt)
				desired = e.vel
			"knight":
				if e.mode == 0:
					desired = dir * e.spd
					e.cd -= dt
					if dist < 52.0 and e.cd <= 0.0:
						e.mode = 1
						e.t = 0.0
						e.aim = dir
				elif e.mode == 1:
					if e.t > 0.5:
						e.mode = 2
						e.t = 0.0
				else:
					desired = e.aim * 175.0
					if e.t > 0.26:
						e.mode = 0
						e.cd = 1.4
			"wisp":
				var want := 85.0
				var radial := clampf((dist - want) * 1.5, -e.spd, e.spd)
				desired = dir * radial + dir.orthogonal() * sin(e.t * 1.3 + e.sd) * 26.0
				e.cd -= dt
				if e.cd <= 0.0 and dist < 160.0 and los_px(e.pos, p_pos):
					e.cd = 1.7
					shoot(e.pos, dir * 78.0, 1.0, false, Color(0.5, 0.65, 1.0), 3.0)
					sfx.play("eshoot")
			"shade":
				if e.mode == 0:
					desired = dir * e.spd * 0.6
					e.cd -= dt
					if e.cd <= 0.0:
						for i in 8:
							var cand := p_pos + Vector2.from_angle(rng.randf() * TAU) * 34.0
							if not hits(cand, e.r) and los_px(cand, p_pos):
								burst(e.pos, 10, Color(0.5, 0.2, 0.8), 50.0, 0.5, 2.0, 0.0)
								e.pos = cand
								burst(e.pos, 10, Color(0.5, 0.2, 0.8), 50.0, 0.5, 2.0, 0.0)
								sfx.play("blink")
								break
						e.mode = 1
						e.t = 0.0
				elif e.mode == 1:
					if e.t > 0.45:
						e.mode = 2
						e.t = 0.0
						e.aim = dir
				else:
					desired = e.aim * 150.0
					if e.t > 0.32:
						e.mode = 0
						e.cd = 2.6
			"boss":
				desired = update_boss(e, dt, dir, dist)
	e.pos = move_circle(e.pos, (desired + e.kb) * dt, e.r * 0.8)
	# contact damage
	if e.active and dist < e.r + P_R:
		var d := e.dmg
		if e.kind == "knight" and e.mode == 2:
			d = 2
		if inv_t <= 0.0 and dash_t <= 0.0:
			if e.kind == "shade":
				torch = maxf(0.0, torch - 18.0)
				popup(p_pos + Vector2(0, -16), "-torch", Color(0.7, 0.5, 1.0))
			hurt(d, dir)


func update_boss(e: Enemy, dt: float, dir: Vector2, dist: float) -> Vector2:
	var rage := e.hp < e.maxhp * 0.5
	var desired := Vector2.ZERO
	e.cd -= dt
	match e.mode:
		0:
			desired = dir * e.spd
			if e.cd <= 0.0:
				e.pattern += 1
				var seq := [1, 2, 3, 4]
				if rage:
					seq = [1, 2, 4, 1, 3, 2]
				e.mode = seq[e.pattern % seq.size()]
				e.t = 0.0
				e.fired = false
		1:  # ring burst
			if e.t > 0.55 and not e.fired:
				e.fired = true
				var n := 14 + 4 * e.tier + (4 if rage else 0)
				var off := rng.randf() * TAU
				for i in n:
					shoot(e.pos, Vector2.from_angle(off + i * TAU / n) * 70.0, 1.0, false, Color(1, 0.45, 0.1), 3.5)
				sfx.play("eshoot")
				shake = 4.0
			if e.t > 1.1:
				end_boss_move(e, rage)
		2:  # telegraphed charge
			if e.t < 0.65:
				e.aim = dir
			elif e.t < 1.35:
				desired = e.aim * (210.0 if rage else 180.0)
				if rng.randf() < 0.6:
					spawn_part(e.pos, Vector2.ZERO, Color(1, 0.45, 0.1, 0.8), 0.4, 4.0, 0.0)
			else:
				end_boss_move(e, rage)
		3:  # summon skitters
			if e.t > 0.5 and not e.fired:
				e.fired = true
				for i in 2 + e.tier:
					var s := make_enemy("skitter", e.pos + Vector2.from_angle(rng.randf() * TAU) * 20.0)
					s.active = true
				burst(e.pos, 20, Color(0.6, 0.45, 0.3), 80.0, 0.6, 2.0, 0.0)
				sfx.play("blink")
			if e.t > 1.0:
				end_boss_move(e, rage)
		4:  # spiral stream
			desired = dir * 8.0
			e.cd -= dt
			if e.cd <= -0.09:
				e.cd = 0.0
				var arms := 2 + (1 if e.tier > 1 else 0)
				for a in arms:
					shoot(e.pos, Vector2.from_angle(e.t * 3.2 + a * TAU / arms) * 75.0, 1.0, false, Color(1, 0.65, 0.2), 3.0)
			if e.t > 2.2:
				end_boss_move(e, rage)
	return desired


func end_boss_move(e: Enemy, rage: bool) -> void:
	e.mode = 0
	e.cd = 0.9 if rage else 1.5
	e.t = 0.0


func separate() -> void:
	var n := enemies.size()
	for i in n:
		var a := enemies[i]
		if not a.active:
			continue
		for j in range(i + 1, n):
			var b := enemies[j]
			var d := a.pos - b.pos
			var md := a.r + b.r
			var l := d.length()
			if l < md and l > 0.01:
				var push := d / l * (md - l) * 0.5
				if a.kind != "boss":
					a.pos = move_circle(a.pos, push, a.r * 0.8)
				if b.kind != "boss":
					b.pos = move_circle(b.pos, -push, b.r * 0.8)


func update_projs(dt: float) -> void:
	for p in projs:
		p.pos += p.vel * dt
		p.life -= dt
		if p.life <= 0.0:
			p.dead = true
			continue
		if is_wall_px(p.pos):
			p.dead = true
			burst(p.pos, 4, p.col, 40.0, 0.3, 1.5, 0.0)
			continue
		if p.mine:
			for e in enemies:
				if not e.dead and e.pos.distance_to(p.pos) < e.r + p.r:
					damage_enemy(e, p.dmg, p.vel.normalized() * 70.0)
					p.dead = true
					break
		elif p.pos.distance_to(p_pos) < P_R + p.r - 1.0 and inv_t <= 0.0 and dash_t <= 0.0:
			p.dead = true
			hurt(1, p.vel.normalized())


func update_picks(dt: float) -> void:
	var mag := 16.0 + float(stats["magnet"])
	for p in picks:
		p.t += dt
		var d := p.pos.distance_to(p_pos)
		if p.kind in ["ember", "gold", "heart"] and d < mag:
			p.pos = p.pos.move_toward(p_pos, 140.0 * dt)
		if d > 9.0:
			continue
		match p.kind:
			"ember":
				p.dead = true
				torch = minf(torch_max, torch + 30.0)
				sfx.play("ember")
				burst(p.pos, 10, Color(1, 0.6, 0.15), 50.0, 0.5, 2.0, -40.0)
				popup(p.pos + Vector2(0, -8), "+torch", Color(1, 0.7, 0.3))
			"gold":
				p.dead = true
				gold += p.amount
				sfx.play("coin")
				popup(p.pos + Vector2(0, -8), "+%d" % p.amount, Color(1, 0.85, 0.3))
			"heart":
				if hp < max_hp:
					p.dead = true
					hp += 1
					sfx.play("pickup")
					popup(p.pos + Vector2(0, -8), "+1 HP", Color(1, 0.4, 0.4))
			"weapon":
				if swap_cd <= 0.0:
					var old := weapon
					weapon = p.val
					p.val = old
					p.t = 0.0
					swap_cd = 1.2
					sfx.play("pickup")
					popup(p.pos + Vector2(0, -10), String(WEAPONS[weapon]["name"]), Color(0.9, 0.95, 1.0))
			"chest":
				p.kind = "open"
				sfx.play("chest")
				burst(p.pos, 16, Color(1, 0.85, 0.3), 70.0, 0.6, 2.0, 40.0)
				var roll := rng.randf()
				if roll < 0.4:
					var wp := add_pick("weapon", p.pos + Vector2(0, 14))
					wp.val = random_weapon_not(weapon)
				elif roll < 0.7:
					add_pick("heart", p.pos + Vector2(10, 12))
					add_pick("ember", p.pos + Vector2(-10, 12))
				else:
					var gp := add_pick("gold", p.pos + Vector2(0, 14))
					gp.amount = rng.randi_range(6, 12)
				swap_cd = 0.6


func update_parts(dt: float) -> void:
	for p in parts:
		p.life -= dt
		p.pos += p.vel * dt
		p.vel.y += p.grav * dt
		p.vel *= 1.0 - minf(1.0, 2.5 * dt)
	parts.assign(parts.filter(func(p: Part) -> bool: return p.life > 0.0))


func spawn_part(pos: Vector2, vel: Vector2, col: Color, life: float, size: float, grav: float) -> void:
	if parts.size() > 600:
		return
	var p := Part.new()
	p.pos = pos
	p.vel = vel
	p.col = col
	p.life = life
	p.maxl = life
	p.size = size
	p.grav = grav
	parts.append(p)


func burst(pos: Vector2, n: int, col: Color, spd: float, life: float, size: float, grav: float) -> void:
	for i in n:
		var v := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.2, 1.0) * spd
		spawn_part(pos, v, col.lightened(rng.randf_range(0.0, 0.3)), life * rng.randf_range(0.6, 1.0), size, grav)


func popup(pos: Vector2, text: String, col: Color) -> void:
	var p := Part.new()
	p.pos = pos
	p.vel = Vector2(0, -28)
	p.col = col
	p.life = 0.9
	p.maxl = 0.9
	p.text = text
	parts.append(p)


# ---------------------------------------------------------------- grid helpers
func is_wall_px(p: Vector2) -> bool:
	var tx := int(floor(p.x / T))
	var ty := int(floor(p.y / T))
	if tx < 0 or ty < 0 or tx >= MW or ty >= MH:
		return true
	return grid[ty * MW + tx] == 0


func hits(p: Vector2, r: float) -> bool:
	return is_wall_px(p + Vector2(-r, -r)) or is_wall_px(p + Vector2(r, -r)) \
		or is_wall_px(p + Vector2(-r, r)) or is_wall_px(p + Vector2(r, r))


func move_circle(p: Vector2, v: Vector2, r: float) -> Vector2:
	var np := p
	var tx := np + Vector2(v.x, 0)
	if not hits(tx, r):
		np = tx
	var ty := np + Vector2(0, v.y)
	if not hits(ty, r):
		np = ty
	return np


func los_tile(x0: int, y0: int, x1: int, y1: int) -> bool:
	var dx := absi(x1 - x0)
	var dy := -absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy
	var x := x0
	var y := y0
	for guard in 200:
		if x == x1 and y == y1:
			return true
		if (x != x0 or y != y0) and grid[y * MW + x] == 0:
			return false
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x += sx
		if e2 <= dx:
			err += dx
			y += sy
	return true


func los_px(a: Vector2, b: Vector2) -> bool:
	return los_tile(int(a.x / T), int(a.y / T), int(b.x / T), int(b.y / T))


func light_px(p: Vector2) -> float:
	var tx := int(p.x / T)
	var ty := int(p.y / T)
	if tx < 0 or ty < 0 or tx >= MW or ty >= MH:
		return 0.0
	return lightmap[ty * MW + tx]


func compute_light() -> void:
	for i in lit_idx:
		lightmap[i] = 0.0
	lit_idx.clear()
	if grid.size() == 0:
		return
	add_light(p_pos, light_radius())
	for b in braziers:
		if b["lit"] and (b["pos"] as Vector2).distance_to(p_pos) < 420.0:
			add_light(b["pos"], 92.0 + sin(time * 9.0 + (b["pos"] as Vector2).x) * 3.0)
	for p in projs:
		if p.pos.distance_to(p_pos) < 260.0:
			add_light(p.pos, 22.0)


func add_light(src: Vector2, r: float) -> void:
	var stx := int(src.x / T)
	var sty := int(src.y / T)
	var rt := int(ceil(r / T))
	for ty in range(maxi(0, sty - rt), mini(MH, sty + rt + 1)):
		for tx in range(maxi(0, stx - rt), mini(MW, stx + rt + 1)):
			var c := Vector2(tx * T + T * 0.5, ty * T + T * 0.5)
			var d := c.distance_to(src)
			if d > r:
				continue
			var b := clampf((1.0 - d / r) * 1.9, 0.0, 1.0)
			var i := ty * MW + tx
			if b <= lightmap[i]:
				continue
			if not los_tile(stx, sty, tx, ty):
				continue
			if lightmap[i] == 0.0:
				lit_idx.append(i)
			lightmap[i] = b
			seen[i] = 1


func hash2(x: int, y: int) -> int:
	var h := (x * 374761393 + y * 668265263 + floor_n * 2246822519) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return h


# ---------------------------------------------------------------- dev capture
func capture_shot() -> void:
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		return
	if img.get_width() > 900:
		img.resize(900, int(img.get_height() * 900.0 / img.get_width()), Image.INTERPOLATE_BILINEAR)
	var b64 := Marshalls.raw_to_base64(img.save_jpg_to_buffer(0.7))
	JavaScriptBridge.eval("(window.__shots=window.__shots||[]).push('data:image/jpeg;base64,%s')" % b64)


# ---------------------------------------------------------------- demo pilot
func demo_step() -> void:
	touch_mode = true
	var best := 1e9
	var target := p_pos
	for e in enemies:
		var d := e.pos.distance_to(p_pos)
		if d < best:
			best = d
			target = e.pos
	joy_idx = 0
	joy_vec = (target - p_pos).normalized() if best > 26.0 and best < 1e8 else Vector2.ZERO
	atk_idx = 0 if best < 48.0 else -1
	hp = maxi(hp, 2)


# ---------------------------------------------------------------- smoke bot
func smoke_step(dt: float) -> void:
	smoke_t += dt
	match state:
		St.TITLE:
			if smoke_t > 0.3:
				print("[smoke] new run")
				new_run()
				smoke_t = 0.0
		St.PLAY:
			atk_idx = 0
			touch_mode = true
			var target := stairs
			var best := 1e9
			for e in enemies:
				var d := e.pos.distance_to(p_pos)
				if d < best:
					best = d
					target = e.pos
			joy_idx = 0
			joy_vec = (target - p_pos).normalized()
			if int(smoke_t * 3.0) % 4 == 0:
				want_dash = true
			if boss != null and smoke_t > 3.0:
				damage_enemy(boss, 8.0, Vector2.ZERO)
			if smoke_t > 4.0 and boss == null:
				hp = max_hp
				if floor_n == 7 and smoke_phase == 0:
					smoke_phase = 1
					print("[smoke] forcing death on floor 7")
					inv_t = 0.0
					dash_t = 0.0
					hp = 1
					hurt(1, Vector2.RIGHT)
					smoke_t = 0.0
					return
				if stairs_open:
					p_pos = stairs
				smoke_t = 0.0
		St.UPGRADE:
			print("[smoke] floor %d cleared, choosing upgrade" % floor_n)
			choose_upgrade(rng.randi_range(0, choices.size() - 1))
			smoke_t = 0.0
		St.DEAD:
			if smoke_t > 1.5:
				print("[smoke] died: floor=%d kills=%d score=%d" % [floor_n, kills, score])
				new_run()
				smoke_t = 0.0
		St.WIN:
			if smoke_t > 1.5:
				print("[smoke] WIN floor=%d kills=%d score=%d" % [floor_n, kills, score])
				print("SMOKE OK")
				get_tree().quit()
	if smoke_phase == 1 and state == St.PLAY and floor_n == 1:
		smoke_phase = 2
		print("[smoke] restarted after death")
	if smoke_phase == 2 and state == St.PLAY and floor_n == 7:
		# second time through: allow win path
		smoke_phase = 3


# ---------------------------------------------------------------- world drawing
func sh(c: Color, b: float, tint: Color) -> Color:
	return Color(c.r * b * tint.r, c.g * b * tint.g, c.b * b * tint.b, c.a)


func _draw() -> void:
	if state == St.TITLE or grid.size() == 0:
		return
	var vs := get_viewport_rect().size
	var cpos := cam.get_screen_center_position()
	var x0 := maxi(0, int((cpos.x - vs.x * 0.5) / T) - 1)
	var y0 := maxi(0, int((cpos.y - vs.y * 0.5) / T) - 1)
	var x1 := mini(MW - 1, int((cpos.x + vs.x * 0.5) / T) + 1)
	var y1 := mini(MH - 1, int((cpos.y + vs.y * 0.5) / T) + 2)
	var warm := Color(1.0, 0.84, 0.62)
	var cold := Color(0.55, 0.6, 0.85)
	for ty in range(y0, y1 + 1):
		for tx in range(x0, x1 + 1):
			var i := ty * MW + tx
			if seen[i] == 0:
				continue
			var lb := lightmap[i]
			var b := maxf(lb, 0.16)
			var tint := cold.lerp(warm, clampf(lb * 2.5, 0.0, 1.0))
			draw_tile(tx, ty, i, b, tint)
	# stairs
	if stairs_open and seen_px(stairs):
		var sb := maxf(light_px(stairs), 0.25)
		var sr := Rect2(stairs - Vector2(8, 8), Vector2(16, 16))
		draw_rect(sr, Color(0.02, 0.01, 0.02))
		for k in 4:
			draw_rect(Rect2(stairs.x - 7 + k, stairs.y - 6 + k * 3, 14 - k * 2, 2), sh(Color(0.5, 0.42, 0.38), sb * (1.0 - k * 0.2), warm))
		var pulse := 0.5 + 0.5 * sin(time * 4.0)
		draw_rect(sr.grow(1.0 + pulse), Color(1, 0.7, 0.3, 0.35 * sb), false, 1.0)
	# braziers
	for bz in braziers:
		var bp: Vector2 = bz["pos"]
		if not seen_px(bp):
			continue
		var bb := maxf(light_px(bp), 0.2)
		draw_rect(Rect2(bp.x - 5, bp.y - 1, 10, 4), sh(Color(0.45, 0.4, 0.38), bb, warm))
		draw_rect(Rect2(bp.x - 2, bp.y + 3, 4, 4), sh(Color(0.3, 0.27, 0.26), bb, warm))
		if bz["lit"]:
			draw_flame(bp + Vector2(0, -2), 1.3, bp.x)
		else:
			draw_rect(Rect2(bp.x - 4, bp.y - 2, 8, 1), Color(0.15, 0.12, 0.1))
	# pickups
	for p in picks:
		if not seen_px(p.pos):
			continue
		draw_pick(p)
	# enemies
	for e in enemies:
		var lb := light_px(e.pos)
		if lb < 0.05 and not (e.kind == "boss" and e.active):
			continue
		draw_enemy(e, maxf(lb, 0.45))
	# player
	draw_player()
	# projectiles
	for p in projs:
		draw_circle(p.pos, p.r + 2.0, Color(p.col, 0.25))
		draw_circle(p.pos, p.r, p.col)
		draw_circle(p.pos, p.r * 0.45, Color(1, 1, 0.9))
	# particles
	for p in parts:
		var a := clampf(p.life / p.maxl, 0.0, 1.0)
		if p.text != "":
			draw_string_outline(font, p.pos - Vector2(30, 0), p.text, HORIZONTAL_ALIGNMENT_CENTER, 60, 8, 2, Color(0, 0, 0, a))
			draw_string(font, p.pos - Vector2(30, 0), p.text, HORIZONTAL_ALIGNMENT_CENTER, 60, 8, Color(p.col, a))
		else:
			var s := p.size * (0.4 + 0.6 * a)
			draw_rect(Rect2(p.pos - Vector2(s, s) * 0.5, Vector2(s, s)), Color(p.col, p.col.a * a))


func seen_px(p: Vector2) -> bool:
	var tx := int(p.x / T)
	var ty := int(p.y / T)
	if tx < 0 or ty < 0 or tx >= MW or ty >= MH:
		return false
	return seen[ty * MW + tx] == 1


func draw_tile(tx: int, ty: int, i: int, b: float, tint: Color) -> void:
	var x := float(tx * T)
	var y := float(ty * T)
	var h := hash2(tx, ty)
	if grid[i] == 1:
		var v := float(h % 7) * 0.012
		var base := Color(0.25 + v, 0.21 + v, 0.22 + v)
		draw_rect(Rect2(x, y, T, T), sh(base, b, tint))
		var line := sh(base.darkened(0.35), b, tint)
		if (tx + ty) % 2 == 0:
			draw_rect(Rect2(x, y, T, 1), line)
			draw_rect(Rect2(x, y, 1, T), line)
		else:
			draw_rect(Rect2(x, y + 8, T, 1), line)
			draw_rect(Rect2(x + 8, y, 1, 8), line)
		if h % 9 == 0:
			draw_rect(Rect2(x + 4, y + 5, 3, 1), line)
			draw_rect(Rect2(x + 6, y + 6, 1, 3), line)
		elif h % 17 == 0:
			draw_rect(Rect2(x + 9, y + 10, 2, 2), sh(Color(0.75, 0.72, 0.62), b, tint))
			draw_rect(Rect2(x + 7, y + 11, 6, 1), sh(Color(0.7, 0.68, 0.6), b, tint))
		elif h % 23 == 0:
			draw_rect(Rect2(x + 3, y + 11, 2, 2), sh(Color(0.18, 0.4, 0.22), b, tint))
	else:
		var below_floor := ty + 1 < MH and grid[i + MW] == 1
		if below_floor:
			var brick := Color(0.42, 0.3, 0.27) if h % 5 != 0 else Color(0.38, 0.27, 0.25)
			draw_rect(Rect2(x, y, T, T), sh(brick, b, tint))
			var mortar := sh(Color(0.17, 0.12, 0.12), b, tint)
			for row in 3:
				var ry := y + 4 + row * 5
				draw_rect(Rect2(x, ry, T, 1), mortar)
				var off := 4 if row % 2 == 0 else 10
				draw_rect(Rect2(x + off, ry - 4, 1, 4), mortar)
			draw_rect(Rect2(x, y, T, 2), sh(Color(0.55, 0.42, 0.36), b, tint))
			draw_rect(Rect2(x, y + T - 2, T, 2), sh(Color(0.12, 0.08, 0.08), b, tint))
		else:
			draw_rect(Rect2(x, y, T, T), sh(Color(0.13, 0.1, 0.12), b, tint))
			var edge := sh(Color(0.3, 0.23, 0.22), b, tint)
			if tx > 0 and grid[i - 1] == 1:
				draw_rect(Rect2(x, y, 2, T), edge)
			if tx < MW - 1 and grid[i + 1] == 1:
				draw_rect(Rect2(x + T - 2, y, 2, T), edge)
			if ty > 0 and grid[i - MW] == 1:
				draw_rect(Rect2(x, y, T, 2), edge)


func draw_flame(p: Vector2, s: float, sd: float, ci: CanvasItem = null) -> void:
	if ci == null:
		ci = self
	var f := sin(time * 18.0 + sd) * 0.6 + sin(time * 31.0 + sd * 2.0) * 0.4
	ci.draw_circle(p + Vector2(0, -3) * s, 6.0 * s, Color(1, 0.5, 0.1, 0.18))
	ci.draw_circle(p + Vector2(f * 0.5, -2) * s, 2.6 * s, Color(1, 0.35, 0.08))
	ci.draw_circle(p + Vector2(f * 0.8, -3.5) * s, 1.8 * s, Color(1, 0.7, 0.2))
	ci.draw_circle(p + Vector2(f, -5) * s, 1.0 * s, Color(1, 0.95, 0.6))


func draw_player() -> void:
	var p := p_pos.round()
	if state == St.DEAD:
		draw_rect(Rect2(p.x - 5, p.y + 1, 10, 4), Color(0.35, 0.08, 0.1))
		return
	if inv_t > 0.0 and int(inv_t * 20.0) % 2 == 0:
		return
	var bob := 0.0
	if p_vel.length() > 10.0:
		bob = absf(sin(walk_t * 12.0)) * -1.5
	var flip := -1.0 if aim.x < 0 else 1.0
	# shadow
	draw_rect(Rect2(p.x - 4, p.y + 4, 8, 2), Color(0, 0, 0, 0.4))
	var y := p.y + bob
	# cloak
	var cloak := Color(0.55, 0.13, 0.16)
	if dash_t > 0.0:
		cloak = Color(1, 0.6, 0.3)
	draw_rect(Rect2(p.x - 4, y - 3, 8, 8), cloak)
	draw_rect(Rect2(p.x - 4, y + 3, 8, 2), cloak.darkened(0.3))
	# hood + face
	draw_rect(Rect2(p.x - 3, y - 8, 6, 6), Color(0.42, 0.1, 0.13))
	draw_rect(Rect2(p.x - 2 + flip, y - 6, 4, 3), Color(0.95, 0.78, 0.62))
	draw_rect(Rect2(p.x + flip * 1.0, y - 5, 1, 1), Color(0.1, 0.05, 0.05))
	# feet
	var step := sin(walk_t * 12.0) * 1.5 if p_vel.length() > 10.0 else 0.0
	draw_rect(Rect2(p.x - 3 + step, y + 5, 2, 1), Color(0.2, 0.15, 0.12))
	draw_rect(Rect2(p.x + 1 - step, y + 5, 2, 1), Color(0.2, 0.15, 0.12))
	# torch in off hand
	var th := p + Vector2(-5.0 * flip, bob - 2.0)
	draw_rect(Rect2(th.x - 0.5, th.y - 1, 1.5, 6), Color(0.45, 0.3, 0.18))
	if torch > 0.0:
		draw_flame(th + Vector2(0, -1), 0.6 + 0.5 * torch / maxf(torch_max, 1.0), 0.0)
	# weapon
	var w: Dictionary = WEAPONS[weapon]
	var a := aim.angle()
	if swing_t > 0.0:
		var k := 1.0 - swing_t / 0.16
		var arc := deg_to_rad(float(w["arc"]))
		var rng_len := float(w["range"])
		var col: Color = w["col"]
		if weapon == "spear":
			var reach := lerpf(6.0, rng_len, sin(k * PI))
			draw_weapon(self, p + aim * (reach - 14.0), weapon, a, 1.0, Color.WHITE)
		elif weapon == "wand":
			draw_weapon(self, p + aim * 4.0, weapon, a, 1.0, Color.WHITE)
		else:
			var cur := a - arc * 0.5 + arc * k
			draw_arc(p, rng_len * 0.8, a - arc * 0.5, cur, 12, Color(col, 0.55 * (1.0 - k)), 3.0)
			draw_weapon(self, p + Vector2.from_angle(cur) * 3.0, weapon, cur, 1.0, Color.WHITE)
	else:
		draw_weapon(self, p + Vector2(4.0 * flip, bob), weapon, -PI * 0.35 if flip > 0 else -PI * 0.65, 0.8, Color.WHITE)


func draw_weapon(ci: CanvasItem, pos: Vector2, kind: String, ang: float, s: float, mod: Color) -> void:
	ci.draw_set_transform(pos, ang, Vector2(s, s))
	match kind:
		"sword":
			ci.draw_rect(Rect2(-2, -1, 4, 2), Color(0.45, 0.28, 0.16) * mod)
			ci.draw_rect(Rect2(2, -3, 2, 6), Color(0.95, 0.75, 0.3) * mod)
			ci.draw_rect(Rect2(4, -1, 11, 2), Color(0.85, 0.9, 1.0) * mod)
			ci.draw_rect(Rect2(4, -1, 11, 1), Color(1, 1, 1) * mod)
			ci.draw_rect(Rect2(15, -0.5, 2, 1), Color(0.85, 0.9, 1.0) * mod)
		"axe":
			ci.draw_rect(Rect2(-3, -1, 16, 2), Color(0.5, 0.32, 0.18) * mod)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(9, -1), Vector2(15, -7), Vector2(17, -3), Vector2(17, 3), Vector2(15, 6), Vector2(9, 1)]), Color(0.75, 0.75, 0.8) * mod)
			ci.draw_rect(Rect2(15, -5, 2, 9), Color(1, 0.65, 0.45) * mod)
		"spear":
			ci.draw_rect(Rect2(-4, -0.75, 22, 1.5), Color(0.8, 0.72, 0.55) * mod)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(17, -3), Vector2(25, 0), Vector2(17, 3)]), Color(0.95, 0.92, 0.8) * mod)
			ci.draw_rect(Rect2(15, -1.5, 2, 3), Color(0.6, 0.2, 0.2) * mod)
		"wand":
			ci.draw_rect(Rect2(-2, -1, 12, 2), Color(0.35, 0.16, 0.35) * mod)
			ci.draw_circle(Vector2(12, 0), 4.0, Color(1, 0.4, 0.9, 0.25))
			ci.draw_circle(Vector2(12, 0), 2.5, Color(1, 0.5, 0.9) * mod)
			ci.draw_circle(Vector2(12, -0.5), 1.0, Color(1, 1, 1) * mod)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func draw_pick(p: Pick) -> void:
	var bob := sin(p.t * 3.0) * 1.5
	var pos := p.pos + Vector2(0, bob)
	match p.kind:
		"ember":
			var pulse := 0.7 + 0.3 * sin(p.t * 6.0)
			draw_circle(pos, 7.0, Color(1, 0.45, 0.1, 0.18 * pulse))
			draw_colored_polygon(PackedVector2Array([pos + Vector2(0, -4), pos + Vector2(3, 0), pos + Vector2(0, 4), pos + Vector2(-3, 0)]), Color(1, 0.5 * pulse + 0.2, 0.1))
			draw_rect(Rect2(pos.x - 1, pos.y - 1, 2, 2), Color(1, 0.95, 0.6))
		"gold":
			var w := 1.0 + absf(sin(p.t * 4.0)) * 3.0
			draw_rect(Rect2(pos.x - w * 0.5, pos.y - 3, w, 6), Color(1, 0.8, 0.25))
			draw_rect(Rect2(pos.x - w * 0.5, pos.y - 3, maxf(1.0, w * 0.4), 6), Color(1, 0.95, 0.6))
		"heart":
			draw_heart(self, pos, 1.0, Color(0.95, 0.2, 0.25))
		"weapon":
			draw_circle(pos, 9.0, Color(1, 1, 1, 0.06 + 0.05 * sin(p.t * 4.0)))
			draw_weapon(self, pos + Vector2(-7, 4), p.val, -PI * 0.25, 0.9, Color.WHITE)
		"chest", "open":
			var b := maxf(light_px(p.pos), 0.3)
			var wood := Color(0.5, 0.3, 0.15) * b
			wood.a = 1.0
			draw_rect(Rect2(p.pos.x - 7, p.pos.y - 3, 14, 8), wood)
			draw_rect(Rect2(p.pos.x - 7, p.pos.y + 1, 14, 1), Color(0.9, 0.7, 0.25) * b)
			if p.kind == "chest":
				draw_rect(Rect2(p.pos.x - 7, p.pos.y - 7, 14, 4), wood.lightened(0.15))
				draw_rect(Rect2(p.pos.x - 1, p.pos.y - 3, 2, 3), Color(1, 0.85, 0.3) * b)
			else:
				draw_rect(Rect2(p.pos.x - 7, p.pos.y - 9, 14, 2), wood.lightened(0.15))
				draw_rect(Rect2(p.pos.x - 6, p.pos.y - 3, 12, 2), Color(0.08, 0.05, 0.03))


func draw_heart(ci: CanvasItem, pos: Vector2, s: float, col: Color) -> void:
	ci.draw_circle(pos + Vector2(-2, -1) * s, 2.3 * s, col)
	ci.draw_circle(pos + Vector2(2, -1) * s, 2.3 * s, col)
	ci.draw_colored_polygon(PackedVector2Array([pos + Vector2(-4.2, -0.3) * s, pos + Vector2(4.2, -0.3) * s, pos + Vector2(0, 4.5) * s]), col)
	ci.draw_rect(Rect2(pos + Vector2(-2.5, -2.5) * s, Vector2(1, 1) * s), Color(1, 1, 1, 0.7 * col.a))


func draw_enemy(e: Enemy, b: float) -> void:
	var p := e.pos.round()
	var flash := e.flash > 0.0
	var c := enemy_color(e)
	var lit := func(col: Color) -> Color:
		if flash:
			return Color(1, 1, 1, col.a)
		return Color(col.r * b, col.g * b, col.b * b, col.a)
	draw_rect(Rect2(p.x - e.r, p.y + e.r - 1, e.r * 2, 2), Color(0, 0, 0, 0.35))
	match e.kind:
		"skitter":
			var leg := sin(e.t * 30.0) * 1.5
			for s in [-1, 1]:
				draw_line(p + Vector2(-3, 0), p + Vector2(-5, 3 * s + leg * s), lit.call(c.darkened(0.4)), 1.0)
				draw_line(p + Vector2(3, 0), p + Vector2(5, 3 * s - leg * s), lit.call(c.darkened(0.4)), 1.0)
			draw_circle(p, 3.5, lit.call(c))
			draw_circle(p + Vector2(0, -1), 2.0, lit.call(c.lightened(0.2)))
			draw_rect(Rect2(p.x - 2, p.y - 1, 1, 1), Color(1, 0.2, 0.1))
			draw_rect(Rect2(p.x + 1, p.y - 1, 1, 1), Color(1, 0.2, 0.1))
		"ooze":
			var sq := 1.0 + sin(e.t * 9.0) * 0.12 + e.vel.length() * 0.002
			draw_set_transform(p, 0.0, Vector2(sq, 1.0 / sq))
			draw_circle(Vector2.ZERO, e.r, lit.call(c.darkened(0.2)))
			draw_circle(Vector2(0, -1), e.r * 0.8, lit.call(c))
			draw_circle(Vector2(-e.r * 0.35, -e.r * 0.4), e.r * 0.25, Color(1, 0.9, 0.6, 0.8))
			draw_rect(Rect2(-2.5, -1, 1.5, 2), Color(0.1, 0.02, 0))
			draw_rect(Rect2(1, -1, 1.5, 2), Color(0.1, 0.02, 0))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"knight":
			if e.mode == 1:
				var tl := Color(1, 0.2, 0.15, 0.25 + 0.35 * sin(e.t * 40.0))
				draw_line(p, p + e.aim * 46.0, tl, 2.0)
			var bone: Color = lit.call(c)
			draw_rect(Rect2(p.x - 4, p.y - 2, 8, 7), lit.call(Color(0.35, 0.33, 0.38)))
			draw_rect(Rect2(p.x - 1, p.y - 1, 2, 5), bone)
			draw_circle(p + Vector2(0, -6), 3.5, bone)
			draw_rect(Rect2(p.x - 2, p.y - 7, 1, 2), Color(0.9, 0.2, 0.1) if e.active else Color(0.1, 0.1, 0.1))
			draw_rect(Rect2(p.x + 1, p.y - 7, 1, 2), Color(0.9, 0.2, 0.1) if e.active else Color(0.1, 0.1, 0.1))
			draw_rect(Rect2(p.x - 7, p.y - 3, 3, 7), lit.call(Color(0.5, 0.45, 0.4)))
			var sa := e.aim.angle() if e.active else 0.4
			draw_line(p + Vector2(4, 0), p + Vector2(4, 0) + Vector2.from_angle(sa) * 9.0, lit.call(Color(0.8, 0.82, 0.9)), 2.0)
		"wisp":
			var fl := sin(e.t * 8.0 + e.sd) * 1.5
			var pp := p + Vector2(0, fl)
			draw_circle(pp, 7.0, Color(0.4, 0.55, 1.0, 0.15))
			draw_circle(pp + Vector2(sin(e.t * 5.0) * 1.5, 4), 2.5, Color(0.35, 0.5, 1.0, 0.6))
			draw_circle(pp, 4.0, Color(0.45, 0.6, 1.0) if not flash else Color.WHITE)
			draw_circle(pp + Vector2(0, -1), 2.5, Color(0.8, 0.9, 1.0))
			draw_rect(Rect2(pp.x - 2, pp.y - 1, 1, 2), Color(0.05, 0.05, 0.2))
			draw_rect(Rect2(pp.x + 1, pp.y - 1, 1, 2), Color(0.05, 0.05, 0.2))
		"shade":
			var alpha := 0.45 if e.mode == 0 else 0.95
			var body := Color(0.18, 0.08, 0.28, alpha)
			if flash:
				body = Color(1, 1, 1, 0.9)
			var wob := sin(e.t * 6.0) * 1.0
			draw_colored_polygon(PackedVector2Array([p + Vector2(-5, 6), p + Vector2(-4 + wob, -3), p + Vector2(0, -8), p + Vector2(4 - wob, -3), p + Vector2(5, 6), p + Vector2(2, 4), p + Vector2(0, 6), p + Vector2(-2, 4)]), body)
			var eye := Color(1, 0.9, 1.0, alpha)
			if e.mode == 1:
				eye = Color(1, 0.3, 0.9)
			draw_rect(Rect2(p.x - 3, p.y - 4, 2, 1), eye)
			draw_rect(Rect2(p.x + 1, p.y - 4, 2, 1), eye)
		"boss":
			draw_boss(e, p, flash)
	if e.kind != "boss" and e.hp < e.maxhp and e.active:
		var w := e.r * 2.0 + 2.0
		draw_rect(Rect2(p.x - w * 0.5, p.y - e.r - 9, w, 2), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(p.x - w * 0.5, p.y - e.r - 9, w * e.hp / e.maxhp, 2), Color(0.95, 0.3, 0.2))


func draw_boss(e: Enemy, p: Vector2, flash: bool) -> void:
	var king := e.tier > 1
	var body := Color(0.2, 0.12, 0.12) if not king else Color(0.16, 0.14, 0.18)
	if flash:
		body = Color(1, 1, 1)
	var glow := 0.6 + 0.4 * sin(time * 5.0)
	draw_circle(p, 22.0, Color(1, 0.35, 0.05, 0.08 * glow))
	if e.mode == 2 and e.t < 0.65:
		draw_line(p, p + e.aim * 120.0, Color(1, 0.3, 0.1, 0.3 + 0.3 * sin(e.t * 40.0)), 4.0)
	if e.mode == 1 and e.t < 0.55:
		draw_arc(p, 14.0 + e.t * 30.0, 0, TAU, 24, Color(1, 0.5, 0.1, 0.6), 2.0)
	# body
	draw_circle(p, 13.0, body)
	draw_circle(p + Vector2(0, -2), 10.0, body.lightened(0.08))
	# lava cracks
	var lava := Color(1, 0.45 + 0.2 * glow, 0.1)
	draw_line(p + Vector2(-8, 2), p + Vector2(-2, 6), lava, 1.5)
	draw_line(p + Vector2(-2, 6), p + Vector2(4, 3), lava, 1.5)
	draw_line(p + Vector2(4, 3), p + Vector2(9, 7), lava, 1.5)
	draw_line(p + Vector2(0, -12), p + Vector2(1, -6), lava, 1.0)
	# horns / crown
	if king:
		for k in 5:
			var x := -8.0 + k * 4.0
			draw_colored_polygon(PackedVector2Array([p + Vector2(x - 1.5, -10), p + Vector2(x, -17 - (k % 2) * 3), p + Vector2(x + 1.5, -10)]), Color(0.95, 0.75, 0.3))
	else:
		draw_colored_polygon(PackedVector2Array([p + Vector2(-9, -6), p + Vector2(-15, -16), p + Vector2(-5, -10)]), Color(0.3, 0.25, 0.22))
		draw_colored_polygon(PackedVector2Array([p + Vector2(9, -6), p + Vector2(15, -16), p + Vector2(5, -10)]), Color(0.3, 0.25, 0.22))
	# eyes
	var look := (p_pos - p).normalized() * 1.5
	draw_rect(Rect2(p + look + Vector2(-5, -5), Vector2(3, 2)), Color(1, 0.85, 0.3))
	draw_rect(Rect2(p + look + Vector2(2, -5), Vector2(3, 2)), Color(1, 0.85, 0.3))
	# embers rising
	if rng.randf() < 0.3 and state == St.PLAY:
		spawn_part(p + Vector2(rng.randf_range(-10, 10), rng.randf_range(-6, 6)), Vector2(0, -20), Color(1, 0.5, 0.1), 0.8, 2.0, -10.0)
