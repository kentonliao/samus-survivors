extends SceneTree
## M3 煙霧測試（godot --headless -s res://tests/m3_smoke.gd）
## 載入主場景 → 12武器Lv5 → 全部Lv9＋8被動Lv6（觸發12進化＋HYPER變身）
## → 快轉模擬，收集各行為類別是否實際運作的旗標，最後輸出報告。

var t := 0.0
var game: Game
var phase := 0
var flags := {}
var cards_picked := 0
var xp_timer := 0.0


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/Main.tscn")
	var inst: Node = scene.instantiate()
	root.add_child(inst)
	game = inst as Game
	Engine.time_scale = 2.5
	print("[M3TEST] initialized")


func _process(delta: float) -> bool:
	t += delta
	if game == null:
		print("[M3TEST] FAIL: game scene missing")
		return true
	# 快轉進化公告
	if game.announce_time > 0.12:
		game.announce_time = 0.12
	# 防死亡（接觸傷害會累積）
	if game.player.hp < 40.0:
		game.player.hp = game.player.max_hp
	# 模擬點擊升級卡
	if game.menu_open and game.menu_box != null:
		for c in game.menu_box.get_children():
			if c is Button:
				cards_picked += 1
				(c as Button).pressed.emit()
				break
	if phase >= 1:
		# 敵人變坦：讓它們活著走近玩家，測連鎖/地雷/脈衝/凍結近戰路徑
		for e in game.enemies:
			if e.max_hp < 5000.0:
				e.max_hp = 5000.0
				e.hp = 5000.0
		# 直接灌經驗測升級選單流程（玩家不動撿不到晶石）
		xp_timer -= delta
		if xp_timer <= 0.0 and not game.menu_open and game.announce_time <= 0.0:
			xp_timer = 1.2
			game._gain_xp(40.0)
			# 把敵人拉到玩家附近：保證地雷觸發（重力井）與脈衝命中（共鳴連鎖）
			var k := 0
			for e in game.enemies:
				e.position = game.player.position + Vector2.from_angle(TAU * float(k) / 6.0) * 70.0
				k += 1
				if k >= 6:
					break
	match phase:
		0:
			if t > 1.0:
				phase = 1
				for id in WeaponData.WEAPON_ORDER:
					if game.weapon_sys.get_weapon(id) == null:
						game.weapon_sys.add_weapon(id)
					game.weapon_sys.get_weapon(id).level = 5
				print("[M3TEST] phase1: 12 weapons lv5, enemies=%d" % game.enemies.size())
		1:
			if t > 7.0:
				phase = 2
				for id in WeaponData.WEAPON_ORDER:
					game.weapon_sys.get_weapon(id).level = 9
				for pid in WeaponData.PASSIVE_ORDER:
					if game.weapon_sys.get_passive(pid) == null:
						game.weapon_sys.apply_card({"kind": "newPassive", "id": pid})
					game.weapon_sys.get_passive(pid).level = 6
				for w in game.weapon_sys.check_evolutions():
					game.evolution_queue.append(w)
				game._check_suit_tier()
				game._proceed_after_menus()
				print("[M3TEST] phase2: evolved=%d suit=%s" % [game.weapon_sys.evolved_count(), game.player.suit])
		2:
			if t > 16.0:
				_report()
				return true
	var ws := game.weapon_sys
	if ws.projectiles.size() > 0:
		flags["projectiles"] = true
	if ws.bombs.size() > 0:
		flags["bombs"] = true
	if ws.mines.size() > 0:
		flags["mines"] = true
	if ws.novas.size() > 0:
		flags["novas"] = true
	if ws.pulses.size() > 0:
		flags["pulses"] = true
	if ws.lightning.size() > 0:
		flags["lightning"] = true
	for w in ws.weapons:
		if w.beam_target != null:
			flags["beam"] = true
	for m in ws.mines:
		if m.pulling:
			flags["mine_pull"] = true
	for p in ws.pulses:
		if p.gen > 0:
			flags["pulse_chain"] = true
	for p in ws.projectiles:
		if p.is_missile:
			flags["missiles"] = true
		flags["shape_" + p.shape] = true
	for e in game.enemies:
		if e.frozen_timer > 0.0:
			flags["freeze"] = true
		if e.speed_mult < 1.0:
			flags["slow"] = true
	return false


func _report() -> void:
	# 微型驗證：共鳴連鎖分支（30%機率，直接在敵人身上重複試行至觸發）
	var ws := game.weapon_sys
	var trial := 0
	while not flags.has("pulse_chain") and trial < 200 and game.enemies.size() > 0:
		trial += 1
		var q := WeaponSystem.PulseRing.new()
		q.pos = game.enemies[0].position
		q.max_radius = 50.0
		q.dmg = 0.1
		q.speed = 100.0
		q.weapon_id = "echoPulse"
		q.evolved = true
		ws.pulses.append(q)
		ws._update_pulses(0.05)
		for p in ws.pulses:
			if p.gen > 0:
				flags["pulse_chain"] = true
	ws.pulses.clear()
	var required := ["projectiles", "bombs", "mines", "novas", "pulses", "lightning", "beam", "missiles",
		"shape_bolt", "shape_shard", "shape_ribbon", "shape_star", "freeze", "mine_pull", "pulse_chain"]
	var probabilistic := ["slow"]
	var ok := true
	for k in required:
		if not flags.has(k):
			ok = false
			print("[M3TEST] MISSING: " + k)
	for k in probabilistic:
		if not flags.has(k):
			print("[M3TEST] WARN(機率性未觀測): " + k)
	print("[M3TEST] evolved=%d/12 suit=%s finalBossPending=%s" % [game.weapon_sys.evolved_count(), game.player.suit, str(game.final_boss_pending)])
	print("[M3TEST] cards_picked=%d level=%d enemies=%d gems=%d" % [cards_picked, game.level, game.enemies.size(), game.gems.size()])
	if ok and game.weapon_sys.evolved_count() == 12 and game.player.suit == "hyper" and cards_picked > 0:
		print("[M3TEST] === PASS ===")
	else:
		print("[M3TEST] === FAIL ===")
