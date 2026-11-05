extends RefCounted
## Ember Crypt — procedural dungeon generator.
## Rooms are placed by rejection sampling, linked into a spanning tree
## (each room joins its nearest earlier room) plus a few extra loops,
## and carved with 2-tile-wide L-shaped corridors.

static func make(rng: RandomNumberGenerator, w: int, h: int, floor_n: int, boss: bool) -> Dictionary:
	var g := PackedByteArray()
	g.resize(w * h)
	g.fill(0)
	var rooms: Array[Rect2i] = []
	if boss:
		var start := Rect2i(4, h / 2 - 3, 7, 7)
		var arena := Rect2i(w / 2 - 13, h / 2 - 10, 26, 20)
		rooms.append(start)
		rooms.append(arena)
		_carve_room(g, w, start)
		_carve_room(g, w, arena)
		# four pillars to dodge around
		for p in [Vector2i(-6, -4), Vector2i(5, -4), Vector2i(-6, 3), Vector2i(5, 3)]:
			var c: Vector2i = arena.get_center() + p
			g[c.y * w + c.x] = 0
			g[c.y * w + c.x + 1] = 0
			g[(c.y + 1) * w + c.x] = 0
			g[(c.y + 1) * w + c.x + 1] = 0
		_corridor(g, w, h, start.get_center(), arena.get_center())
		return {"grid": g, "rooms": rooms}

	var target := 7 + mini(floor_n, 7)
	var tries := 0
	while rooms.size() < target and tries < 600:
		tries += 1
		var rw := rng.randi_range(6, 13)
		var rh := rng.randi_range(5, 10)
		var r := Rect2i(rng.randi_range(2, w - rw - 3), rng.randi_range(2, h - rh - 3), rw, rh)
		var ok := true
		for o in rooms:
			if r.grow(2).intersects(o):
				ok = false
				break
		if ok:
			rooms.append(r)
	for r in rooms:
		_carve_room(g, w, r)
		# pillars in big rooms for cover
		if r.size.x >= 10 and r.size.y >= 8 and rng.randf() < 0.7:
			var n := rng.randi_range(1, 3)
			for i in n:
				var px := rng.randi_range(r.position.x + 2, r.end.x - 3)
				var py := rng.randi_range(r.position.y + 2, r.end.y - 3)
				g[py * w + px] = 0
	for i in range(1, rooms.size()):
		var best := 0
		var bd := 1e9
		for j in i:
			var d := Vector2(rooms[i].get_center()).distance_to(Vector2(rooms[j].get_center()))
			if d < bd:
				bd = d
				best = j
		_corridor(g, w, h, rooms[i].get_center(), rooms[best].get_center())
	# a couple of loops so the crypt is not a pure tree
	for k in 2:
		var a := rng.randi_range(0, rooms.size() - 1)
		var b := rng.randi_range(0, rooms.size() - 1)
		if a != b:
			_corridor(g, w, h, rooms[a].get_center(), rooms[b].get_center())
	return {"grid": g, "rooms": rooms}


static func _carve_room(g: PackedByteArray, w: int, r: Rect2i) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			g[y * w + x] = 1


static func _corridor(g: PackedByteArray, w: int, h: int, a: Vector2i, b: Vector2i) -> void:
	var x := a.x
	var y := a.y
	var horiz_first := (a.x + a.y) % 2 == 0
	if horiz_first:
		while x != b.x:
			_dig(g, w, h, x, y)
			x += signi(b.x - x)
		while y != b.y:
			_dig(g, w, h, x, y)
			y += signi(b.y - y)
	else:
		while y != b.y:
			_dig(g, w, h, x, y)
			y += signi(b.y - y)
		while x != b.x:
			_dig(g, w, h, x, y)
			x += signi(b.x - x)
	_dig(g, w, h, x, y)


static func _dig(g: PackedByteArray, w: int, h: int, x: int, y: int) -> void:
	for dy in 2:
		for dx in 2:
			var xx := x + dx
			var yy := y + dy
			if xx > 0 and yy > 0 and xx < w - 1 and yy < h - 1:
				g[yy * w + xx] = 1
