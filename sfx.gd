extends Node
## Ember Crypt — every sound is synthesised at startup into AudioStreamWAV
## buffers (no audio files). WAV samples also work on the single-threaded
## Web export, unlike AudioStreamGenerator.

const RATE := 22050
var enabled := true
var streams := {}
var players: Array[AudioStreamPlayer] = []
var next := 0


func _ready() -> void:
	for i in 10:
		var p := AudioStreamPlayer.new()
		p.volume_db = -6.0
		add_child(p)
		players.append(p)
	#                      dur   f0    f1   wave noise vol
	streams["swing"] = _tone(0.10, 900, 300, 2, 0.85, 0.35)
	streams["hit"] = _tone(0.12, 240, 70, 1, 0.45, 0.55)
	streams["kill"] = _tone(0.22, 420, 60, 1, 0.55, 0.55)
	streams["hurt"] = _tone(0.28, 320, 80, 2, 0.25, 0.6)
	streams["ember"] = _tone(0.16, 620, 1300, 0, 0.0, 0.45)
	streams["coin"] = _tone(0.10, 1300, 1700, 1, 0.0, 0.25)
	streams["pickup"] = _tone(0.18, 440, 990, 3, 0.0, 0.5)
	streams["dash"] = _tone(0.16, 500, 120, 0, 0.9, 0.4)
	streams["shoot"] = _tone(0.12, 900, 260, 0, 0.1, 0.35)
	streams["eshoot"] = _tone(0.16, 300, 520, 3, 0.2, 0.3)
	streams["chest"] = _tone(0.25, 300, 760, 3, 0.1, 0.5)
	streams["stairs"] = _tone(0.55, 220, 880, 3, 0.05, 0.5)
	streams["upgrade"] = _tone(0.35, 520, 1560, 3, 0.0, 0.5)
	streams["brazier"] = _tone(0.45, 160, 90, 2, 0.75, 0.55)
	streams["boss"] = _tone(0.9, 90, 45, 2, 0.35, 0.7)
	streams["death"] = _tone(1.1, 220, 35, 2, 0.4, 0.65)
	streams["win"] = _tone(0.9, 330, 1320, 3, 0.0, 0.55)
	streams["blink"] = _tone(0.2, 1400, 200, 0, 0.5, 0.3)
	streams["click"] = _tone(0.05, 700, 700, 1, 0.0, 0.25)


func play(id: String, pitch_var := 0.08) -> void:
	if not enabled or not streams.has(id):
		return
	var p := players[next]
	next = (next + 1) % players.size()
	p.stream = streams[id]
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()


func _tone(dur: float, f0: float, f1: float, wave: int, noise: float, vol: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var ph := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / float(n)
		var f := lerpf(f0, f1, t)
		ph += f / RATE
		var fr := fmod(ph, 1.0)
		var s := 0.0
		match wave:
			0: s = sin(ph * TAU)
			1: s = 1.0 if fr < 0.5 else -1.0
			2: s = fr * 2.0 - 1.0
			_: s = absf(fr * 4.0 - 2.0) - 1.0
		lp = lerpf(lp, randf() * 2.0 - 1.0, 0.4)
		s = lerpf(s, lp * 1.6, noise)
		var env := (1.0 - t) * (1.0 - t)
		var att := minf(1.0, float(i) / (RATE * 0.004))
		var v := int(clampf(s * env * att * vol, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w
