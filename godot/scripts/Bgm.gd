class_name Bgm
extends Node
## 8-bit 配樂播放器（M6b）：三首無縫循環曲（title/battle/boss），
## 由 Python 預合成（scratchpad/bgm_gen.py），runtime 設定 wav 循環點。

const TRACKS := ["title", "battle", "boss"]
const VOLUME_DB := -10.0   # 配樂比音效小聲

var streams := {}
var player: AudioStreamPlayer
var current := ""
var muted := false


func _ready() -> void:
	for name in TRACKS:
		var s: AudioStreamWAV = load("res://assets/bgm/%s.wav" % name)
		if s != null:
			s.loop_mode = AudioStreamWAV.LOOP_FORWARD
			s.loop_begin = 0
			# 注意：wav 匯入預設 QOA 壓縮（compress/mode=2），data.size()/2 不再是樣本數，
			# 必須用長度×取樣率（格式無關）——否則循環點切在曲子中間
			s.loop_end = int(s.get_length() * s.mix_rate)
			streams[name] = s
	player = AudioStreamPlayer.new()
	player.volume_db = VOLUME_DB
	add_child(player)


func play_track(name: String) -> void:
	if current == name:
		return
	current = name
	if not streams.has(name):
		return
	player.stream = streams[name]
	if not muted:
		player.play()


func stop_music() -> void:
	current = ""
	player.stop()


func set_muted(m: bool) -> void:
	muted = m
	if m:
		player.stop()
	elif current != "" and streams.has(current):
		player.stream = streams[current]
		player.play()
