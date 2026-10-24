extends Node
## Звук без внешних файлов: все эффекты синтезируются при запуске в PCM 16 бит.
## Пулы плееров (2D и 3D) — без аллокаций во время боя.
## Чтобы заменить звук на записанный, положите .wav/.ogg в res://assets/audio/<имя>.*
## — он будет загружен вместо синтеза.

const RATE := 22050
const POOL_2D := 10
const POOL_3D := 14

var _streams: Dictionary = {}
var _p2d: Array[AudioStreamPlayer] = []
var _p3d: Array[AudioStreamPlayer3D] = []
var _i2d := 0
var _i3d := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 211
	_build_all()
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_p2d.append(p)
	for i in POOL_3D:
		var p3 := AudioStreamPlayer3D.new()
		p3.bus = "SFX"
		p3.unit_size = 8.0
		p3.max_distance = 70.0
		p3.attenuation_filter_cutoff_hz = 9000.0
		add_child(p3)
		_p3d.append(p3)


func has_sound(sound: String) -> bool:
	return _streams.has(sound)


func play(sound: String, volume_db: float = 0.0, pitch_var: float = 0.05) -> void:
	var s: AudioStream = _streams.get(sound)
	if s == null:
		return
	var p := _p2d[_i2d]
	_i2d = (_i2d + 1) % _p2d.size()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + _rng.randf_range(-pitch_var, pitch_var)
	p.play()


func play_at(sound: String, pos: Vector3, volume_db: float = 0.0, pitch_var: float = 0.06) -> void:
	var s: AudioStream = _streams.get(sound)
	if s == null:
		return
	var p := _p3d[_i3d]
	_i3d = (_i3d + 1) % _p3d.size()
	p.stream = s
	p.global_position = pos
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + _rng.randf_range(-pitch_var, pitch_var)
	p.play()


## Зацикленный звук, привязанный к узлу-владельцу (освобождается вместе с ним).
func loop_on(owner_node: Node, sound: String, volume_db: float = 0.0, bus: String = "SFX") -> AudioStreamPlayer:
	var s: AudioStream = _streams.get(sound)
	if s == null or owner_node == null:
		return null
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.bus = bus
	p.volume_db = volume_db
	owner_node.add_child(p)
	p.play()
	return p


func stop_all() -> void:
	for p in _p2d:
		p.stop()
	for p3 in _p3d:
		p3.stop()


# ======================================================================
# Синтез
# ======================================================================

func _build_all() -> void:
	_add("shot", _gunshot(0.55, 95.0, 0.55, 1.0))
	_add("shot_enemy", _gunshot(0.5, 80.0, 0.4, 0.85))
	_add("dry", _click(0.035, 2600.0, 0.5))
	_add("reload_out", _concat([_click(0.03, 1500.0, 0.7), _silence(0.05), _click(0.04, 900.0, 0.6)]))
	_add("reload_in", _concat([_click(0.04, 1100.0, 0.8), _silence(0.12), _click(0.05, 1900.0, 0.9)]))
	_add("baton_swing", _whoosh(0.28))
	_add("baton_hit", _thud(0.18, 70.0, 0.9))
	_add("hit_flesh", _thud(0.12, 110.0, 0.7))
	_add("hurt", _thud(0.25, 55.0, 1.0))
	_add("impact", _impact(0.09))
	_add("step", _step(0.08))
	_add("ui_click", _click(0.03, 1800.0, 0.35))
	_add("ui_back", _click(0.03, 1100.0, 0.3))
	_add("alert", _tone_seq([880.0, 1175.0], 0.09, 0.35))
	_add("victory", _tone_seq([523.0, 659.0, 784.0, 1046.0], 0.16, 0.45))
	_add("defeat", _tone_seq([392.0, 330.0, 262.0, 196.0], 0.22, 0.45))
	_add("radio", _radio(1.4))
	_add("siren", _siren(2.4), true)
	_add("hum", _hum(1.0), true)
	_add("rain", _rain(2.0), true)
	_add("car_engine", _engine(1.0), true)
	_add("door", _thud(0.22, 90.0, 0.6))
	# Внешние файлы (если есть) перекрывают синтез.
	for name in _streams.keys():
		for ext in ["ogg", "wav", "mp3"]:
			var path := "res://assets/audio/%s.%s" % [name, ext]
			if ResourceLoader.exists(path):
				var ext_stream := load(path) as AudioStream
				if ext_stream:
					_streams[name] = ext_stream
				break


func _add(sound: String, samples: PackedFloat32Array, loop: bool = false) -> void:
	_streams[sound] = _to_wav(samples, loop)


func _to_wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = samples.size()
	return s


func _buf(dur: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(dur * RATE))
	return b


func _silence(dur: float) -> PackedFloat32Array:
	return _buf(dur)


