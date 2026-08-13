class_name BossSystem
extends Node2D
## M4 巨型頭目戰（index.html 同構移植）：
## 頭目佔滿畫面一側、從側邊滑入（進場無敵）、專屬攻擊模式、死亡演出（連環爆炸+震動+淡出）、
## 戰鬥期間停止生產雜兵。素材截斷側（Kraid尾巴等）永遠貼齊畫面邊緣之外。
## 敵方彈幕（spike/rock/fire/ghost/acid/shock）存純資料陣列，_draw 統一繪製。

const BOSS_TABLE := [
	{"t": 300.0,  "name": "KRAID",     "tex": "enemy_kraid",     "color": "#ff6a1a", "hp": 80000.0,  "dmg": 26.0, "heightFrac": 0.70, "grounded": true},
	{"t": 600.0,  "name": "CROCOMIRE", "tex": "enemy_crocomire", "color": "#ff9b3d", "hp": 150000.0, "dmg": 22.0, "heightFrac": 0.48, "grounded": true},
	{"t": 900.0,  "name": "PHANTOON",  "tex": "enemy_phantoon",  "color": "#9b59d0", "hp": 250000.0, "dmg": 30.0, "heightFrac": 0.60, "grounded": false},
	{"t": 1200.0, "name": "RIDLEY",    "tex": "enemy_ridley",    "color": "#c0272c", "hp": 380000.0, "dmg": 38.0, "heightFrac": 0.44, "grounded": false},
]
const MAX_ENEMY_PROJECTILES := 90


class EProj:
	var type := "fire"       # spike / rock / fire / ghost / acid / shock
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var r := 7.0
	var dmg := 10.0
	var life := 3.0
	var age := 0.0
	var gravity := 0.0
	var color := Color.WHITE
	# shock（擴張衝擊波）專用
	var radius := 0.0
	var speed := 0.0
	var max_radius := 0.0
	var hit_done := false


var game: Game
var player: PlayerUnit
var fx: FxLayer
var rng := RandomNumberGenerator.new()

var boss_battle: EnemyUnit = null   # 進行中的巨型頭目戰
var boss_spawned := {}              # t -> true
var pending_mid_boss := {}          # 排隊等待公告的中頭目（空=無）
var enemy_projectiles: Array[EProj] = []


func _ready() -> void:
	rng.randomize()


func final_boss_active() -> bool:
	for e in game.enemies:
		if e.is_final_boss:
			return true
	return false


func next_unspawned() -> Dictionary:
	for entry in BOSS_TABLE:
		if not boss_spawned.has(entry["t"]):
			return entry
	return {}


func check_time_triggers() -> void:
	# 前一場頭目戰未結束時延後下一場；排入公告佇列（由 Game._process 消化）
	for entry in BOSS_TABLE:
		var tt: float = entry["t"]
		if game.elapsed >= tt and not boss_spawned.has(tt) and boss_battle == null \
				and pending_mid_boss.is_empty() and not final_boss_active():
			boss_spawned[tt] = true
			pending_mid_boss = entry


func start_boss_battle(entry: Dictionary) -> void:
	var tex: Texture2D = load("res://assets/%s.png" % String(entry["tex"]))
	var side := "left" if rng.randf() < 0.5 else "right"
	# 血量隨時間難度超線性放大（回饋：「第2隻起反而比第一隻好打」）：5分Kraid為基準×1
	var d := game.difficulty(game.elapsed)
	var hp_scale := pow(maxf(1.0, float(d[0]) / 2.8), 1.6)
	var boss_hp := roundf(float(entry["hp"]) * hp_scale)
	var target_h: float = Game.H * float(entry["heightFrac"])
	var scale := target_h / float(tex.get_height())
	var wpx := float(tex.get_width()) * scale
	# 素材皆面向左、截斷側在右：右側登場不翻面，左側登場翻面，截斷側都超出畫面外
	var anchor_x := (Game.W - wpx / 2.0 + wpx * 0.06) if side == "right" else (wpx / 2.0 - wpx * 0.06)
	var base_y := (Game.H - 18.0 - target_h / 2.0) if bool(entry["grounded"]) else Game.H * 0.42
	var b := EnemyUnit.new()
	b.is_boss = true
	b.giant = true
	b.boss_name = String(entry["name"])
	b.type_id = String(entry["tex"]).replace("enemy_", "")
	b.side = side
	b.position = Vector2((Game.W + wpx * 0.7) if side == "right" else (-wpx * 0.7), base_y)
	b.base_x = anchor_x
	b.base_y = base_y
	b.target_pos = Vector2(anchor_x, base_y)
	b.entering = true
	b.sprite_scale = scale
	b.wpx = wpx
	b.hpx = target_h
	b.face_right = side == "left"
	b.radius = minf(wpx, target_h) * 0.38
	b.hp = boss_hp
	b.max_hp = boss_hp
	b.dmg = float(entry["dmg"])
	b.spd = 0.0
	b.attack_timer = 2.2
	b.rock_timer = 3.5
	b.tp_timer = 6.0
	b.boss_dash_timer = 6.0
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.scale = Vector2(scale, scale)
	spr.flip_h = b.face_right
	b.spr = spr
	b.add_child(spr)
	game.add_child(b)
	game.enemies.append(b)
	boss_battle = b


