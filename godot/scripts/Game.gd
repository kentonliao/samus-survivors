class_name Game
extends Node2D
## M3 主控制器：時間/難度曲線/敵人生成/經驗/HUD ＋ 完整武器系統整合
## （升級抽卡6+6欄位、12進化、進化公告、動力服自動變色）
## 中央迴圈驅動所有實體陣列（HTML版同構移植）

const W := 960.0
const H := 540.0
const MAX_ENEMIES := 600
const GEM_CAP := 45

const SUIT_LABELS := {"power": "POWER SUIT", "varia": "VARIA SUIT", "gravity": "GRAVITY SUIT", "hyper": "HYPER MODE"}
const SUIT_HIGHLIGHT := {"power": "#eef30c", "varia": "#ffcf3d", "gravity": "#4fd8ff", "hyper": "#ffffff"}

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
var announce_time := 0.0          # 進化公告倒數（>0 時遊戲暫停）
var banner_time := 0.0            # 動力服橫幅倒數
var flash_time := 0.0             # 變身白閃倒數（刻意保留的慶祝特效）
var evolution_queue: Array = []   # 待公告的 WeaponSystem.WeaponInst
var final_boss_pending := false   # 6把全進化→M4 在此觸發 QUEEN METROID

var rng := RandomNumberGenerator.new()

@onready var player: PlayerUnit = $Player
var weapon_sys: WeaponSystem
var fx: FxLayer
var hud: CanvasLayer
var hp_bar: ColorRect
var hp_label: Label
var timer_label: Label
var lv_label: Label
var xp_bar: ColorRect
var weapon_slots_label: Label
var passive_slots_label: Label
var banner_label: Label
var menu_layer: CanvasLayer
var menu_box: VBoxContainer
var announce_layer: CanvasLayer
var announce_warn: Label
var announce_name: Label
var announce_desc: Label
var flash_layer: CanvasLayer
var flash_rect: ColorRect
var dead_label: Label


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
	weapon_sys.add_weapon("powerBeam")   # 初始武器
	player.reserve_triggered.connect(_on_reserve_triggered)
	_build_hud()
	_refresh_slots()


func _process(delta: float) -> void:
	if flash_time > 0.0:
		flash_time -= delta
		flash_rect.modulate.a = clampf(flash_time / 0.6, 0.0, 1.0) * 0.9
		flash_rect.visible = flash_time > 0.0
	if banner_time > 0.0:
		banner_time -= delta
		if banner_time <= 0.0:
			banner_label.visible = false
	if dead:
		if Input.is_physical_key_pressed(KEY_R):
			get_tree().reload_current_scene()
		return
	if announce_time > 0.0:
		# 進化公告期間全場暫停
		announce_time -= delta
		if announce_time <= 0.0:
			announce_layer.visible = false
			_proceed_after_menus()
		return
	if menu_open:
		return
	elapsed += delta
	weapon_sys.refresh_mods()
	player.speed = 190.0 * weapon_sys.mods.speed_mult
	player.dmg_reduction = weapon_sys.mods.suit_dmg_reduction
	magnet_radius = 90.0 * weapon_sys.mods.magnet_mult
	_update_spawning(delta)
	_update_enemies(delta)
	weapon_sys.tick(delta)
	_update_gems(delta)
	fx.tick(delta)
	_update_hud()
	if player.hp <= 0.0:
		_game_over()
	elif levelups_queued > 0:
		_open_levelup()


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
		if e.hit_flash > 0.0:
			e.hit_flash -= delta
			e.spr.modulate = Color(2.2, 2.0, 1.4) if e.elite else Color(2.0, 2.0, 2.0)
		elif e.frozen_timer > 0.0:
			e.spr.modulate = Color(0.75, 1.05, 1.8)  # 冰凍藍
		elif e.elite:
			e.spr.modulate = Color(1.35, 1.15, 0.65)
		else:
			e.spr.modulate = Color.WHITE
		if e.frozen_timer > 0.0:
			# 凍結：不移動、不接觸傷害（HTML同構）
			e.frozen_timer -= delta
			continue
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
		# 接觸傷害（減傷在 player.hurt 內套用）
		if player.invul <= 0.0 and e.position.distance_to(player.position) < e.radius + 8.0:
			player.hurt(e.dmg)


func damage_enemy(e: EnemyUnit, dmg: float) -> void:
	if e.dead:
		return
	e.hp -= dmg
	e.hit_flash = 0.15
	if e.hp <= 0.0:
		var idx := enemies.find(e)
		if idx >= 0:
			_kill_enemy(idx)


