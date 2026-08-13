class_name Game
extends Node2D
## M5 主控制器：時間/難度曲線/敵人生成/經驗/武器系統/頭目戰
## ＋ SM風格HUD（Hud.gd）＋ 8-bit音效（Sfx.gd）＋ 畫面震動
## 中央迴圈驅動所有實體陣列（HTML版同構移植）

const GAME_VERSION := "Godot M6a · 2026-08-12 · 標題/暫停/存檔"
const SAVE_PATH := "user://save.cfg"
const W := 960.0
const H := 540.0
const MAX_ENEMIES := 600
const GEM_CAP := 45

static var skip_title := false   # 「再次挑戰」重載場景時跳過標題直接開打

const SUIT_LABELS := {"power": "POWER SUIT", "varia": "VARIA SUIT", "gravity": "GRAVITY SUIT", "hyper": "HYPER MODE"}
const SUIT_HIGHLIGHT := {"power": "#eef30c", "varia": "#ffcf3d", "gravity": "#4fd8ff", "hyper": "#ffffff"}
const SUIT_PRIMARY := {"power": "#e6201a", "varia": "#ff6a1a", "gravity": "#7b2fbe", "hyper": "#ffd400"}

# id: [introduceAt, hp, dmg, spd, r, weight, flyer, dash, explode]
const ENEMY_TYPES := {
	"zeela":  [0.0,   16.0, 9.0,  70.0,  13.0, 3.0, false, false, false],
	"skree":  [0.0,   10.0, 6.0,  112.0, 11.0, 2.0, true,  false, false],
	"ripper": [120.0, 12.0, 8.0,  150.0, 10.0, 2.0, false, true,  false],
	"reo":    [150.0, 15.0, 7.0,  55.0,  12.0, 1.4, true,  false, false],
	"puyo":   [300.0, 18.0, 14.0, 65.0,  12.0, 1.4, false, false, true],
	"sciser": [330.0, 36.0, 11.0, 50.0,  16.0, 1.1, false, false, false],
	"rinka":  [600.0, 20.0, 10.0, 145.0, 9.0,  1.3, true,  false, false],
}
# [t, hp, dmg, spd, spawn]
const DIFF := [
	[0.0, 1.0, 1.0, 1.0, 1.0], [120.0, 1.6, 1.05, 1.05, 0.6],
	[300.0, 2.8, 1.25, 1.15, 0.4], [600.0, 4.8, 1.5, 1.25, 0.26],
	[900.0, 7.8, 1.75, 1.35, 0.18], [1200.0, 12.5, 2.1, 1.45, 0.12],
]

var elapsed := 0.0
var spawn_timer := 0.6
var enemies: Array[EnemyUnit] = []
var gems: Array[GemPickup] = []
var xp := 0.0
var level := 1
var xp_next := 10.0
var levelups_queued := 0
var menu_open := false
var dead := false
var magnet_radius := 90.0
var announce_state := ""          # 公告狀態機："" 無 / wait 等任意鍵 / closing cut-in滑出收尾
var announce_min_t := 0.0         # 最短顯示時間（防止手滑瞬間跳過）
var announce_close_t := 0.0
var announce_input_ready := false # 需先放開所有按鍵再按（防移動鍵按著就跳過）
var announce_action := ""         # 公告結束時的動作："" / midboss / queen / cutin
var announce_entry := {}          # midboss 公告攜帶的 BOSS_TABLE 條目
var evolution_queue: Array = []   # 待公告的 WeaponSystem.WeaponInst
var final_boss_pending := false   # QUEEN 待觸發（6把全進化或25分保底）
var final_boss_triggered := false # 只觸發一次
var victorious := false
var shake_amt := 0.0              # 畫面震動強度（爆炸/頭目死亡/變身）
var m_prev := false               # M鍵靜音去彈跳
var esc_prev := false             # ESC暫停去彈跳
var pending_cutin := ""           # 待播放的變身 cut-in（動力服tier）
var reroll_left := 3              # 升級選單重選次數（每場3次）
var banish_left := 3              # 排除次數（每場3次；之後商店系統可加購）
var started := false              # 標題畫面 → 按任意鍵開始
var title_wait_t := 0.0
var title_input_ready := false
var paused := false               # ESC 暫停
var run_recorded := false         # 本局結果只記一次