func spawn_final_boss() -> void:
	var tex: Texture2D = load("res://assets/boss_queen.png")
	var d := game.difficulty(game.elapsed)
	# ×6：全進化陣容DPS極高（HTML回饋確認）
	var hp := 90000.0 * maxf(1.0, float(d[0]) * 0.8) * 6.0
	var scale := 2.1
	var wpx := float(tex.get_width()) * scale
	var hpx := float(tex.get_height()) * scale
	var b := EnemyUnit.new()
	b.is_boss = true
	b.giant = true
	b.is_final_boss = true
	b.boss_name = "QUEEN METROID"
	b.type_id = "queen"
	b.side = "top"
	b.position = Vector2(Game.W / 2.0, -hpx * 0.7)
	b.target_pos = Vector2(Game.W / 2.0, hpx * 0.42 + 10.0)
	b.base_x = Game.W / 2.0
	b.base_y = hpx * 0.42 + 10.0
	b.entering = true
	b.sprite_scale = scale
	b.wpx = wpx
	b.hpx = hpx
	b.radius = minf(wpx, hpx) * 0.4
	b.hp = hp
	b.max_hp = hp
	b.dmg = 34.0
	b.spd = 0.0
	b.attack_timer = 2.5
	b.shock_timer = 8.0
	b.egg_timer = 4.0
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.scale = Vector2(scale, scale)
	b.spr = spr
	b.add_child(spr)
	game.add_child(b)
	game.enemies.append(b)
	boss_battle = b   # 皇后也走頭目戰系統：頂部血條、彈幕、死亡演出、雜兵停產


func spawn_metroid(pos: Vector2) -> void:
	var d := game.difficulty(game.elapsed)
	var e := EnemyUnit.new()
	e.type_id = "metroid"
	e.position = pos
	e.radius = 15.0
	e.hp = 130.0 * float(d[0])
	e.max_hp = e.hp
	e.spd = 140.0
	e.dmg = 12.0
	e.flyer = true
	e.drain = true
	e.phase = rng.randf_range(0.0, 7.0)
	var spr := Sprite2D.new()
	spr.texture = load("res://assets/enemy_metroid.png")
	var sc := minf(e.radius * 3.2 / spr.texture.get_width(), e.radius * 2.2 / spr.texture.get_height())
	spr.scale = Vector2(sc, sc)
	e.spr = spr
	e.add_child(spr)
	game.add_child(e)
	game.enemies.append(e)
	fx.spawn_burst(pos, Color("#3adb4e"), 12, 130.0, 0.4)


func metroid_count() -> int:
	var n := 0
	for e in game.enemies:
		if e.drain:
			n += 1
	return n


# ---------- 中央更新 ----------
func tick(dt: float) -> void:
	check_time_triggers()
	_update_boss(dt)
	_update_projectiles(dt)
	queue_redraw()


func _fire(p: EProj) -> void:
	if enemy_projectiles.size() >= MAX_ENEMY_PROJECTILES:
		enemy_projectiles.pop_front()
	enemy_projectiles.append(p)


func _aim_at_player(b: EnemyUnit, spread: float) -> float:
	return (player.position - b.position).angle() + rng.randf_range(-spread, spread)


func _make_proj(type: String, pos: Vector2, ang: float, speed: float, r: float, dmg: float, life: float, color: String) -> EProj:
	var p := EProj.new()
	p.type = type
	p.pos = pos
	p.vel = Vector2.from_angle(ang) * speed
	p.r = r
	p.dmg = dmg
	p.life = life
	p.color = Color(color)
	return p


