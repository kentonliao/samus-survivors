class_name Sfx
extends Node
## 8-bit 音效播放器（HTML SFX 模組同構）：
## 14 種 wav（Python 依 RECIPES 配方預合成，master 0.9 已烘焙），
## 每種有最小間隔防洗版，M 鍵靜音由 Game 呼叫 toggle_mute()。

const MIN_MS := {
	"shoot": 90, "missile": 150, "hit": 70, "gem": 60, "levelup": 300,
	"select": 100, "evolve": 300, "suit": 300, "alert": 400, "explosion": 120,
	"hurt": 200, "bosskill": 500, "victory": 500, "gameover": 500,
}
const POOL_SIZE := 12   # 同時發聲上限（輪替使用）

var streams := {}
var players: Array[AudioStreamPlayer] = []
var next_idx := 0
var muted := false
var last := {}


func _ready() -> void:
	for name in MIN_MS:
		streams[name] = load("res://assets/sfx/%s.wav" % name)
	for i in range(POOL_SIZE):
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)


func play(name: String) -> void:
	if muted or not streams.has(name):
		return
	var now := Time.get_ticks_msec()
	var min_gap: int = MIN_MS[name]
	if last.has(name) and now - int(last[name]) < min_gap:
		return
	last[name] = now
	var p := players[next_idx]
	next_idx = (next_idx + 1) % players.size()
	p.stream = streams[name]
	p.play()


func toggle_mute() -> bool:
	muted = not muted
	return muted