var rng := RandomNumberGenerator.new()

@onready var player: PlayerUnit = $Player
var weapon_sys: WeaponSystem
var boss_sys: BossSystem
var fx: FxLayer
var hud: GameHud
var sfx: Sfx


func _ready() -> void:
	rng.randomize()
	player.z_index = 4       # 敵人(0)之上、彈幕層之下
	fx = FxLayer.new()
	fx.z_index = 6           # 粒子最上層
	add_child(fx)
	weapon_sys = WeaponSystem.new()
	weapon_sys.game = self
	weapon_sys.player = player
	weapon_sys.fx = fx
	weapon_sys.z_index = 5   # 彈幕/光束畫在玩家之上
	add_child(weapon_sys)
	boss_sys = BossSystem.new()
	boss_sys.game = self
	boss_sys.player = player
	boss_sys.fx = fx
	boss_sys.z_index = 3     # 敵方彈幕：敵人之上、玩家之下
	add_child(boss_sys)
	sfx = Sfx.new()
	add_child(sfx)
	hud = GameHud.new()
	hud.card_picked.connect(_on_card_picked)
	hud.reroll_requested.connect(_on_reroll)
	hud.banish_requested.connect(_on_banish)
	add_child(hud)
	weapon_sys.sfx = sfx
	player.sfx = sfx
	hud.menu_action.connect(_on_menu_action)
	weapon_sys.add_weapon("powerBeam")   # 初始武器
	player.reserve_triggered.connect(_on_reserve_triggered)
	hud.refresh_slots(weapon_sys)
	_load_settings()
	if skip_title:
		skip_title = false
		started = true
	else:
		player.set_process(false)
		hud.show_title(_best_line())


func _process(delta: float) -> void:
	# M鍵靜音（隨時可按，狀態存檔）
	var m_now := Input.is_physical_key_pressed(KEY_M)
	if m_now and not m_prev:
		var mm := sfx.toggle_mute()
		hud.show_banner("♪ 靜音" if mm else "♪ 音效開啟")
		_save_settings()
	m_prev = m_now
	# 標題畫面：按任意鍵開始
	if not started:
		title_wait_t += delta
		if not Input.is_anything_pressed():
			title_input_ready = true
		if title_wait_t > 0.3 and title_input_ready and Input.is_anything_pressed():
			_start_game()
		return
	if dead or victorious:
		if Input.is_physical_key_pressed(KEY_R):
			_on_menu_action("restart")
		elif Input.is_physical_key_pressed(KEY_T):
			_on_menu_action("title")
		return
	# ESC 暫停（遊玩中才可；選單/公告中不搶）
	var esc_now := Input.is_physical_key_pressed(KEY_ESCAPE)
	if esc_now and not esc_prev:
		if paused:
			_set_paused(false)
		elif not menu_open and announce_state == "":
			_set_paused(true)
	esc_prev = esc_now
	if paused:
		return
	if announce_state != "":
		# 公告期間全場暫停；按任意鍵繼續（玩家要求：不用計時，留足觀看時間）
		if announce_state == "closing":
			announce_close_t -= delta
			if announce_close_t <= 0.0:
				announce_state = ""
				announce_action = ""
				hud.hide_cutin()
				_proceed_after_menus()
			return
		announce_min_t -= delta
		if not Input.is_anything_pressed():
			announce_input_ready = true   # 需先全放開（防移動鍵按住直接跳過）
		if announce_min_t <= 0.0 and announce_input_ready and Input.is_anything_pressed():
			_finish_announce()
		return
	if menu_open:
		return
	elapsed += delta
	# 畫面震動（爆炸/頭目死亡/變身時累加，指數衰減）
	if shake_amt > 0.001:
		position = Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * shake_amt
		shake_amt *= exp(-6.0 * delta)
		if shake_amt < 0.05:
			shake_amt = 0.0
			position = Vector2.ZERO
	weapon_sys.refresh_mods()
	player.speed = 190.0 * weapon_sys.mods.speed_mult
	player.dmg_reduction = weapon_sys.mods.suit_dmg_reduction
	magnet_radius = 90.0 * weapon_sys.mods.magnet_mult
	_update_spawning(delta)
	_update_enemies(delta)
	weapon_sys.tick(delta)
	boss_sys.tick(delta)
	_update_gems(delta)
	fx.tick(delta)
	hud.update_status(player.hp, player.max_hp, elapsed, level, xp / xp_next, String(SUIT_LABELS[player.suit]), boss_sys.boss_battle)
	if player.hp <= 0.0:
		_game_over()
		return
	# ---- 頭目公告與連戰（HTML update() 同構）----
	# 保底：進化搭配湊不滿6把時，25分鐘強制觸發 QUEEN
	if not final_boss_triggered and elapsed >= 1500.0:
		final_boss_triggered = true
		final_boss_pending = true
	if boss_sys.pending_mid_boss.size() > 0 and boss_sys.boss_battle == null:
		var entry: Dictionary = boss_sys.pending_mid_boss
		boss_sys.pending_mid_boss = {}
		_show_boss_announce(String(entry["name"]), "巨大生物反應接近中，雜兵生產已停止。迎擊！", "midboss", entry)
		return
	# 頭目連戰：QUEEN 觸發時若還有中頭目未登場，依序全部登場，全數擊破後 QUEEN 才現身
	if final_boss_pending and boss_sys.boss_battle == null and boss_sys.pending_mid_boss.is_empty():
		var next := boss_sys.next_unspawned()
		if next.size() > 0:
			boss_sys.boss_spawned[next["t"]] = true
			boss_sys.pending_mid_boss = next
			return
		final_boss_pending = false
		_show_boss_announce("QUEEN METROID", "動力服已完全覺醒，星球深處的最終威脅甦醒了。擊敗它，證明薩姆斯的極限。", "queen", {})
		return
	if levelups_queued > 0:
		_open_levelup()