func _concat(parts: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for p in parts:
		out.append_array(p)
	return out


## Выстрел: щелчок (фильтрованный шум) + «тело» (падающий по частоте синус) + хвост помещения.
func _gunshot(dur: float, thump: float, bright: float, gain: float) -> PackedFloat32Array:
	var out := _buf(dur)
	var lp := 0.0
	var lp2 := 0.0
	var phase := 0.0
	for i in out.size():
		var t := float(i) / RATE
		var n := _rng.randf_range(-1.0, 1.0)
		lp += (n - lp) * bright
		lp2 += (n - lp2) * 0.06
		var crack := lp * exp(-t * 32.0)
		var f := thump * (1.0 + 2.5 * exp(-t * 35.0))
		phase += TAU * f / RATE
		var body := sin(phase) * exp(-t * 14.0) * 0.9
		var tail := lp2 * exp(-t * 5.0) * 0.5
		out[i] = (crack * 0.9 + body + tail) * gain
	return out


func _click(dur: float, freq: float, gain: float) -> PackedFloat32Array:
	var out := _buf(dur)
	for i in out.size():
		var t := float(i) / RATE
		out[i] = (sin(TAU * freq * t) * 0.6 + _rng.randf_range(-1.0, 1.0) * 0.4) * exp(-t * 120.0) * gain
	return out


func _whoosh(dur: float) -> PackedFloat32Array:
	var out := _buf(dur)
	var lp := 0.0
	for i in out.size():
		var t := float(i) / RATE
		var k := t / dur
		var cutoff := 0.03 + 0.25 * sin(PI * k)
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * cutoff
		out[i] = lp * sin(PI * k) * 1.4
	return out


func _thud(dur: float, freq: float, gain: float) -> PackedFloat32Array:
	var out := _buf(dur)
	var lp := 0.0
	var phase := 0.0
	for i in out.size():
		var t := float(i) / RATE
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.15
		phase += TAU * freq * (1.0 + exp(-t * 30.0)) / RATE
		out[i] = (sin(phase) * 0.9 + lp * 0.5) * exp(-t * 22.0) * gain
	return out


func _impact(dur: float) -> PackedFloat32Array:
	var out := _buf(dur)
	var lp := 0.0
	for i in out.size():
		var t := float(i) / RATE
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.5
		out[i] = (lp + sin(TAU * 3100.0 * t) * 0.25) * exp(-t * 55.0) * 0.6
	return out


func _step(dur: float) -> PackedFloat32Array:
	var out := _buf(dur)
	var lp := 0.0
	for i in out.size():
		var t := float(i) / RATE
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.08
		out[i] = lp * exp(-t * 45.0) * 1.6
	return out


func _tone_seq(freqs: Array, note: float, gain: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for f in freqs:
		var b := _buf(note)
		for i in b.size():
			var t := float(i) / RATE
			var env := minf(1.0, t * 80.0) * exp(-t * 4.0)
			b[i] = (sin(TAU * f * t) + 0.3 * sin(TAU * f * 2.0 * t)) * env * gain
		out.append_array(b)
	return out


## Рация диспетчера: полосовой шум + писк в начале и в конце.
func _radio(dur: float) -> PackedFloat32Array:
	var out := _buf(dur)
	var lp := 0.0
	var hp := 0.0
	for i in out.size():
		var t := float(i) / RATE
		var n := _rng.randf_range(-1.0, 1.0)
		lp += (n - lp) * 0.35
		hp = lp - hp * 0.0
		var babble := (sin(TAU * 4.0 * t) * 0.5 + 0.5) * (sin(TAU * 7.3 * t) * 0.5 + 0.5)
		var v := hp * 0.35 * babble
		if t < 0.08 or t > dur - 0.08:
			v += sin(TAU * 1450.0 * t) * 0.35
		out[i] = v
	return out


## Американская «вой»-сирена: частота плавно 650→1350→650 Гц за период (зациклено).
func _siren(dur: float) -> PackedFloat32Array:
	var out := _buf(dur)
	var phase := 0.0
	for i in out.size():
		var t := float(i) / RATE
		var k := 0.5 - 0.5 * cos(TAU * t / dur)
		var f := 650.0 + 700.0 * k
		phase += TAU * f / RATE
		out[i] = (sin(phase) * 0.7 + sin(phase * 2.0) * 0.15) * 0.5
	return out


func _hum(dur: float) -> PackedFloat32Array:
	var out := _buf(dur)
	for i in out.size():
		var t := float(i) / RATE
		out[i] = (sin(TAU * 60.0 * t) * 0.5 + sin(TAU * 120.0 * t) * 0.3 + sin(TAU * 180.0 * t) * 0.1) * 0.12
	return out


func _rain(dur: float) -> PackedFloat32Array:
	var out := _buf(dur)
	var lp := 0.0
	for i in out.size():
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.3
		var drop := 0.0
		if _rng.randf() < 0.002:
			drop = _rng.randf_range(0.2, 0.5)
		out[i] = lp * 0.22 + drop
	# плавная склейка конца с началом, чтобы цикл не щёлкал
	var fade := int(0.05 * RATE)
	for i in fade:
		var k := float(i) / fade
		out[out.size() - fade + i] = lerpf(out[out.size() - fade + i], out[i], k)
	return out


func _engine(dur: float) -> PackedFloat32Array:
	var out := _buf(dur)
	var phase := 0.0
	for i in out.size():
		phase += TAU * 42.0 / RATE
		out[i] = (sin(phase) * 0.5 + sin(phase * 2.0) * 0.25 + sin(phase * 3.0) * 0.12) * 0.35
	return out