func _kill_enemy(idx: int) -> void:
	var e := enemies[idx]
	if e.dead:
		return
	e.dead = true
	enemies.remove_at(idx)  # 先移除再做死亡效果：防自爆蟲互殺無限遞迴（HTML v0.9教訓）
	fx.spawn_burst(e.position, Color("#c58bff") if e.flyer else Color("#ffd76a"), 10, 140.0, 0.4)
	if e.explode:
		for other: EnemyUnit in enemies.duplicate():
			if is_instance_valid(other) and not other.dead and other.position.distance_to(e.position) < 60.0:
				damage_enemy(other, 14.0)
		if player.invul <= 0.0 and e.position.distance_to(player.position) < 60.0:
			player.hurt(10.0)
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
	pool.shuffle()
	for c in menu_box.get_children():
		c.queue_free()
	var title := Label.new()
	title.text = "── 能量吸收：選擇強化 ──"
	title.add_theme_font_size_override("font_size", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_box.add_child(title)
	for i in range(mini(3, pool.size())):
		var card: Dictionary = pool[i]
		var info := weapon_sys.card_label(card)
		var btn := Button.new()
		btn.text = "%s\n%s" % [String(info["title"]), String(info["desc"])]
		btn.custom_minimum_size = Vector2(600, 64)
		btn.add_theme_font_size_override("font_size", 15)
		btn.pressed.connect(_on_card_pressed.bind(card))
		menu_box.add_child(btn)
	menu_layer.visible = true


func _on_card_pressed(card: Dictionary) -> void:
	weapon_sys.apply_card(card)
	for w in weapon_sys.check_evolutions():
		evolution_queue.append(w)
	_check_suit_tier()
	_refresh_slots()
	menu_layer.visible = false
	menu_open = false
	player.set_process(true)
	_proceed_after_menus()


func _proceed_after_menus() -> void:
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
	announce_warn.text = "◆ 武器進化 ◆"
	announce_name.text = String(evo["name"])
	announce_desc.text = String(evo["desc"])
	announce_layer.visible = true
	announce_time = 2.2
	player.set_process(false)
	fx.spawn_burst(player.position, Color(String(evo["color"])), 50, 240.0, 1.0)
	_refresh_slots()


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
		flash_time = 0.6   # 變身白閃：刻意保留的稀有慶祝特效（設計決策）
		flash_rect.visible = true
		_show_banner(String(SUIT_LABELS[tier]) + " 起動！")
	if cnt >= 6 and not final_boss_pending:
		final_boss_pending = true   # M4：QUEEN METROID 頭目戰在此觸發


func _show_banner(text: String) -> void:
	banner_label.text = text
	banner_label.visible = true
	banner_time = 1.8


# ---------- HUD ----------
func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	hp_label = Label.new()
	hp_label.position = Vector2(14, 10)
	hud.add_child(hp_label)
	var hp_bg := ColorRect.new()
	hp_bg.position = Vector2(14, 34)
	hp_bg.size = Vector2(204, 14)
	hp_bg.color = Color(0.08, 0.02, 0.05)
	hud.add_child(hp_bg)
	hp_bar = ColorRect.new()
	hp_bar.position = Vector2(16, 36)
	hp_bar.size = Vector2(200, 10)
	hp_bar.color = Color("#f070a8")
	hud.add_child(hp_bar)
	weapon_slots_label = Label.new()
	weapon_slots_label.position = Vector2(14, 52)
	weapon_slots_label.add_theme_font_size_override("font_size", 13)
	hud.add_child(weapon_slots_label)
	passive_slots_label = Label.new()
	passive_slots_label.position = Vector2(14, 70)
	passive_slots_label.add_theme_font_size_override("font_size", 13)
	hud.add_child(passive_slots_label)
	timer_label = Label.new()
	timer_label.position = Vector2(W - 100, 10)
	timer_label.add_theme_font_size_override("font_size", 22)
	hud.add_child(timer_label)
	lv_label = Label.new()
	lv_label.position = Vector2(W / 2 - 30, H - 50)
	hud.add_child(lv_label)
	var xp_bg := ColorRect.new()
	xp_bg.position = Vector2(W / 2 - 210, H - 24)
	xp_bg.size = Vector2(424, 10)
	xp_bg.color = Color(0.04, 0.02, 0.07)
	hud.add_child(xp_bg)
	xp_bar = ColorRect.new()
	xp_bar.position = Vector2(W / 2 - 208, H - 22)
	xp_bar.size = Vector2(0, 6)
	xp_bar.color = Color("#58d854")
	hud.add_child(xp_bar)
	# 動力服橫幅
	banner_label = Label.new()
	banner_label.position = Vector2(0, 64)
	banner_label.size = Vector2(W, 34)
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_label.add_theme_font_size_override("font_size", 26)
	banner_label.add_theme_color_override("font_color", Color("#ffe27a"))
	banner_label.visible = false
	hud.add_child(banner_label)
	# 升級選單
	menu_layer = CanvasLayer.new()
	menu_layer.layer = 10
	menu_layer.visible = false
	add_child(menu_layer)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.0, 0.03, 0.85)
	dim.size = Vector2(W, H)
	menu_layer.add_child(dim)
	var center := CenterContainer.new()
	center.size = Vector2(W, H)
	menu_layer.add_child(center)
	menu_box = VBoxContainer.new()
	menu_box.add_theme_constant_override("separation", 14)
	center.add_child(menu_box)
	# 進化公告
	announce_layer = CanvasLayer.new()
	announce_layer.layer = 15
	announce_layer.visible = false
	add_child(announce_layer)
	var adim := ColorRect.new()
	adim.color = Color(0.02, 0.0, 0.05, 0.88)
	adim.size = Vector2(W, H)
	announce_layer.add_child(adim)
	var acenter := CenterContainer.new()
	acenter.size = Vector2(W, H)
	announce_layer.add_child(acenter)
	var abox := VBoxContainer.new()
	abox.add_theme_constant_override("separation", 12)
	acenter.add_child(abox)
	announce_warn = Label.new()
	announce_warn.add_theme_font_size_override("font_size", 20)
	announce_warn.add_theme_color_override("font_color", Color("#ff7ae0"))
	announce_warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	abox.add_child(announce_warn)
	announce_name = Label.new()
	announce_name.add_theme_font_size_override("font_size", 34)
	announce_name.add_theme_color_override("font_color", Color("#ffe27a"))
	announce_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	abox.add_child(announce_name)
	announce_desc = Label.new()
	announce_desc.add_theme_font_size_override("font_size", 17)
	announce_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	abox.add_child(announce_desc)
	# 變身白閃（最上層）
	flash_layer = CanvasLayer.new()
	flash_layer.layer = 30
	add_child(flash_layer)
	flash_rect = ColorRect.new()
	flash_rect.color = Color.WHITE
	flash_rect.size = Vector2(W, H)
	flash_rect.visible = false
	flash_layer.add_child(flash_rect)
	# 死亡畫面
	dead_label = Label.new()
	dead_label.add_theme_font_size_override("font_size", 30)
	dead_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dead_label.position = Vector2(W / 2 - 220, H / 2 - 70)
	dead_label.visible = false
	hud.add_child(dead_label)