func add_shake(a: float) -> void:
	shake_amt = minf(10.0, shake_amt + a)


# ---------- 流程：標題/暫停/結算選單 ----------
func _start_game() -> void:
	started = true
	hud.hide_title()
	player.set_process(true)
	sfx.play("select")


func _set_paused(p: bool) -> void:
	paused = p
	player.set_process(not p)
	if p:
		hud.show_pause()
	else:
		hud.hide_pause()


func _on_menu_action(action: String) -> void:
	match action:
		"resume":
			_set_paused(false)
		"restart":
			Game.skip_title = true
			get_tree().reload_current_scene()
		"title":
			get_tree().reload_current_scene()


# ---------- 存檔（設定＋最佳紀錄）----------
func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	sfx.muted = bool(cfg.get_value("settings", "muted", false))


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)   # 保留既有紀錄區
	cfg.set_value("settings", "muted", sfx.muted)
	cfg.save(SAVE_PATH)


func _best_line() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK or int(cfg.get_value("records", "runs", 0)) == 0:
		return "尚無出擊紀錄"
	var bt := int(cfg.get_value("records", "best_time", 0))
	var bl := int(cfg.get_value("records", "best_level", 1))
	var wins := int(cfg.get_value("records", "victories", 0))
	var runs := int(cfg.get_value("records", "runs", 0))
	return "最佳存活 %02d:%02d｜最高 LV %d｜通關 %d／出擊 %d 次" % [bt / 60, bt % 60, bl, wins, runs]


func _record_run(victory: bool) -> void:
	if run_recorded:
		return
	run_recorded = true
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("records", "runs", int(cfg.get_value("records", "runs", 0)) + 1)
	cfg.set_value("records", "best_time", maxi(int(cfg.get_value("records", "best_time", 0)), int(elapsed)))
	cfg.set_value("records", "best_level", maxi(int(cfg.get_value("records", "best_level", 1)), level))
	if victory:
		cfg.set_value("records", "victories", int(cfg.get_value("records", "victories", 0)) + 1)
	cfg.save(SAVE_PATH)


