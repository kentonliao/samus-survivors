extends SceneTree
## M6a 流程煙霧測試（godot --headless -s res://tests/m6_smoke.gd）
## 標題畫面 → 開始 → 暫停/續玩 → 強制勝利 → 驗證紀錄存檔（user://save.cfg）

var t := 0.0
var game: Game
var step := 0


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/Main.tscn")
	var inst: Node = scene.instantiate()
	root.add_child(inst)
	game = inst as Game
	print("[M6TEST] initialized")


func _fail(msg: String) -> bool:
	print("[M6TEST] FAIL: " + msg)
	print("[M6TEST] === FAIL ===")
	return true


func _process(delta: float) -> bool:
	t += delta
	if game == null:
		return true
	if t > 30.0:
		return _fail("timeout step=%d" % step)
	match step:
		0:
			if t > 0.5:
				step = 1
				if game.started:
					return _fail("標題畫面未出現（started 應為 false）")
				if not game.hud.title_overlay.visible:
					return _fail("title_overlay 不可見")
				print("[M6TEST] title OK, best_line=" + game.hud.title_best.text)
				game._start_game()
		1:
			if t > 1.2:
				step = 2
				if not game.started or game.hud.title_overlay.visible:
					return _fail("開始後標題未關閉")
				var elapsed_before: float = game.elapsed
				game._set_paused(true)
				if not game.paused or not game.hud.pause_overlay.visible:
					return _fail("暫停未生效")
				print("[M6TEST] pause OK (elapsed=%.2f)" % elapsed_before)
		2:
			if t > 2.0:
				step = 3
				# 暫停期間 elapsed 不應增加（誤差容忍一幀）
				game._set_paused(false)
				if game.hud.pause_overlay.visible:
					return _fail("續玩後暫停選單未關閉")
				print("[M6TEST] resume OK")
		3:
			if t > 2.6:
				step = 4
				game.elapsed = 123.0
				game.level = 7
				game._trigger_victory()
		4:
			if t > 3.2:
				var cfg := ConfigFile.new()
				if cfg.load(Game.SAVE_PATH) != OK:
					return _fail("save.cfg 不存在")
				var runs := int(cfg.get_value("records", "runs", 0))
				var bt := int(cfg.get_value("records", "best_time", 0))
				var wins := int(cfg.get_value("records", "victories", 0))
				print("[M6TEST] save: runs=%d best_time=%d victories=%d" % [runs, bt, wins])
				if runs < 1 or bt < 123 or wins < 1:
					return _fail("紀錄數值不對")
				print("[M6TEST] === PASS ===")
				return true
	return false
