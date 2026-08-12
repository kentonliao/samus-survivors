extends Node2D
## M2 主控制器：時間/難度曲線/敵人生成/經驗/升級選單/HUD
## 中央迴圈驅動所有實體陣列（HTML版同構移植）

const W := 960.0
const H := 540.0
const MAX_ENEMIES := 600
const GEM_CAP := 45

# id: [introduceAt, hp, dmg, spd, r, weight, flyer, dash, explode, color_hint]
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
var bolts: Array[BoltShot] = []
var xp := 0.0
var level := 1
var xp_next := 10.0
var levelups_queued := 0
var menu_open := false
var dead := false
var magnet_radius := 90.0
# M2 佔位武器：力量光束
var fire_timer := 0.0
var wpn_dmg := 8.0
var wpn_cd := 0.42
var wpn_count := 1

var rng := RandomNumberGenerator.new()

@onready var player: Node2D = $Player
var hud: CanvasLayer
var hp_bar: ColorRect
var hp_label: Label
var timer_label: Label
var lv_label: Label
var xp_bar: ColorRect
var menu_layer: CanvasLayer
var menu_box: VBoxContainer
var dead_label: Label

func _ready() -> void:
	rng.randomize()
	_build_hud()

func _process(delta: float) -> void:
	if dead:
		if Input.is_physical_key_pressed(KEY_R):
			get_tree().reload_current_scene()
		return
	if menu_open:
		return
	elapsed += delta
	_update_spawning(delta)
	_update_enemies(delta)
	_update_weapon(delta)
	_update_bolts(delta)
	_update_gems(delta)
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
			var f := (t - a[0]) / (b[0] - a[0])
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
			if enemies.size() >= MAX_ENEMIES: break
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
		if e.hit_flash > 0.0:
			e.hit_flash -= delta
			e.spr.modulate = Color(2.0, 2.0, 2.0) if not e.elite else Color(2.2, 2.0, 1.4)
		else:
			e.spr.modulate = Color(1.35, 1.15, 0.65) if e.elite else Color.WHITE
		var target := player.position
		if e.flyer:
			target += Vector2(sin(e.phase) * 30.0, cos(e.phase * 0.7) * 20.0)
		var spd := e.spd
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
		# 接觸傷害
		if player.invul <= 0.0 and e.position.distance_to(player.position) < e.radius + 8.0:
			player.hurt(e.dmg)

func _kill_enemy(idx: int) -> void:
	var e := enemies[idx]
	enemies.remove_at(idx)
	if e.explode:
		for other in enemies:
			if other.position.distance_to(e.position) < 60.0:
				_damage(other, 14.0)
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

func _damage(e: EnemyUnit, dmg: float) -> void:
	e.hp -= dmg
	e.hit_flash = 0.15
	if e.hp <= 0.0:
		var idx := enemies.find(e)
		if idx >= 0:
			_kill_enemy(idx)

# ---------- 佔位武器：力量光束 ----------
func _update_weapon(delta: float) -> void:
	fire_timer -= delta
	if fire_timer <= 0.0 and enemies.size() > 0:
		fire_timer = wpn_cd
		var nearest: EnemyUnit = null
		var best := INF
		for e in enemies:
			var dd := e.position.distance_squared_to(player.position)
			if dd < best:
				best = dd
				nearest = e
		if nearest == null:
			return
		var base_ang := (nearest.position - player.position).angle()
		for i in range(wpn_count):
			var ang := base_ang + (i - (wpn_count - 1) / 2.0) * 0.16
			var b := BoltShot.new()
			b.position = player.position
			b.vx = cos(ang) * 520.0
			b.vy = sin(ang) * 520.0
			b.dmg = wpn_dmg
			b.rotation = ang
			add_child(b)
			bolts.append(b)

func _update_bolts(delta: float) -> void:
	for i in range(bolts.size() - 1, -1, -1):
		var b := bolts[i]
		b.age += delta
		b.life -= delta
		b.position += Vector2(b.vx, b.vy) * delta
		b.queue_redraw()
		var out := b.life <= 0.0 or b.position.x < -20 or b.position.x > W + 20 or b.position.y < -20 or b.position.y > H + 20
		var used := false
		if not out:
			for e in enemies:
				if e.position.distance_to(b.position) < e.radius + 4.0:
					_damage(e, b.dmg)
					b.pierce -= 1
					if b.pierce <= 0:
						used = true
					break
		if out or used:
			bolts.remove_at(i)
			b.queue_free()

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

func _up_hp() -> void:
	player.max_hp += 20.0
	player.hp = player.max_hp

func _gain_xp(v: float) -> void:
	xp += v
	while xp >= xp_next:
		xp -= xp_next
		level += 1
		xp_next = 6.0 + level * 3.2
		levelups_queued += 1

# ---------- 升級選單（M2文字卡佔位） ----------
func _open_levelup() -> void:
	levelups_queued -= 1
	menu_open = true
	player.set_process(false)
	var pool := [
		["光束傷害 +25%", func(): wpn_dmg *= 1.25],
		["射速 +15%", func(): wpn_cd = maxf(0.12, wpn_cd * 0.87)],
		["移動速度 +10%", func(): player.speed *= 1.1],
		["能量上限 +20（回滿）", _up_hp],
		["磁吸範圍 +25%", func(): magnet_radius *= 1.25],
		["光束 +1 發", func(): wpn_count += 1],
	]
	pool.shuffle()
	for c in menu_box.get_children():
		c.queue_free()
	var title := Label.new()
	title.text = "── 能量吸收：選擇升級 ──"
	title.add_theme_font_size_override("font_size", 22)
	menu_box.add_child(title)
	for i in range(3):
		var btn := Button.new()
		btn.text = pool[i][0]
		btn.custom_minimum_size = Vector2(320, 48)
		var f: Callable = pool[i][1]
		btn.pressed.connect(func():
			f.call()
			menu_open = false
			player.set_process(true)
			menu_layer.visible = false)
		menu_box.add_child(btn)
	menu_layer.visible = true

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
	# 死亡畫面
	dead_label = Label.new()
	dead_label.text = "ENERGY DEPLETED\n\n按 R 重新挑戰"
	dead_label.add_theme_font_size_override("font_size", 30)
	dead_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dead_label.position = Vector2(W / 2 - 160, H / 2 - 60)
	dead_label.visible = false
	hud.add_child(dead_label)

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
	dead_label.visible = true
	player.set_process(false)