func _begin_announce(action: String, min_t: float) -> void:
	announce_state = "wait"
	announce_action = action
	announce_min_t = min_t
	announce_input_ready = false
	player.set_process(false)


func _finish_announce() -> void:
	if announce_action == "cutin":
		# cut-in 有滑出動畫：先觸發滑出，短暫收尾後才繼續流程
		hud.dismiss_cutin()
		announce_state = "closing"
		announce_close_t = 0.4
		return
	hud.hide_announce()
	var action := announce_action
	announce_action = ""
	announce_state = ""
	match action:
		"midboss":
			boss_sys.start_boss_battle(announce_entry)
			announce_entry = {}
		"queen":
			boss_sys.spawn_final_boss()
	_proceed_after_menus()


func debug_skip_announce() -> void:
	# 測試/自動化專用：立即結束目前公告（跳過輸入等待與滑出動畫）
	if announce_state == "":
		return
	if announce_action == "cutin":
		announce_action = ""
		announce_state = ""
		hud.hide_cutin()
		_proceed_after_menus()
		return
	_finish_announce()


# ---------- 難度 ----------
func difficulty(t: float) -> Array:
	if t >= 1200.0:
		var extra := (t - 1200.0) / 60.0
		return [12.5 * pow(1.18, extra), 2.1 * pow(1.06, extra), 1.45, maxf(0.1, 0.12 - extra * 0.002)]
	for i in range(DIFF.size() - 1):
		var a: Array = DIFF[i]
		var b: Array = DIFF[i + 1]
		if t >= a[0] and t <= b[0]:
			var f: float = (t - a[0]) / (b[0] - a[0])
			return [lerpf(a[1], b[1], f), lerpf(a[2], b[2], f), lerpf(a[3], b[3], f), lerpf(a[4], b[4], f)]
	return [1.0, 1.0, 1.0, 1.0]


# ---------- 生成 ----------
func _update_spawning(delta: float) -> void:
	spawn_timer -= delta
	if boss_sys.boss_battle != null:
		return   # 頭目戰期間停止生產雜兵
	var d := difficulty(elapsed)
	if spawn_timer <= 0.0 and enemies.size() < MAX_ENEMIES:
		spawn_timer = d[3]
		var batch := 1 + int(elapsed / 130.0)
		for i in range(mini(batch, 9)):
			if enemies.size() >= MAX_ENEMIES:
				break
			_spawn_enemy(d)


func _spawn_enemy(d: Array) -> void:
	var pool: Array = []
	var total_w := 0.0
	for id in ENEMY_TYPES:
		if ENEMY_TYPES[id][0] <= elapsed:
			pool.append(id)
			total_w += ENEMY_TYPES[id][5]
	var r := rng.randf_range(0.0, total_w)
	var chosen: String = pool[0]
	for id in pool:
		r -= ENEMY_TYPES[id][5]
		if r <= 0.0:
			chosen = id
			break
	var t: Array = ENEMY_TYPES[chosen]
	var elite := elapsed > 480.0 and rng.randf() < minf(0.32, 0.1 + (elapsed - 480.0) / 2600.0)
	var e := EnemyUnit.new()
	var hp_m := 2.2 if elite else 1.0
	var dmg_m := 1.6 if elite else 1.0
	e.hp = t[1] * d[0] * hp_m
	e.max_hp = e.hp
	e.dmg = t[2] * d[1] * dmg_m
	e.spd = t[3] * d[2]
	e.radius = t[4] * (1.2 if elite else 1.0)
	e.flyer = t[6]
	e.dash = t[7]
	e.explode = t[8]
	e.elite = elite
	e.phase = rng.randf_range(0.0, TAU)
	e.dash_timer = rng.randf_range(1.0, 3.0)
	var edge := rng.randi_range(0, 3)
	match edge:
		0: e.position = Vector2(rng.randf_range(0, W), -20)
		1: e.position = Vector2(W + 20, rng.randf_range(0, H))
		2: e.position = Vector2(rng.randf_range(0, W), H + 20)
		_: e.position = Vector2(-20, rng.randf_range(0, H))
	var spr := Sprite2D.new()
	spr.texture = load("res://assets/enemy_%s.png" % chosen)
	var sc := minf(e.radius * 3.2 / spr.texture.get_width(), e.radius * 2.2 / spr.texture.get_height())
	spr.scale = Vector2(sc, sc)
	if elite:
		spr.modulate = Color(1.35, 1.15, 0.65)  # 鍍金
	e.spr = spr
	e.add_child(spr)
	add_child(e)
	enemies.append(e)


