extends SceneTree
## M5.2 排除/重選功能驗證（godot --headless -s res://tests/m51_ui.gd）
## 開升級選單 → 按排除鈕（驗證卡池排除+次數-1+選單重開）→ 按重選鈕 → 選卡收單

var t := 0.0
var game: Game
var step := 0
var banned_id := ""


func _initialize() -> void:
	Game.skip_title = true   # 測試跳過標題畫面
	var scene: PackedScene = load("res://scenes/Main.tscn")
	var inst: Node = scene.instantiate()
	root.add_child(inst)
	game = inst as Game
	print("[M51TEST] initialized")


func _process(delta: float) -> bool:
	t += delta
	if game == null:
		return true
	if t > 30.0:
		print("[M51TEST] TIMEOUT step=%d" % step)
		print("[M51TEST] === FAIL ===")
		return true
	game.player.hp = game.player.max_hp
	match step:
		0:
			if t > 0.8:
				step = 1
				game._gain_xp(12.0)   # 觸發一次升級選單
		1:
			if game.menu_open and game.hud.cards_box.get_child_count() > 0:
				step = 2
				# 第一張卡的排除鈕 = 卡欄VBox的第二個子節點
				var col := game.hud.cards_box.get_child(0)
				var ban_btn: Button = col.get_child(1)
				var first_card_btn: Button = game.hud.card_buttons[0]
				banned_id = ""
				var pool_before := game.weapon_sys.build_card_pool().size()
				ban_btn.pressed.emit()
				var ok1 := game.banish_left == 2
				var ok2 := game.weapon_sys.banned.size() == 1
				var ok3 := game.menu_open
				var pool_after := game.weapon_sys.build_card_pool().size()
				print("[M51TEST] banish: left=%d banned=%d menu=%s pool %d->%d" % [game.banish_left, game.weapon_sys.banned.size(), str(game.menu_open), pool_before, pool_after])
				if not (ok1 and ok2 and ok3 and pool_after < pool_before):
					print("[M51TEST] === FAIL === (banish)")
					return true
		2:
			if t > 1.5:
				step = 3
				game.hud.reroll_btn.pressed.emit()
				print("[M51TEST] reroll: left=%d menu=%s cards=%d" % [game.reroll_left, str(game.menu_open), game.hud.card_buttons.size()])
				if game.reroll_left != 2 or not game.menu_open:
					print("[M51TEST] === FAIL === (reroll)")
					return true
		3:
			if t > 2.2:
				step = 4
				if game.hud.card_buttons.size() > 0:
					game.hud.card_buttons[0].pressed.emit()
		4:
			if t > 2.8:
				if not game.menu_open:
					print("[M51TEST] pick card -> menu closed OK")
					print("[M51TEST] === PASS ===")
				else:
					print("[M51TEST] === FAIL === (menu didn't close)")
				return true
	return false
