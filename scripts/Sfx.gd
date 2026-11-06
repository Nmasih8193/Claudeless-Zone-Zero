class_name Sfx
extends Node
## All sound effects are synthesised at start-up (no audio assets needed) and played through a
## small AudioStreamPlayer pool. The fight music is loaded from res://audio/bgm.mp3.

const RATE := 22050
const POOL := 16
const MUSIC_PATH := "res://audio/bgm.mp3"

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next: int = 0
var _music: AudioStreamPlayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_build_streams()
	_music = AudioStreamPlayer.new()
	_music.volume_db = GameConfig.MUSIC_DB
	add_child(_music)
	var stream: AudioStream = load(MUSIC_PATH) as AudioStream
	if stream == null and FileAccess.file_exists(MUSIC_PATH):
		var mp3 := AudioStreamMP3.new()
		mp3.data = FileAccess.get_file_as_bytes(MUSIC_PATH)
		stream = mp3
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	_music.stream = stream

func play_music() -> void:
	if _music != null and _music.stream != null and not _music.playing:
		_music.play()

func stop_music() -> void:
	if _music != null:
		_music.stop()

func play(sfx_name: String, vol_db: float = 0.0, pitch_var: float = 0.06) -> void:
	var s: AudioStream = _streams.get(sfx_name)
	if s == null:
		return
	var p := _players[_next]
	_next = (_next + 1) % POOL
	p.stream = s
	p.volume_db = vol_db + GameConfig.SFX_DB
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()

# ------------------------------------------------------------------ synthesis
func _blank(dur: float) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(int(dur * float(RATE)))
	return a

## wave: 0 sine, 1 square, 2 saw. Frequency glides f0 -> f1; exponential decay.
func _tone(buf: PackedFloat32Array, t0: float, dur: float, f0: float, f1: float, amp: float, decay: float, wave: int = 0) -> void:
	var n := int(dur * float(RATE))
	var s0 := int(t0 * float(RATE))
	var phase := 0.0
	for i in n:
		var idx := s0 + i
		if idx >= buf.size():
			break
		var t := float(i) / float(RATE)
		var f := lerpf(f0, f1, float(i) / float(n))
		phase += TAU * f / float(RATE)
		var w := sin(phase)
		if wave == 1:
			w = signf(w) * 0.6
		elif wave == 2:
			w = fposmod(phase / TAU, 1.0) * 2.0 - 1.0
		buf[idx] += w * amp * exp(-decay * t) * minf(1.0, t * 300.0)

## lp: 1.0 = white noise, smaller = darker (one-pole low-pass).
func _noise(buf: PackedFloat32Array, t0: float, dur: float, amp: float, decay: float, lp: float = 1.0) -> void:
	var n := int(dur * float(RATE))
	var s0 := int(t0 * float(RATE))
	var y := 0.0
	for i in n:
		var idx := s0 + i
		if idx >= buf.size():
			break
		var t := float(i) / float(RATE)
		y += lp * (randf_range(-1.0, 1.0) - y)
		buf[idx] += y * amp * exp(-decay * t) * minf(1.0, t * 400.0)