# ---------- 敵人行為 ----------
func _update_enemies(delta: float) -> void:
	for i in range(enemies.size() - 1, -1, -1):
		var e := enemies[i]
		e.phase += delta * 4.0
		if e.slow_timer > 0.0:
			e.slow_timer -= delta
			if e.slow_timer <= 0.0:
				e.speed_mult = 1.0
		if e.freeze_cd > 0.0:
			e.freeze_cd -= delta
		var tint: Color
		if e.hit_flash > 0.0:
			e.hit_flash -= delta
			tint = Color(2.2, 2.0, 1.4) if e.elite else Color(2.0, 2.0, 2.0)
		elif e.frozen_timer > 0.0:
			tint = Color(0.75, 1.05, 1.8)  # 冰凍藍
		elif e.elite:
			tint = Color(1.35, 1.15, 0.65)
		else:
			tint = Color.WHITE
		tint.a = e.alpha   # Phantoon 淡出／死亡演出淡出
		e.spr.modulate = tint
		if e.frozen_timer > 0.0:
			# 凍結：不移動、不接觸傷害（HTML同構）
			e.frozen_timer -= delta
			continue
		if not e.giant:
			# 巨型頭目的移動由 BossSystem 控制，不追玩家、不翻面
			var target := player.position
			if e.flyer:
				target += Vector2(sin(e.phase) * 30.0, cos(e.phase * 0.7) * 20.0)
			var spd := e.spd * e.speed_mult
			if e.dash:
				e.dash_timer -= delta
				if e.dash_timer <= 0.0:
					spd *= 2.6
					if e.dash_timer < -0.25:
						e.dash_timer = rng.randf_range(1.5, 3.0)
			var dir := (target - e.position)
			if dir.length() > 1.0:
				e.position += dir.normalized() * spd * delta
				e.spr.flip_h = player.position.x > e.position.x
		# 接觸傷害（減傷在 player.hurt 內套用；死亡演出中關閉）
		if e.dying <= 0.0 and player.invul <= 0.0 and e.position.distance_to(player.position) < e.radius + 8.0:
			var dealt := e.dmg * (1.0 - player.dmg_reduction)
			player.hurt(e.dmg)
			if e.drain:
				e.hp = minf(e.max_hp, e.hp + dealt * 2.5)   # Metroid幼體吸血回血
			fx.spawn_burst(player.position, Color("#ff5b5b"), 10, 120.0, 0.35)


func damage_enemy(e: EnemyUnit, dmg: float) -> void:
	if e.dead:
		return
	if e.giant and (e.entering or e.dying > 0.0):
		return   # 巨型頭目進場中無敵；死亡演出中不再受擊
	e.hp -= dmg
	e.hit_flash = 0.15
	sfx.play("hit")
	if e.hp <= 0.0:
		if e.giant:
			e.hp = 0.0
			e.dying = 1.6   # 進入死亡演出（BossSystem 驅動，結束後才移除）
			return
		var idx := enemies.find(e)
		if idx >= 0:
			kill_enemy(idx)


