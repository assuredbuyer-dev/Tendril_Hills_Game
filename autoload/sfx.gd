# =============================================================
# sfx.gd — AUTOLOAD "Sfx"
# -------------------------------------------------------------
# Placeholder audio: soft synth blips generated in code, so the
# game has feedback sounds with ZERO asset files.
#
#   HOW TO USE REAL SOUNDS (the normal Godot way):
#   1. Drop .wav/.ogg files into assets/sfx/ (e.g. pop.wav)
#   2. This script auto-detects them and plays the file instead
#      of the synth tone. Nothing else to wire up.
#
# Call from anywhere:  Sfx.play("pop") / "coin" / "chime" /
#                      "water" / "munch" / "deny" / "portal"
#
# RULE: sound must never be able to break the game. Every entry
# point here is guarded and fails silent. If the audio device is
# missing, busy, or the generator playback never materialises,
# Tendril Hills goes quiet and keeps running. A cozy farming game
# is still playable without a carrot pop; it is not playable if a
# missing sound card throws on the first keypress.
# =============================================================
extends Node

const KINDS := ["pop", "coin", "chime", "water", "munch", "deny", "portal",
	"jump", "land"]

# freq (Hz), duration (seconds)
const TONES := {
	"pop":    [[520.0, 0.10], [780.0, 0.10]],
	"coin":   [[880.0, 0.07], [1320.0, 0.09]],
	"water":  [[300.0, 0.10], [240.0, 0.12]],
	"chime":  [[660.0, 0.16], [880.0, 0.16], [1100.0, 0.22]],
	"munch":  [[180.0, 0.07], [150.0, 0.07]],
	"deny":   [[200.0, 0.13]],
	"portal": [[523.0, 0.14], [659.0, 0.14], [784.0, 0.14], [1046.0, 0.22]],
	"jump":   [[420.0, 0.05], [640.0, 0.07]],    # a little rising boing
	"land":   [[170.0, 0.05], [120.0, 0.07]],    # soft clay thud
}

var muted := false

var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _mix_rate := 22050.0
var _streams := {}          # kind -> AudioStreamPlayer loaded from assets/sfx
var _synth_ok := true       # flips false for good if the device never shows up


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = _mix_rate
	gen.buffer_length = 0.6
	_player = AudioStreamPlayer.new()
	_player.name = "SynthChannel"
	_player.stream = gen
	add_child(_player)
	_player.play()

	# Real sound files, if any have been dropped in.
	for kind in KINDS:
		for ext in ["wav", "ogg"]:
			var path := "res://assets/sfx/%s.%s" % [kind, ext]
			if not ResourceLoader.exists(path):
				continue
			var stream: AudioStream = load(path)
			if stream == null:
				continue
			var p := AudioStreamPlayer.new()
			p.stream = stream
			add_child(p)
			_streams[kind] = p
			break


# get_stream_playback() can legitimately return null right after
# play() — the audio server may not have picked the stream up yet,
# and how long that takes varies by platform and driver. So we
# fetch it lazily on first use rather than caching it in _ready().
func _acquire_playback() -> bool:
	if _playback != null:
		return true
	if not _synth_ok or _player == null or not is_instance_valid(_player):
		return false
	if not _player.playing:
		_player.play()
	var pb := _player.get_stream_playback()
	if pb is AudioStreamGeneratorPlayback:
		_playback = pb
		return true
	return false


func play(kind: String) -> void:
	if muted:
		return

	# A real file always wins over the synth.
	var real = _streams.get(kind)
	if real != null and is_instance_valid(real):
		real.play()
		return

	if not TONES.has(kind):
		return
	if not _acquire_playback():
		return
	_tones(TONES[kind])


# Pushes a short sequence of decaying sine blips into the
# generator buffer. Simple, but sounds pleasantly "clay".
#
# NOTE FOR ANYONE PORTING GODOT 3 AUDIO CODE: there is no
# can_push_frame() in Godot 4. It was AudioStreamGeneratorPlayback's
# Godot 3 API and calling it throws at runtime, taking down whatever
# gameplay action triggered the sound. Godot 4 asks the buffer how
# much room it has: get_frames_available(). Building the whole tone
# and pushing it in one push_buffer() call is also thousands of
# times fewer calls than pushing frame by frame.
func _tones(sequence: Array) -> void:
	var buf := PackedVector2Array()
	for pair in sequence:
		var freq := float(pair[0])
		var dur := float(pair[1])
		var frames := int(_mix_rate * dur)
		var phase := 0.0
		var inc := freq / _mix_rate
		for i in frames:
			var decay := 1.0 - float(i) / float(frames)
			var sample := sin(phase * TAU) * 0.18 * decay
			buf.append(Vector2(sample, sample))
			phase = fmod(phase + inc, 1.0)

	var room := _playback.get_frames_available()
	if room <= 0:
		return
	if buf.size() > room:
		buf = buf.slice(0, room)
	_playback.push_buffer(buf)