func _wav(buf: PackedFloat32Array, gain: float = 0.8) -> AudioStreamWAV:
	var n := buf.size()
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(buf[i] * gain, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w

func _build_streams() -> void:
	var b: PackedFloat32Array
	b = _blank(0.2)
	_noise(b, 0.0, 0.2, 0.6, 14.0, 0.25)
	_tone(b, 0.0, 0.2, 520.0, 180.0, 0.25, 10.0)
	_streams["swing"] = _wav(b)

	b = _blank(0.16)
	_noise(b, 0.0, 0.16, 0.8, 30.0, 0.5)
	_tone(b, 0.0, 0.14, 220.0, 90.0, 0.7, 25.0)
	_streams["hit"] = _wav(b)

	b = _blank(0.35)
	_noise(b, 0.0, 0.3, 0.8, 30.0, 0.5)
	_tone(b, 0.0, 0.3, 220.0, 90.0, 0.6, 25.0)
	_tone(b, 0.0, 0.35, 1400.0, 1800.0, 0.28, 10.0)
	_tone(b, 0.02, 0.3, 2100.0, 2400.0, 0.16, 12.0)
	_streams["crit"] = _wav(b)

	b = _blank(0.4)
	_noise(b, 0.0, 0.35, 0.9, 12.0, 0.35)
	_tone(b, 0.0, 0.4, 140.0, 45.0, 0.9, 8.0)
	_streams["hit_heavy"] = _wav(b)

	b = _blank(0.28)
	_noise(b, 0.0, 0.26, 0.5, 8.0, 0.15)
	_tone(b, 0.0, 0.26, 900.0, 300.0, 0.1, 8.0)
	_streams["dodge"] = _wav(b)

	b = _blank(0.7)
	_tone(b, 0.0, 0.65, 880.0, 880.0, 0.4, 6.0)
	_tone(b, 0.07, 0.6, 1320.0, 1320.0, 0.35, 6.0)
	_tone(b, 0.14, 0.55, 1760.0, 1760.0, 0.25, 6.0)
	_streams["perfect"] = _wav(b)

	b = _blank(0.2)
	_tone(b, 0.0, 0.18, 400.0, 900.0, 0.5, 8.0)
	_noise(b, 0.0, 0.1, 0.2, 20.0)
	_streams["swap"] = _wav(b)

	b = _blank(0.55)
	_tone(b, 0.0, 0.5, 200.0, 900.0, 0.45, 3.0, 2)
	_noise(b, 0.0, 0.5, 0.35, 4.0, 0.2)
	_streams["ex"] = _wav(b)

	b = _blank(1.4)
	_tone(b, 0.0, 0.9, 100.0, 1000.0, 0.4, 1.5, 2)
	_noise(b, 0.0, 0.9, 0.4, 2.0, 0.15)
	_tone(b, 0.85, 0.5, 120.0, 40.0, 0.9, 6.0)
	_noise(b, 0.85, 0.4, 0.8, 8.0, 0.3)
	_streams["ult"] = _wav(b)

	b = _blank(0.6)
	_tone(b, 0.0, 0.55, 600.0, 150.0, 0.5, 5.0, 1)
	_noise(b, 0.0, 0.4, 0.3, 8.0, 0.4)
	_streams["stun"] = _wav(b)

	b = _blank(0.7)
	_tone(b, 0.0, 0.5, 523.0, 523.0, 0.4, 7.0)
	_tone(b, 0.1, 0.5, 659.0, 659.0, 0.4, 7.0)
	_tone(b, 0.2, 0.5, 784.0, 784.0, 0.4, 7.0)
	_tone(b, 0.3, 0.4, 1046.0, 1046.0, 0.45, 6.0)
	_streams["chain"] = _wav(b)

	b = _blank(0.3)
	_tone(b, 0.0, 0.12, 700.0, 700.0, 0.35, 6.0, 1)
	_tone(b, 0.14, 0.12, 700.0, 700.0, 0.35, 6.0, 1)
	_streams["warn"] = _wav(b)

	b = _blank(0.7)
	_tone(b, 0.0, 0.65, 110.0, 35.0, 1.0, 5.0)
	_noise(b, 0.0, 0.45, 0.9, 7.0, 0.2)
	_streams["slam"] = _wav(b)

	b = _blank(0.25)
	_tone(b, 0.0, 0.22, 1200.0, 200.0, 0.5, 10.0, 2)
	_streams["zap"] = _wav(b)

	b = _blank(0.3)
	_tone(b, 0.0, 0.25, 300.0, 120.0, 0.6, 10.0, 1)
	_noise(b, 0.0, 0.2, 0.5, 15.0)
	_streams["hurt"] = _wav(b)

	b = _blank(0.5)
	_noise(b, 0.0, 0.4, 0.5, 6.0, 0.9)
	_tone(b, 0.0, 0.4, 2400.0, 3200.0, 0.2, 8.0)
	_streams["freeze"] = _wav(b)

	b = _blank(1.2)
	_tone(b, 0.0, 0.9, 523.0, 523.0, 0.4, 4.0)
	_tone(b, 0.14, 0.9, 659.0, 659.0, 0.4, 4.0)
	_tone(b, 0.28, 0.9, 784.0, 784.0, 0.4, 4.0)
	_tone(b, 0.42, 0.8, 1046.0, 1046.0, 0.45, 3.0)
	_streams["win"] = _wav(b)

	b = _blank(1.2)
	_tone(b, 0.0, 0.8, 392.0, 392.0, 0.4, 4.0)
	_tone(b, 0.2, 0.8, 330.0, 330.0, 0.4, 4.0)
	_tone(b, 0.4, 0.8, 262.0, 262.0, 0.4, 4.0)
	_tone(b, 0.6, 0.6, 196.0, 196.0, 0.45, 3.0)
	_streams["lose"] = _wav(b)

	b = _blank(0.35)
	_tone(b, 0.0, 0.3, 440.0, 880.0, 0.45, 6.0)
	_streams["start"] = _wav(b)

	# ---- boss / combat additions ----
	b = _blank(0.35)
	_noise(b, 0.0, 0.33, 0.9, 7.0, 0.3)
	_tone(b, 0.0, 0.3, 300.0, 80.0, 0.4, 9.0, 2)
	_streams["swing_heavy"] = _wav(b)

	b = _blank(0.45)
	_tone(b, 0.0, 0.42, 2600.0, 3400.0, 0.35, 9.0)
	_tone(b, 0.0, 0.4, 3900.0, 5200.0, 0.2, 11.0)
	_streams["glint"] = _wav(b)

	b = _blank(0.5)
	_tone(b, 0.0, 0.48, 1500.0, 1300.0, 0.4, 7.0, 1)
	_tone(b, 0.05, 0.42, 2250.0, 2000.0, 0.25, 8.0)
	_streams["glint_red"] = _wav(b)

	b = _blank(1.5)
	_tone(b, 0.0, 1.4, 95.0, 55.0, 0.7, 1.6, 2)
	_tone(b, 0.0, 1.4, 142.0, 80.0, 0.35, 1.8, 2)
	_noise(b, 0.0, 1.4, 0.55, 1.8, 0.18)
	_streams["roar"] = _wav(b, 0.9)

	b = _blank(0.9)
	_tone(b, 0.0, 0.85, 70.0, 30.0, 1.0, 3.5)
	_noise(b, 0.0, 0.8, 0.8, 4.0, 0.12)
	_streams["quake"] = _wav(b)

	b = _blank(0.6)
	_noise(b, 0.0, 0.55, 0.7, 4.0, 0.25)
	_tone(b, 0.0, 0.5, 120.0, 400.0, 0.3, 4.0, 2)
	_streams["leap"] = _wav(b)

	b = _blank(2.4)
	_tone(b, 0.0, 2.35, 110.0, 120.0, 0.35, 0.4, 1)
	_tone(b, 0.0, 2.35, 220.0, 236.0, 0.25, 0.4, 2)
	_noise(b, 0.0, 2.35, 0.35, 0.5, 0.5)
	_streams["beam"] = _wav(b)

	b = _blank(1.2)
	_tone(b, 0.0, 1.15, 150.0, 900.0, 0.35, 0.8, 2)
	_noise(b, 0.0, 1.15, 0.2, 1.0, 0.3)
	_streams["charge"] = _wav(b)

	b = _blank(0.4)
	_noise(b, 0.0, 0.38, 0.9, 5.0, 0.35)
	_tone(b, 0.0, 0.35, 90.0, 60.0, 0.6, 6.0)
	_streams["dash"] = _wav(b)

	b = _blank(0.25)
	_tone(b, 0.0, 0.22, 65.0, 40.0, 0.7, 14.0)
	_noise(b, 0.0, 0.12, 0.3, 25.0, 0.15)
	_streams["step"] = _wav(b, 0.5)

	b = _blank(0.4)
	_noise(b, 0.0, 0.35, 0.7, 10.0, 0.6)
	_tone(b, 0.0, 0.3, 900.0, 300.0, 0.35, 9.0, 1)
	_streams["spike"] = _wav(b)

	b = _blank(1.6)
	_tone(b, 0.0, 1.5, 80.0, 25.0, 1.0, 2.0)
	_noise(b, 0.0, 1.5, 1.0, 2.5, 0.25)
	_tone(b, 0.0, 0.4, 1800.0, 600.0, 0.3, 6.0)
	_streams["blast"] = _wav(b)

	b = _blank(0.6)
	_tone(b, 0.0, 0.55, 1250.0, 1250.0, 0.45, 6.0)
	_tone(b, 0.0, 0.55, 1870.0, 1870.0, 0.3, 7.0)
	_tone(b, 0.0, 0.5, 3100.0, 3100.0, 0.18, 9.0)
	_noise(b, 0.0, 0.08, 0.7, 40.0)
	_streams["parry"] = _wav(b)

	b = _blank(0.45)
	_noise(b, 0.0, 0.4, 0.6, 8.0, 0.4)
	_tone(b, 0.0, 0.4, 600.0, 1400.0, 0.35, 6.0, 2)
	_tone(b, 0.15, 0.25, 160.0, 60.0, 0.7, 10.0)
	_streams["counter"] = _wav(b)