func kill_enemy(idx: int) -> void:
	var e := enemies[idx]
	if e.dead:
		return
	e.dead = true
	enemies.remove_at(idx)  # 先移除再做死亡效果：防自爆蟲互殺無限遞迴（HTML v0.9教訓）
	if e == boss_sys.boss_battle:
		# 頭目戰結束：清空敵方彈幕、恢復雜兵生產
		boss_sys.boss_battle = null
		boss_sys.enemy_projectiles.clear()
		sfx.play("bosskill")
	fx.spawn_burst(e.position, Color("#ffe066") if e.is_boss else (Color("#c58bff") if e.flyer else Color("#ffd76a")), 60 if e.is_boss else 10, 260.0 if e.is_boss else 140.0, 0.9 if e.is_boss else 0.4)
	if e.is_final_boss:
		fx.spawn_burst(e.position, Color("#1e9628"), 80, 300.0, 1.2)
		fx.spawn_burst(e.position, Color.WHITE, 50, 260.0, 1.0)
		e.queue_free()
		_trigger_victory()
		return
	if e.explode:
		for other: EnemyUnit in enemies.duplicate():
			if is_instance_valid(other) and not other.dead and other.position.distance_to(e.position) < 60.0:
				damage_enemy(other, 14.0)
		if player.invul <= 0.0 and e.position.distance_to(player.position) < 60.0:
			player.hurt(10.0)
	if e.is_boss:
		# 巨型頭目：14顆結晶（位置夾回場內），不走整合結晶（維持慶祝感）
		var total := 150.0
		for i in range(14):
			var g := GemPickup.new()
			g.setup(ceilf(total / 14.0), 7.0, false)
			g.position = Vector2(
				clampf(e.position.x + rng.randf_range(-40.0, 40.0), 30.0, W - 30.0),
				clampf(e.position.y + rng.randf_range(-40.0, 40.0), 30.0, H - 30.0))
			add_child(g)
			gems.append(g)
		e.queue_free()
		return
	var gv := 6.0 if e.elite else (3.0 if e.flyer else 2.0)
	if gems.size() >= GEM_CAP:
		var consol: GemPickup = null
		for g in gems:
			if g.consolidator:
				consol = g
				break
		if consol:
			consol.value += gv
			consol.radius = minf(17.0, 8.0 + sqrt(consol.value) * 0.9)
			consol.queue_redraw()
		else:
			var g := GemPickup.new()
			g.setup(gv, 9.0, true)
			g.position = e.position
			add_child(g)
			gems.append(g)
	else:
		var g := GemPickup.new()
		g.setup(gv, 5.0, false)
		g.position = e.position + Vector2(rng.randf_range(-20, 20), rng.randf_range(-20, 20))
		add_child(g)
		gems.append(g)
	e.queue_free()


# ---------- 晶石 ----------
func _update_gems(delta: float) -> void:
	for i in range(gems.size() - 1, -1, -1):
		var g := gems[i]
		g.phase += delta * 5.0
		var d := g.position.distance_to(player.position)
		if d < magnet_radius:
			var dir := (player.position - g.position).normalized()
			g.vx = dir.x * 420.0
			g.vy = dir.y * 420.0
		else:
			g.vx *= 0.9
			g.vy *= 0.9
		g.position += Vector2(g.vx, g.vy) * delta
		if d < 8.0 + g.radius + 4.0:
			_gain_xp(g.value)
			sfx.play("gem")
			gems.remove_at(i)
			g.queue_free()


func _gain_xp(v: float) -> void:
	xp += v
	while xp >= xp_next:
		xp -= xp_next
		level += 1
		xp_next = 6.0 + level * 3.2
		levelups_queued += 1


func _on_reserve_triggered() -> void:
	fx.spawn_burst(player.position, Color("#4fd8ff"), 40, 220.0, 0.8)


# ---------- 升級抽卡（6+6欄位、四種卡） ----------
func _open_levelup() -> void:
	var pool := weapon_sys.build_card_pool()
	if pool.is_empty():
		# 全欄位滿級：直接清空佇列，不顯示空選單卡住玩家（HTML v0.9教訓）
		levelups_queued = 0
		return
	levelups_queued -= 1
	menu_open = true
	player.set_process(false)
	sfx.play("levelup")
	_present_levelup()