func _update_boss(dt: float) -> void:
	var b := boss_battle
	if b == null:
		return
	if not is_instance_valid(b) or b.dead:
		boss_battle = null
		return
	# 死亡演出：連環爆炸＋震動＋淡出，結束後才真正移除（回饋：只是消失太突然）
	if b.dying > 0.0:
		b.dying -= dt
		b.death_fx_t -= dt
		if b.death_fx_t <= 0.0:
			b.death_fx_t = 0.13
			var bp := b.position + Vector2(rng.randf_range(-b.wpx * 0.3, b.wpx * 0.3), rng.randf_range(-b.hpx * 0.35, b.hpx * 0.35))
			fx.spawn_burst(bp, Color("#ffe066"), 14, 190.0, 0.5)
			fx.add_ring(b.position + Vector2(rng.randf_range(-b.wpx * 0.25, b.wpx * 0.25), rng.randf_range(-b.hpx * 0.3, b.hpx * 0.3)), rng.randf_range(35.0, 75.0), Color("#ffbf50"))
			game.sfx.play("explosion")
			game.add_shake(2.5)
		b.alpha = clampf(b.dying / 1.0, 0.0, 1.0)
		b.shake_x = rng.randf_range(-4.0, 4.0)
		b.shake_y = rng.randf_range(-3.0, 3.0)
		_apply_giant_visual(b)
		if b.dying <= 0.0:
			fx.spawn_burst(b.position, Color.WHITE, 60, 320.0, 0.9)
			fx.add_ring(b.position, maxf(b.wpx, b.hpx) * 0.7, Color.WHITE)
			game.add_shake(8.0)
			var idx := game.enemies.find(b)
			if idx >= 0:
				game.kill_enemy(idx)
		return
	if b.lunge_t > 0.0:
		b.lunge_t -= dt
	# 進場（必須在凍結檢查之前：否則冰凍光束會把頭目永久卡在場外造成軟鎖——HTML v1.4教訓）
	if b.entering:
		var delta := b.target_pos - b.position
		var dist := delta.length()
		var step := 170.0 * dt
		if dist <= step:
			b.position = b.target_pos
			b.entering = false
		else:
			b.position += delta / dist * step
		_apply_giant_visual(b)
		return
	if b.frozen_timer > 0.0:
		_apply_giant_visual(b)
		return   # 冰凍時暫停行動（獎勵冰系，freeze_cd 防永凍）
	b.pattern_t += dt
	b.attack_timer -= dt
	var fire_dir := 1.0 if b.face_right else -1.0
	match b.boss_name:
		"KRAID":
			# 腹部三連尖刺（瞄準玩家）＋全場落石（拋物線）
			if b.attack_timer <= 0.0:
				b.attack_timer = 2.3
				b.lunge_t = 0.25
				for i in range(3):
					var ang := _aim_at_player(b, 0.14)
					var pos := b.position + Vector2(fire_dir * b.wpx * 0.22, -b.hpx * 0.18 + float(i) * b.hpx * 0.16)
					_fire(_make_proj("spike", pos, ang, 250.0, 7.0, 14.0, 3.0, "#e8e3b0"))
			b.rock_timer -= dt
			if b.rock_timer <= 0.0:
				b.rock_timer = 3.6
				for i in range(3):
					var p := EProj.new()
					p.type = "rock"
					p.pos = Vector2(rng.randf_range(40.0, Game.W - 40.0), -16.0 - float(i) * 30.0)
					p.vel = Vector2(rng.randf_range(-15.0, 15.0), 50.0)
					p.gravity = 330.0
					p.r = 9.0
					p.dmg = 16.0
					p.life = 4.0
					p.color = Color("#a8825a")
					_fire(p)
		"CROCOMIRE":
			# 沿側邊上下巡弋＋5發扇形火彈
			b.position.y = b.base_y + sin(b.pattern_t * 0.85) * Game.H * 0.2
			if b.attack_timer <= 0.0:
				b.attack_timer = 2.7
				b.lunge_t = 0.25
				var base := _aim_at_player(b, 0.0)
				for i in range(-2, 3):
					var pos := b.position + Vector2(fire_dir * b.wpx * 0.3, -b.hpx * 0.08)
					_fire(_make_proj("fire", pos, base + float(i) * 0.24, 210.0, 7.0, 12.0, 3.2, "#ff8a2a"))
		"PHANTOON":
			# 瞬移換邊（淡出→換邊→淡入）＋10發環形幽靈火球
			b.position.y = b.base_y + sin(b.pattern_t * 1.3) * 26.0
			b.tp_timer -= dt
			if b.tp_timer <= -0.8:
				b.tp_timer = 6.0
				b.alpha = 1.0
			elif b.tp_timer <= 0.0:
				if b.alpha > 0.95:   # 瞬移時刻：換邊
					b.side = "left" if b.side == "right" else "right"
					b.face_right = b.side == "left"
					b.spr.flip_h = b.face_right
					b.position.x = (Game.W - b.wpx / 2.0 + b.wpx * 0.06) if b.side == "right" else (b.wpx / 2.0 - b.wpx * 0.06)
				b.alpha = minf(1.0, 0.25 + (-b.tp_timer) / 0.8 * 0.75)   # 淡入
			elif b.tp_timer <= 0.7:
				b.alpha = maxf(0.25, b.tp_timer / 0.7)   # 淡出
			if b.attack_timer <= 0.0 and b.alpha > 0.9:
				b.attack_timer = 3.1
				b.lunge_t = 0.25
				var n := 10
				for i in range(n):
					var ang := TAU / float(n) * float(i) + b.pattern_t
					var pos := b.position + Vector2(fire_dir * b.wpx * 0.1, 0)
					_fire(_make_proj("ghost", pos, ang, 140.0, 7.0, 10.0, 4.0, "#c07df0"))
		"RIDLEY":
			# 平時盤旋吐火球；定期鎖定玩家高度→紅色預警→720px/s俯衝橫掃→衝出畫面換邊重進場
			if b.dash_phase == "telegraph":
				b.dash_t -= dt
				b.position.y += (b.dash_y - b.position.y) * minf(1.0, dt * 6.0)
				if b.dash_t <= 0.0:
					b.dash_phase = "dash"
					b.dash_vx = (-720.0 if b.side == "right" else 720.0)
					b.face_right = b.dash_vx > 0.0
					b.spr.flip_h = b.face_right
			elif b.dash_phase == "dash":
				b.position.x += b.dash_vx * dt
				var out := b.position.x > Game.W + b.wpx * 0.6 if b.dash_vx > 0.0 else b.position.x < -b.wpx * 0.6
				if out:   # 衝出畫面，換邊重新進場
					b.side = "right" if b.dash_vx > 0.0 else "left"
					b.face_right = b.side == "left"
					b.spr.flip_h = b.face_right
					var anchor_x := (Game.W - b.wpx / 2.0 + b.wpx * 0.06) if b.side == "right" else (b.wpx / 2.0 - b.wpx * 0.06)
					b.target_pos = Vector2(anchor_x, b.base_y)
					b.position = Vector2((Game.W + b.wpx * 0.7) if b.side == "right" else (-b.wpx * 0.7), b.base_y)
					b.dash_phase = ""
					b.entering = true
					b.boss_dash_timer = 7.0
			else:
				b.position.y = b.base_y + sin(b.pattern_t * 1.1) * 30.0
				b.boss_dash_timer -= dt
				if b.boss_dash_timer <= 0.0:
					b.dash_phase = "telegraph"
					b.dash_t = 0.8
					b.dash_y = player.position.y
					fx.spawn_burst(b.position, Color("#ff4040"), 20, 180.0, 0.5)
				if b.attack_timer <= 0.0:
					b.attack_timer = 2.4
					b.lunge_t = 0.25
					for i in range(2):
						var ang := _aim_at_player(b, 0.1)
						var pos := b.position + Vector2(fire_dir * b.wpx * 0.28, -b.hpx * 0.2)
						_fire(_make_proj("fire", pos, ang, 265.0, 8.0, 16.0, 3.0, "#ff5030"))
		"QUEEN METROID":
			# 佔據畫面上方橫向游移；酸液扇射＋全場衝擊波＋產卵吸血Metroid幼體
			b.position.x = b.base_x + sin(b.pattern_t * 0.5) * 95.0
			b.position.y = b.base_y + sin(b.pattern_t * 1.1) * 12.0
			if b.attack_timer <= 0.0:
				b.attack_timer = 2.4
				b.lunge_t = 0.25
				var base := (player.position - b.position).angle()
				for i in range(-2, 3):
					var pos := b.position + Vector2(0, b.hpx * 0.25)
					_fire(_make_proj("acid", pos, base + float(i) * 0.17, 235.0, 8.0, 15.0, 3.4, "#7fd820"))
			b.shock_timer -= dt
			if b.shock_timer <= 0.0:
				b.shock_timer = 8.5
				var p := EProj.new()
				p.type = "shock"
				p.pos = b.position
				p.radius = 24.0
				p.speed = 240.0
				p.max_radius = 1150.0
				p.dmg = 20.0
				p.life = 6.0
				p.color = Color("#a8f0b0")
				_fire(p)
			b.egg_timer -= dt
			if b.egg_timer <= 0.0:
				b.egg_timer = 6.0
				var alive := metroid_count()
				for i in range(2):
					if alive + i >= 6:
						break
					spawn_metroid(b.position + Vector2(rng.randf_range(-70.0, 70.0), b.hpx * 0.32))
	_apply_giant_visual(b)


