extends SceneTree
## M5 UI 視覺驗證（需有視窗執行）：依序擺出五個 UI 狀態並截圖到 scratchpad
## godot -s res://tests/m5_shots.gd

const OUT := "C:/Users/kento/AppData/Local/Temp/claude/C--Users-kento-OneDrive----Samus-Survivors/87e812b7-e4df-40a4-82ec-9496116720a8/scratchpad/"

var t := 0.0
var game: Game
var step := 0


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/Main.tscn")
	var inst: Node = scene.instantiate()
	root.add_child(inst)
	game = inst as Game
	print("[M5SHOT] initialized")


func _shot(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(OUT + name)
	print("[M5SHOT] saved " + name)


func _process(delta: float) -> bool:
	t += delta
	if game == null:
		return true
	game.player.hp = maxf(game.player.hp, 61.0)
	match step:
		0:
			if t > 0.9:
				step = 1
				# 擺設 HUD 狀態：4武器+3被動、HP 61/99、時間 12:34、XP 60%
				var ws := game.weapon_sys
				ws.add_weapon("missile")
				ws.add_weapon("iceBeam")
				ws.add_weapon("screwAttack")
				ws.get_weapon("powerBeam").level = 5
				ws.get_weapon("missile").level = 3
				ws.get_weapon("iceBeam").level = 7
				ws.apply_card({"kind": "newPassive", "id": "magnetCore"})
				ws.apply_card({"kind": "newPassive", "id": "overloadCapacitor"})
				ws.apply_card({"kind": "newPassive", "id": "criticalSensor"})
				ws.get_passive("overloadCapacitor").level = 6
				game.player.max_hp = 99.0
				game.player.hp = 61.0
				# 注意：elapsed 不能超過頭目觸發時間（300s），否則遊戲自己會發動威脅偵測公告蓋畫面
				game.elapsed = 234.0
				for entry in BossSystem.BOSS_TABLE:
					game.boss_sys.boss_spawned[entry["t"]] = true   # 保險：全部標記已登場
				game.level = 23
				game.xp = game.xp_next * 0.6
				game.hud.refresh_slots(ws)
		1:
			if t > 1.4:
				step = 2
				_shot("m5_hud.png")
				game.levelups_queued = 1   # 下一幀開升級選單
		2:
			if t > 2.0:
				step = 3
				_shot("m5_cards.png")
				if game.hud.card_buttons.size() > 0:
					game.hud.card_buttons[0].pressed.emit()
		3:
			if t > 2.5:
				step = 4
				# 強制進化公告（powerBeam Lv9 + 超載電容6）
				game.weapon_sys.get_weapon("powerBeam").level = 9
				var newly := game.weapon_sys.check_evolutions()
				if newly.size() > 0:
					game._show_evolution(newly[0])
		4:
			if t > 3.1:
				step = 5
				_shot("m5_evolve.png")
				game.debug_skip_announce()
		5:
			if t > 3.6:
				step = 6
				game._show_boss_announce("KRAID", "巨大生物反應接近中，雜兵生產已停止。迎擊！", "", {})
		6:
			if t > 4.2:
				step = 7
				_shot("m5_boss.png")
				game.debug_skip_announce()
		7:
			if t > 4.6:
				step = 8
				game.hud.show_cutin("gravity", Color("#7b2fbe"), "GRAVITY SUIT 起動！")
		8:
			if t > 5.1:
				step = 9
				_shot("m5_cutin.png")
				game.hud.hide_cutin()
				game._trigger_victory()
		9:
			if t > 5.7:
				_shot("m5_victory.png")
				print("[M5SHOT] done")
				return true
	return false