func _present_levelup() -> void:
	# 從當前卡池抽3張呈現（開單/重選/排除後共用）
	var pool := weapon_sys.build_card_pool()
	if pool.is_empty():
		hud.close_levelup()
		menu_open = false
		levelups_queued = 0
		player.set_process(true)
		return
	pool.shuffle()
	var picks: Array = []
	for i in range(mini(3, pool.size())):
		var card: Dictionary = pool[i]
		var info := weapon_sys.card_label(card)
		info["card"] = card
		picks.append(info)
	hud.open_levelup(picks, reroll_left, banish_left)


func _on_reroll() -> void:
	if not menu_open or reroll_left <= 0:
		return
	reroll_left -= 1
	sfx.play("select")
	_present_levelup()


func _on_banish(card: Dictionary) -> void:
	if not menu_open or banish_left <= 0:
		return
	banish_left -= 1
	weapon_sys.banned[String(card["id"])] = true
	sfx.play("select")
	_present_levelup()


func _on_card_picked(card: Dictionary) -> void:
	sfx.play("select")
	weapon_sys.apply_card(card)
	for w in weapon_sys.check_evolutions():
		evolution_queue.append(w)
	_check_suit_tier()
	hud.refresh_slots(weapon_sys)
	hud.close_levelup()
	menu_open = false
	player.set_process(true)
	_proceed_after_menus()


func _proceed_after_menus() -> void:
	if pending_cutin != "":
		# 變身 cut-in 優先於進化公告（變身必然伴隨第2/4/6把進化）
		var tier := pending_cutin
		pending_cutin = ""
		hud.show_cutin(tier, Color(String(SUIT_PRIMARY[tier])), String(SUIT_LABELS[tier]) + " 起動！")
		_begin_announce("cutin", 1.0)
		return
	if evolution_queue.size() > 0:
		var w: WeaponSystem.WeaponInst = evolution_queue.pop_front()
		_show_evolution(w)
		return
	if levelups_queued > 0:
		_open_levelup()
		return
	player.set_process(true)


func _show_evolution(w: WeaponSystem.WeaponInst) -> void:
	var def: Dictionary = WeaponData.WEAPONS[w.id]
	var evo: Dictionary = def["evo"]
	hud.show_evolution(w.id, String(evo["name"]), String(evo["desc"]))
	_begin_announce("", 0.5)
	sfx.play("evolve")
	fx.spawn_burst(player.position, Color(String(evo["color"])), 50, 240.0, 1.0)
	hud.refresh_slots(weapon_sys)


func _check_suit_tier() -> void:
	var cnt := weapon_sys.evolved_count()
	var tier := "power"
	if cnt >= 6:
		tier = "hyper"
	elif cnt >= 4:
		tier = "gravity"
	elif cnt >= 2:
		tier = "varia"
	if tier != player.suit:
		player.set_suit(tier)
		fx.spawn_burst(player.position, Color(String(SUIT_HIGHLIGHT[tier])), 44, 230.0, 0.9)
		hud.flash_white()   # 變身白閃：刻意保留的稀有慶祝特效（設計決策）
		sfx.play("suit")
		add_shake(4.0)
		pending_cutin = tier   # 全畫面 cut-in（_proceed_after_menus 播放，優先於進化公告）
	if cnt >= 6 and not final_boss_triggered:
		final_boss_triggered = true
		final_boss_pending = true   # QUEEN METROID（含頭目連戰）由 _process 消化


func _show_boss_announce(title: String, flavor: String, action: String, entry: Dictionary) -> void:
	hud.show_boss_announce(title, flavor)
	_begin_announce(action, 0.8)
	announce_entry = entry
	sfx.play("alert")


func _trigger_victory() -> void:
	victorious = true
	sfx.play("victory")
	_record_run(true)
	var m := int(elapsed) / 60
	var s := int(elapsed) % 60
	hud.show_victory("存活 %02d:%02d｜LV %d｜%s" % [m, s, level, String(SUIT_LABELS[player.suit])])
	player.set_process(false)


func _game_over() -> void:
	dead = true
	sfx.play("gameover")
	_record_run(false)
	var m := int(elapsed) / 60
	var s := int(elapsed) % 60
	hud.show_dead("存活 %02d:%02d｜LV %d｜進化 %d 把" % [m, s, level, weapon_sys.evolved_count()])
	player.set_process(false)