func _apply_giant_visual(b: EnemyUnit) -> void:
	# 動感：緩慢呼吸起伏（腳底錨定）＋攻擊前撲＋死亡震動（QUEEN不呼吸，只震動）
	var spr := b.spr
	if spr == null:
		return
	var breathe := 1.0 if b.is_final_boss else 1.0 + sin(b.phase * 0.45) * 0.016
	spr.scale.y = b.sprite_scale * breathe
	var lunge := 0.0
	if b.lunge_t > 0.0:
		lunge = sin((0.25 - b.lunge_t) / 0.25 * PI) * b.wpx * 0.045
	spr.position.x = b.shake_x + (lunge if b.face_right else -lunge)
	spr.position.y = b.shake_y - b.hpx * (breathe - 1.0) / 2.0


func _update_projectiles(dt: float) -> void:
	for i in range(enemy_projectiles.size() - 1, -1, -1):
		var p := enemy_projectiles[i]
		p.age += dt
		p.life -= dt
		if p.type == "shock":
			# 擴張衝擊波：環通過玩家時判定一次傷害
			p.radius += p.speed * dt
			if p.life <= 0.0 or p.radius >= p.max_radius:
				enemy_projectiles.remove_at(i)
				continue
			var d := player.position.distance_to(p.pos)
			if not p.hit_done and absf(d - p.radius) < 16.0 and player.invul <= 0.0:
				player.hurt(p.dmg)
				p.hit_done = true
				fx.spawn_burst(player.position, Color("#ff5b5b"), 10, 120.0, 0.35)
			continue
		if p.gravity > 0.0:
			p.vel.y += p.gravity * dt
		p.pos += p.vel * dt
		if p.life <= 0.0 or p.pos.x < -30.0 or p.pos.x > Game.W + 30.0 or p.pos.y < -60.0 or p.pos.y > Game.H + 30.0:
			enemy_projectiles.remove_at(i)
			continue
		var rr := p.r + 8.0
		if player.invul <= 0.0 and p.pos.distance_squared_to(player.position) < rr * rr:
			player.hurt(p.dmg)
			fx.spawn_burst(player.position, Color("#ff5b5b"), 10, 120.0, 0.35)
			enemy_projectiles.remove_at(i)


