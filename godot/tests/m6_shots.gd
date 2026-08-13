extends SceneTree
## M6a 截圖：標題畫面＋暫停選單（godot -s res://tests/m6_shots.gd）

const OUT := "C:/Users/kento/AppData/Local/Temp/claude/C--Users-kento-OneDrive----Samus-Survivors/87e812b7-e4df-40a4-82ec-9496116720a8/scratchpad/"

var t := 0.0
var game: Game
var step := 0


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/Main.tscn")
	var inst: Node = scene.instantiate()
	root.add_child(inst)
	game = inst as Game
	print("[M6SHOT] initialized")


func _shot(name: String) -> void:
	root.get_texture().get_image().save_png(OUT + name)
	print("[M6SHOT] saved " + name)


func _process(delta: float) -> bool:
	t += delta
	if game == null:
		return true
	match step:
		0:
			if t > 0.8:
				step = 1
				_shot("m6_title.png")
				game._start_game()
		1:
			if t > 1.6:
				step = 2
				game._set_paused(true)
		2:
			if t > 2.2:
				_shot("m6_pause.png")
				print("[M6SHOT] done")
				return true
	return false
