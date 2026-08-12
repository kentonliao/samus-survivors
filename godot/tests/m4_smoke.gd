extends SceneTree
## M4 煙霧測試（godot --headless -s res://tests/m4_smoke.gd）
## 流程：快轉至5分觸發KRAID → 觀察攻擊 → 擊殺（死亡演出+結晶）
## → 觸發頭目連戰（CROCOMIRE/PHANTOON/RIDLEY依序）→ QUEEN（酸液/衝擊波/產卵）
## → 勝利畫面。收集各頭目攻擊模式旗標後輸出報告。

# 每隻頭目錨定後至少觀察秒數（涵蓋其最慢的攻擊循環），到時強制擊殺
const OBSERVE_TIME := {
	"KRAID": 5.0, "CROCOMIRE": 4.5, "PHANTOON": 8.5, "RIDLEY": 13.0, "QUEEN METROID": 10.0,
}

var t := 0.0
var game: Game
var stage := "start"
var flags := {}
var bosses_seen := {}
var last_boss_name := ""
var anchor_t := 0.0
var kraid_killed := false


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/Main.tscn")
	var inst: Node = scene.instantiate()
	root.add_child(inst)
	game = inst as Game
	Engine.time_scale = 3.0
	print("[M4TEST] initialized")


func _process(delta: float) -> bool:
	t += delta
	if game == null:
		print("[M4TEST] FAIL: game scene missing")
		return true
	if t > 120.0:
		print("[M4TEST] TIMEOUT at stage=" + stage)
		_report()
		return true
	# 快轉公告（M5.2起公告改任意鍵繼續，測試用debug skip）
	if game.announce_state != "":
		game.debug_skip_announce()
	# 防死亡
	game.player.hp = game.player.max_hp
	# 自動選卡（M5.1起用 Hud.card_buttons）
	if game.menu_open and game.hud.card_buttons.size() > 0:
		game.hud.card_buttons[0].pressed.emit()
	# ---- 旗標收集 ----
	var bs := game.boss_sys
	for p in bs.enemy_projectiles:
		flags["ep_" + p.type] = true
	var b := bs.boss_battle
	if b != null and is_instance_valid(b) and not b.dead:
		bosses_seen[b.boss_name] = true
		if b.boss_name != last_boss_name:
			last_boss_name = b.boss_name
			anchor_t = 0.0
		if b.alpha < 0.9:
			flags["phantoon_fade"] = true
		if b.dash_phase == "dash":
			flags["ridley_dash"] = true
		if b.dying > 0.0:
			flags["death_seq"] = true
		# 錨定後觀察，時間到強制擊殺
		if not b.entering and b.dying <= 0.0:
			anchor_t += delta
			var need: float = OBSERVE_TIME.get(b.boss_name, 5.0)
			if anchor_t > need:
				game.damage_enemy(b, b.hp + 10.0)
	elif last_boss_name == "KRAID" and not kraid_killed:
		kraid_killed = true
		if game.gems.size() >= 10:
			flags["boss_gems"] = true
		print("[M4TEST] KRAID killed, gems=%d" % game.gems.size())
	for e in game.enemies:
		if e.drain:
			flags["metroid"] = true
	# ---- 流程控制 ----
	match stage:
		"start":
			if t > 1.0:
				game.elapsed = 299.0   # 快轉至KRAID觸發前
				stage = "kraid"
				print("[M4TEST] stage: kraid trigger")
		"kraid":
			if kraid_killed:
				stage = "rush"
				game.final_boss_triggered = true
				game.final_boss_pending = true   # 觸發頭目連戰→QUEEN
				print("[M4TEST] stage: boss rush")
		"rush":
			if game.victorious:
				print("[M4TEST] VICTORY reached")
				_report()
				return true
	return false


func _report() -> void:
	var required := ["ep_spike", "ep_rock", "ep_fire", "ep_ghost", "ep_acid", "ep_shock",
		"phantoon_fade", "ridley_dash", "death_seq", "metroid", "boss_gems"]
	var ok := true
	for k in required:
		if not flags.has(k):
			ok = false
			print("[M4TEST] MISSING: " + k)
	for entry in BossSystem.BOSS_TABLE:
		if not bosses_seen.has(entry["name"]):
			ok = false
			print("[M4TEST] BOSS NOT SEEN: " + String(entry["name"]))
	if not bosses_seen.has("QUEEN METROID"):
		ok = false
		print("[M4TEST] BOSS NOT SEEN: QUEEN METROID")
	print("[M4TEST] bosses=%s victorious=%s" % [str(bosses_seen.keys()), str(game.victorious)])
	if ok and game.victorious:
		print("[M4TEST] === PASS ===")
	else:
		print("[M4TEST] === FAIL ===")