func _draw() -> void:
	for p in enemy_projectiles:
		match p.type:
			"spike":
				draw_set_transform(p.pos, p.vel.angle(), Vector2.ONE)
				draw_colored_polygon(PackedVector2Array([Vector2(10, 0), Vector2(-7, -4), Vector2(-7, 4)]), p.color)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"rock":
				draw_set_transform(p.pos, p.age * 3.0, Vector2.ONE)
				draw_colored_polygon(PackedVector2Array([
					Vector2(-p.r, -p.r * 0.5), Vector2(0, -p.r), Vector2(p.r, -p.r * 0.4),
					Vector2(p.r * 0.8, p.r * 0.7), Vector2(-p.r * 0.6, p.r)]), p.color)
				draw_rect(Rect2(-p.r * 0.4, -p.r * 0.3, p.r * 0.7, p.r * 0.5), Color(0, 0, 0, 0.25))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"ghost":
				var ga := 0.75 + sin(p.age * 10.0) * 0.2
				draw_circle(p.pos, p.r, Color(p.color.r, p.color.g, p.color.b, ga))
				draw_circle(p.pos, p.r * 0.35, Color(1, 1, 1, 0.8))
			"acid":
				var pr := p.r * (1.0 + sin(p.age * 14.0) * 0.15)
				draw_circle(p.pos, pr, Color(p.color.r, p.color.g, p.color.b, 0.92))
				draw_circle(p.pos + Vector2(0, -p.r * 0.25), p.r * 0.4, Color("#d8ff85"))
			"shock":
				var sa := clampf(p.life / 6.0, 0.25, 0.8)
				if p.radius > 4.0:
					draw_arc(p.pos, p.radius, 0.0, TAU, 96, Color(p.color.r, p.color.g, p.color.b, sa), 5.0)
					draw_arc(p.pos, p.radius - 4.0, 0.0, TAU, 96, Color(1, 1, 1, sa), 2.0)
			_:   # fire
				var flick := 1.0 + sin(p.age * 22.0) * 0.25
				draw_circle(p.pos, p.r * flick, p.color)
				draw_circle(p.pos, p.r * 0.45 * flick, Color("#ffe27a"))
