extends Node
## AudioBus (autoload)
## 程序化合成环境音与短音效，对应原 main.js 的 Web Audio 部分。
## 默认静音，用户点击声音按钮后开启。

var enabled := false
var master: AudioStreamPlayer
var _ambient_players: Array[AudioStreamPlayer] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func toggle() -> bool:
	enabled = not enabled
	if enabled:
		_start_ambient()
	else:
		_stop_ambient()
	return enabled

func _start_ambient() -> void:
	_stop_ambient()
	for freq in [55.0, 82.41, 110.2]:
		var p := AudioStreamPlayer.new()
		var gen := AudioStreamGenerator.new()
		gen.mix_rate = 22050
		gen.buffer_length = 1.0
		p.stream = gen
		p.volume_db = -30
		add_child(p)
		p.play()
		var playback := p.get_stream_playback() as AudioStreamGeneratorPlayback
		if playback:
			var frames := int(gen.mix_rate * 1.0)
			for i in range(frames):
				var t := float(i) / gen.mix_rate
				var v := sin(t * freq * TAU) * 0.045
				playback.push_frame(Vector2(v, v))
		_ambient_players.append(p)

func _stop_ambient() -> void:
	for p in _ambient_players:
		p.queue_free()
	_ambient_players.clear()

func play_tone(frequency: float = 330.0, duration: float = 0.2, strength: float = 0.06) -> void:
	if not enabled: return
	var p := AudioStreamPlayer.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050
	p.stream = gen
	p.volume_db = -12
	add_child(p)
	p.play()
	var playback := p.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback:
		var frames := int(gen.mix_rate * duration)
		for i in range(frames):
			var t := float(i) / gen.mix_rate
			var env: float = clamp(t / 0.015, 0.0, 1.0) * exp(-t / max(duration * 0.4, 0.01))
			var freq := frequency * pow(0.7, t / duration)
			var v := sin(t * freq * TAU) * strength * env
			playback.push_frame(Vector2(v, v))
	var tree := get_tree()
	if tree:
		await tree.create_timer(duration + 0.1).timeout
	p.queue_free()
