extends SceneTree
## M6b 煙霧測試：BGM載入/循環/切歌、圖鑑擊殺統計、進化收集、碎片貨幣、商店購買持久化

var t := 0.0
var game: Game
var step := 0


func _initialize() -> void:
	# 備份並清空真實存檔：測試需要乾淨狀態，且不得污染玩家進度
	if FileAccess.file_exists("user://save.cfg"):
		DirAccess.copy_absolute("user://save.cfg", "user://save_backup.cfg")
		DirAccess.remove_absolute("user://save.cfg")
	Game.skip_title = true
	var scene: PackedScene = load("res://scenes/Main.tscn")
	var inst: Node = scene.instantiate()
	root.add_child(inst)
	game = inst as Game
	Engine.time_scale = 2.0
	print("[M6BTEST] initialized")


func _restore_save() -> void:
	if FileAccess.file_exists("user://save_backup.cfg"):
		DirAccess.copy_absolute("user://save_backup.cfg", "user://save.cfg")
		DirAccess.remove_absolute("user://save_backup.cfg")
	else:
		DirAccess.remove_absolute("user://save.cfg")


func _fail(msg: String) -> bool:
	print("[M6BTEST] FAIL: " + msg)
	print("[M6BTEST] === FAIL ===")
	_restore_save()
	return true


func _process(delta: float) -> bool:
	t += delta
	if game == null:
		return true
	if t > 30.0:
		return _fail("timeout step=%d" % step)
	game.player.hp = game.player.max_hp
	if game.announce_state != "":
		game.debug_skip_announce()
	if game.menu_open and game.hud.card_buttons.size() > 0:
		game.hud.card_buttons[0].pressed.emit()
	match step:
		0:
			if t > 0.5:
				step = 1
				if game.bgm.streams.size() != 3:
					return _fail("BGM 應載入3首，實際 %d" % game.bgm.streams.size())
				if game.bgm.current != "battle":
					return _fail("skip_title 開局應播 battle，實際 " + game.bgm.current)
				var s: AudioStreamWAV = game.bgm.streams["battle"]
				if s.loop_mode != AudioStreamWAV.LOOP_FORWARD or s.loop_end <= 0:
					return _fail("battle 循環點未設定")
				print("[M6BTEST] BGM OK (battle loop_end=%d)" % s.loop_end)
		1:
			if t > 4.0:
				step = 2
				if game.run_kills.is_empty():
					return _fail("4秒了 run_kills 仍為空（力量光束應有擊殺）")
				print("[M6BTEST] kills OK: " + str(game.run_kills))
				# 強制進化：powerBeam Lv9 + 超載電容6
				game.weapon_sys.get_weapon("powerBeam").level = 9
				if game.weapon_sys.get_passive("overloadCapacitor") == null:
					game.weapon_sys.apply_card({"kind": "newPassive", "id": "overloadCapacitor"})
				game.weapon_sys.get_passive("overloadCapacitor").level = 6
				var newly := game.weapon_sys.check_evolutions()
				if newly.size() > 0:
					game._show_evolution(newly[0])
		2:
			if t > 5.0:
				step = 3
				if not game.run_evos.has("novaBeam"):
					return _fail("run_evos 應含 novaBeam")
				game.elapsed = 200.0
				game.level = 9
				game._trigger_victory()
		3:
			if t > 5.6:
				step = 4
				var cfg := ConfigFile.new()
				if cfg.load(Game.SAVE_PATH) != OK:
					return _fail("save.cfg 不存在")
				var zeela := int(cfg.get_value("codex", "zeela", 0))
				var evos: Array = cfg.get_value("meta", "evos", [])
				var shards := int(cfg.get_value("meta", "shards", 0))
				print("[M6BTEST] save: zeela_kills=%d evos=%s shards=%d" % [zeela, str(evos), shards])
				if not evos.has("novaBeam"):
					return _fail("存檔 evos 應含 novaBeam")
				if shards < 34:   # 9級 + 通關25
					return _fail("碎片應 >= 34")
				# 商店：灌碎片測購買
				cfg.set_value("meta", "shards", 500)
				cfg.save(Game.SAVE_PATH)
				game._shop_buy("reroll")
				var cfg2 := ConfigFile.new()
				cfg2.load(Game.SAVE_PATH)
				var lvl := int(cfg2.get_value("meta", "shop_reroll", 0))
				var left := int(cfg2.get_value("meta", "shards", 0))
				print("[M6BTEST] shop: reroll_lvl=%d shards=%d reroll_left=%d" % [lvl, left, game.reroll_left])
				if lvl != 1 or left != 440:
					return _fail("購買後 shop_reroll 應=1、shards 應=440")
				if game.reroll_left != 4:
					return _fail("購買後本場 reroll_left 應=4")
				print("[M6BTEST] === PASS ===")
				_restore_save()
				return true
	return false
