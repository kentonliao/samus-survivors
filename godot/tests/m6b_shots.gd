extends SceneTree
## M6b 截圖：標題（含圖鑑/補給站按鈕）＋圖鑑＋補給站

const OUT := "C:/Users/kento/AppData/Local/Temp/claude/C--Users-kento-OneDrive----Samus-Survivors/87e812b7-e4df-40a4-82ec-9496116720a8/scratchpad/"

var t := 0.0
var game: Game
var step := 0


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/Main.tscn")
	var inst: Node = scene.instantiate()
	root.add_child(inst)
	game = inst as Game
	print("[M6BSHOT] initialized")


func _shot(name: String) -> void:
	root.get_texture().get_image().save_png(OUT + name)
	print("[M6BSHOT] saved " + name)


func _process(delta: float) -> bool:
	t += delta
	if game == null:
		return true
	match step:
		0:
			if t > 0.8:
				step = 1
				_shot("m6b_title.png")
				game._open_codex()
		1:
			if t > 1.6:
				step = 2
				_shot("m6b_codex.png")
				game._close_title_sub()
				game._open_shop()
		2:
			if t > 2.4:
				_shot("m6b_shop.png")
				print("[M6BSHOT] done")
				return true
	return false