func _refresh_slots() -> void:
	var wparts := PackedStringArray()
	for w in weapon_sys.weapons:
		var def: Dictionary = WeaponData.WEAPONS[w.id]
		wparts.append("%s %s" % [String(def["name"]), "MAX★" if w.evolved else str(w.level)])
	if wparts.size() > 0:
		weapon_slots_label.text = "武器：" + "｜".join(wparts)
	else:
		weapon_slots_label.text = "武器：—"
	var pparts := PackedStringArray()
	for p in weapon_sys.passives:
		var pdef: Dictionary = WeaponData.PASSIVES[p.id]
		pparts.append("%s %d" % [String(pdef["name"]), p.level])
	if pparts.size() > 0:
		passive_slots_label.text = "被動：" + "｜".join(pparts)
	else:
		passive_slots_label.text = "被動：—"


func _update_hud() -> void:
	hp_label.text = "ENERGY  %d / %d" % [ceili(maxf(0, player.hp)), int(player.max_hp)]
	hp_bar.size.x = 200.0 * clampf(player.hp / player.max_hp, 0.0, 1.0)
	hp_bar.color = Color("#ff4040") if player.hp / player.max_hp < 0.3 else Color("#f070a8")
	var m := int(elapsed) / 60
	var s := int(elapsed) % 60
	timer_label.text = "%02d:%02d" % [m, s]
	lv_label.text = "LV. %d" % level
	xp_bar.size.x = 420.0 * clampf(xp / xp_next, 0.0, 1.0)


func _game_over() -> void:
	dead = true
	var m := int(elapsed) / 60
	var s := int(elapsed) % 60
	dead_label.text = "ENERGY DEPLETED\n\n存活 %02d:%02d｜LV %d｜進化 %d 把\n\n按 R 重新挑戰" % [m, s, level, weapon_sys.evolved_count()]
	dead_label.visible = true
	player.set_process(false)
