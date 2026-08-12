class_name WeaponSystem
extends Node2D
## M3 武器系統：12武器＋8被動＋12進化（index.html 逐一同構移植）
## 行為類別：projectile / directional / radial_burst / beam_continuous / homing /
##           placed_bomb / delayed_nova / orbit_aura / orbit_field / chain / mine / pulse
## 彈幕等實體存於純資料陣列，由 tick() 中央驅動、_draw() 統一繪製（等同 canvas 疊繪）。
## 地面物（地雷/炸彈/核彈預警）畫在 GroundLayer 子節點（有效z=0，位於敵人之下）。

const MAX_PROJECTILES := 420
const PRISM_COLORS: Array[String] = ["#ffe14f", "#ff9a4f", "#ff5f8a", "#8a7dff", "#4fd8ff"]


class WeaponInst:
	var id := ""
	var level := 1
	var evolved := false
	var timer := 0.0
	var spin_angle := 0.0            # cascadeBeam 自動旋轉掃射
	var burst_timer := 1.5           # shinesparkFury 週期爆發
	var beam_target: EnemyUnit = null
	var draw_radius := 0.0           # orbit 視覺半徑快取（draw 不重算暴擊）


class PassiveInst:
	var id := ""
	var level := 1


class Mods:
	var suit_dmg_mult := 1.0
	var suit_dmg_reduction := 0.0
	var magnet_mult := 1.0
	var cd_mult := 1.0
	var pierce_bonus := 0
	var count_bonus := 0
	var crit_chance := 0.0
	var speed_mult := 1.0
	var evo_count := 0


class Stats:
	var damage := 0.0
	var dps := 0.0
	var cooldown := 0.0
	var count := 0.0
	var pierce := 0.0
	var speed := 0.0
	var splash := 0.0
	var drop_interval := 0.0
	var blast_radius := 0.0
	var fuse_time := 0.0
	var radius := 0.0
	var delay := 0.0
	var chain_count := 0.0
	var range_ := 0.0
	var max_mines := 0.0
	var trigger_radius := 0.0


class Proj:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var dmg := 0.0
	var r := 4.0
	var pierce := 1
	var life := 1.6
	var age := 0.0
	var color := Color.WHITE
	var wavy := false
	var shape := "bolt"
	var evolved := false
	var weapon_id := ""
	var slow := 0.0
	var freeze := false
	var homing := false
	var target: EnemyUnit = null
	var splash := 0.0
	var is_missile := false


class Bomb:
	var pos := Vector2.ZERO
	var fuse := 0.8
	var blast_radius := 42.0
	var dmg := 0.0
	var weapon_id := ""
	var evolved := false


class Nova:
	var pos := Vector2.ZERO
	var delay := 0.6
	var total_delay := 0.6
	var dmg := 0.0
	var radius := 110.0
	var weapon_id := ""
	var evolved := false


class MineUnit:
	var pos := Vector2.ZERO
	var dmg := 0.0
	var trigger_radius := 42.0
	var blast_radius := 56.0
	var weapon_id := ""
	var evolved := false
	var pulling := false
	var pull_timer := 0.0
	var life := 9.0


class PulseRing:
	var pos := Vector2.ZERO
	var radius := 0.0
	var max_radius := 140.0
	var dmg := 0.0
	var speed := 0.0
	var hit_set := {}
	var weapon_id := ""
	var evolved := false
	var gen := 0


class LightFX:
	var segments := PackedVector2Array()   # 平坦存放 from,to,from,to...
	var life := 0.5
	var max_life := 0.5
	var color := Color.WHITE
	var evolved := false


class GroundLayer:
	extends Node2D
	var sys: WeaponSystem
	func _draw() -> void:
		if sys != null:
			sys.draw_ground(self)


var game: Game
var player: PlayerUnit
var fx: FxLayer
var sfx: Sfx
var rng := RandomNumberGenerator.new()

var weapons: Array[WeaponInst] = []
var passives: Array[PassiveInst] = []
var banned := {}   # id -> true：玩家「排除」的項目，本場不再出現在卡池
var mods := Mods.new()

var projectiles: Array[Proj] = []
var bombs: Array[Bomb] = []
var novas: Array[Nova] = []
var mines: Array[MineUnit] = []
var pulses: Array[PulseRing] = []
var lightning: Array[LightFX] = []

var ground: GroundLayer
var _sort_from := Vector2.ZERO


func _ready() -> void:
	rng.randomize()
	ground = GroundLayer.new()
	ground.sys = self
	ground.z_index = -5   # 相對本層 z=5 → 有效 z=0：畫在背景之上、敵人之下
	add_child(ground)


# ---------- 武器/被動 管理 ----------
func add_weapon(id: String) -> void:
	var w := WeaponInst.new()
	w.id = id
	weapons.append(w)


func get_weapon(id: String) -> WeaponInst:
	for w in weapons:
		if w.id == id:
			return w
	return null


func get_passive(id: String) -> PassiveInst:
	for p in passives:
		if p.id == id:
			return p
	return null


func passive_level(id: String) -> int:
	var p := get_passive(id)
	return 0 if p == null else p.level


func evolved_count() -> int:
	var n := 0
	for w in weapons:
		if w.evolved:
			n += 1
	return n


func refresh_mods() -> void:
	var m := Mods.new()
	m.evo_count = evolved_count()
	m.suit_dmg_mult = 1.15 if m.evo_count >= 6 else 1.0
	if m.evo_count >= 6:
		m.suit_dmg_reduction = 0.30
	elif m.evo_count >= 4:
		m.suit_dmg_reduction = 0.20
	elif m.evo_count >= 2:
		m.suit_dmg_reduction = 0.10
	var m_lv := passive_level("magnetCore")
	m.magnet_mult = (1.0 + 0.2 + float(m_lv - 1) * 0.15) if m_lv > 0 else 1.0
	var o_lv := passive_level("overloadCapacitor")
	m.cd_mult = maxf(0.4, 1.0 - (0.08 + float(o_lv - 1) * 0.06)) if o_lv > 0 else 1.0
	m.pierce_bonus = passive_level("piercingCore")
	m.count_bonus = passive_level("multiLockModule")
	var c_lv := passive_level("criticalSensor")
	m.crit_chance = minf(0.7, 0.08 + float(c_lv - 1) * 0.06) if c_lv > 0 else 0.0
	var b_lv := passive_level("boosterCoil")
	m.speed_mult = 1.0 + (0.08 + float(b_lv - 1) * 0.06 if b_lv > 0 else 0.0)
	mods = m


# ---------- 升級抽卡 ----------
func build_card_pool() -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	var weapon_full := weapons.size() >= 6
	for id in WeaponData.WEAPON_ORDER:
		if banned.has(id):
			continue
		var owned := get_weapon(id)
		if owned == null:
			if not weapon_full:
				pool.append({"kind": "newWeapon", "id": id})
		elif not owned.evolved and owned.level < 9:
			pool.append({"kind": "upgradeWeapon", "id": id})
	var passive_full := passives.size() >= 6
	for id in WeaponData.PASSIVE_ORDER:
		if banned.has(id):
			continue
		var owned := get_passive(id)
		if owned == null:
			if not passive_full:
				pool.append({"kind": "newPassive", "id": id})
		elif owned.level < 6:
			pool.append({"kind": "upgradePassive", "id": id})
	return pool


func apply_card(card: Dictionary) -> void:
	var kind: String = card["kind"]
	var id: String = card["id"]
	match kind:
		"newWeapon":
			add_weapon(id)
		"upgradeWeapon":
			var w := get_weapon(id)
			w.level = mini(9, w.level + 1)
		"newPassive":
			var p := PassiveInst.new()
			p.id = id
			passives.append(p)
			_apply_passive_immediate(id, 1)
		"upgradePassive":
			var p := get_passive(id)
			p.level = mini(6, p.level + 1)
			_apply_passive_immediate(id, p.level)


func _apply_passive_immediate(id: String, lvl: int) -> void:
	if id == "energyTank":
		player.max_hp += 20.0
		player.hp = minf(player.max_hp, player.hp + 20.0)
	if id == "reserveTank":
		player.reserve_charges = lvl
		player.reserve_heal_pct = 0.3 + float(lvl) * 0.05


func check_evolutions() -> Array[WeaponInst]:
	var newly: Array[WeaponInst] = []
	for w in weapons:
		if w.evolved:
			continue
		var def: Dictionary = WeaponData.WEAPONS[w.id]
		var partner := get_passive(String(def["evoPartner"]))
		if w.level >= 9 and partner != null and partner.level >= 6:
			w.evolved = true
			w.beam_target = null   # 類別切換（如電漿→力場）殘留光束線的舊bug防範
			newly.append(w)
	return newly


func card_label(card: Dictionary) -> Dictionary:
	# 回傳卡片顯示資訊：icon/name/lv_line/desc/is_new（Hud 裝備框卡片用）
	var kind: String = card["kind"]
	var id: String = card["id"]
	if kind == "newWeapon" or kind == "upgradeWeapon":
		var def: Dictionary = WeaponData.WEAPONS[id]
		var evo: Dictionary = def["evo"]
		var partner_id: String = def["evoPartner"]
		var pdef: Dictionary = WeaponData.PASSIVES[partner_id]
		var owned := get_weapon(id)
		var lvl := 0 if owned == null else owned.level
		var lv_line := "【首次獲得】" if kind == "newWeapon" else "Lv.%d → %d / 9" % [lvl, lvl + 1]
		var desc := "進化搭檔：%s(%d/6)\n→ %s" % [String(pdef["name"]), passive_level(partner_id), String(evo["name"])]
		return {"icon": id, "name": String(def["name"]), "lv_line": lv_line, "desc": desc, "is_new": kind == "newWeapon"}
	else:
		var pdef: Dictionary = WeaponData.PASSIVES[id]
		var owned := get_passive(id)
		var lvl := 0 if owned == null else owned.level
		var lv_line := "【首次獲得】" if kind == "newPassive" else "Lv.%d → %d / 6" % [lvl, lvl + 1]
		var wnames := PackedStringArray()
		for wid in WeaponData.WEAPON_ORDER:
			var wdef: Dictionary = WeaponData.WEAPONS[wid]
			if String(wdef["evoPartner"]) == id:
				wnames.append(String(wdef["name"]))
		var desc: String = String(pdef["desc"])
		if wnames.size() > 0:
			desc += "\n可進化：" + "、".join(wnames)
		return {"icon": id, "name": String(pdef["name"]), "lv_line": lv_line, "desc": desc, "is_new": kind == "newPassive"}


# ---------- 數值計算（HTML weaponStats 同構）----------
func weapon_stats(w: WeaponInst) -> Stats:
	var def: Dictionary = WeaponData.WEAPONS[w.id]
	var lv := float(w.level)
	var cat: String = def["category"]
	var s := Stats.new()
	match cat:
		"projectile", "directional":
			s.damage = WeaponData.num(def, "baseDmg") + WeaponData.num(def, "dmgPerLv") * (lv - 1.0)
			s.cooldown = maxf(WeaponData.num(def, "minCd", 0.12), WeaponData.num(def, "baseCd") + WeaponData.num(def, "cdPerLv") * (lv - 1.0))
			var every := WeaponData.num(def, "countEvery", 3.0 if cat == "projectile" else 1.0)
			s.count = WeaponData.num(def, "baseCount", 1.0) + floorf((lv - 1.0) / every)
			s.pierce = WeaponData.num(def, "basePierce", 1.0)
			s.speed = WeaponData.num(def, "speed", 500.0)
		"beam_continuous":
			s.dps = WeaponData.num(def, "baseDmg") + WeaponData.num(def, "dmgPerLv") * (lv - 1.0)
		"homing":
			s.damage = WeaponData.num(def, "baseDmg") + WeaponData.num(def, "dmgPerLv") * (lv - 1.0)
			s.cooldown = maxf(WeaponData.num(def, "minCd", 0.35), WeaponData.num(def, "baseCd") + WeaponData.num(def, "cdPerLv") * (lv - 1.0))
			s.count = minf(WeaponData.num(def, "maxCount", 4.0), WeaponData.num(def, "baseCount", 1.0) + floorf((lv - 1.0) / WeaponData.num(def, "countEvery", 2.0)))
			s.splash = WeaponData.num(def, "splashRadius")
		"placed_bomb":
			s.damage = WeaponData.num(def, "baseDmg") + WeaponData.num(def, "dmgPerLv") * (lv - 1.0)
			s.drop_interval = maxf(0.2, WeaponData.num(def, "dropInterval") + WeaponData.num(def, "dropIntervalPerLv") * (lv - 1.0))
			s.blast_radius = WeaponData.num(def, "blastRadius")
			s.fuse_time = WeaponData.num(def, "fuseTime")
		"delayed_nova":
			s.damage = WeaponData.num(def, "baseDmg") + WeaponData.num(def, "dmgPerLv") * (lv - 1.0)
			s.cooldown = maxf(WeaponData.num(def, "minCooldown", 1.5), WeaponData.num(def, "cooldown") + WeaponData.num(def, "cdPerLv") * (lv - 1.0))
			s.radius = WeaponData.num(def, "radius") + WeaponData.num(def, "radiusPerLv") * (lv - 1.0)
			s.delay = WeaponData.num(def, "delay")
			s.count = 1.0 + floorf((lv - 1.0) / 3.0)
		"orbit_aura":
			s.dps = WeaponData.num(def, "baseDmg") + WeaponData.num(def, "dmgPerLv") * (lv - 1.0)
			s.radius = WeaponData.num(def, "radius") + WeaponData.num(def, "radiusPerLv") * (lv - 1.0)
		"chain":
			s.damage = WeaponData.num(def, "baseDmg") + WeaponData.num(def, "dmgPerLv") * (lv - 1.0)
			s.cooldown = maxf(0.25, WeaponData.num(def, "baseCd") + WeaponData.num(def, "cdPerLv") * (lv - 1.0))
			s.chain_count = WeaponData.num(def, "chainCount", 2.0) + floorf((lv - 1.0) / WeaponData.num(def, "chainCountEvery", 3.0))
			s.range_ = WeaponData.num(def, "chainRange")
		"mine":
			s.damage = WeaponData.num(def, "baseDmg") + WeaponData.num(def, "dmgPerLv") * (lv - 1.0)
			s.drop_interval = maxf(0.4, WeaponData.num(def, "dropInterval") + WeaponData.num(def, "dropIntervalPerLv") * (lv - 1.0))
			s.max_mines = WeaponData.num(def, "maxMines", 3.0) + floorf((lv - 1.0) / WeaponData.num(def, "maxMinesEvery", 3.0))
			s.trigger_radius = WeaponData.num(def, "triggerRadius")
			s.blast_radius = WeaponData.num(def, "blastRadius")
		"pulse":
			s.damage = WeaponData.num(def, "baseDmg") + WeaponData.num(def, "dmgPerLv") * (lv - 1.0)
			s.cooldown = maxf(WeaponData.num(def, "minCooldown", 0.6), WeaponData.num(def, "cooldown") + WeaponData.num(def, "cdPerLv") * (lv - 1.0))
			s.radius = WeaponData.num(def, "maxRadius") + WeaponData.num(def, "radiusPerLv") * (lv - 1.0)
	# 被動加成（HTML同順序）
	if s.cooldown > 0.0:
		s.cooldown *= mods.cd_mult
	if s.drop_interval > 0.0:
		s.drop_interval *= mods.cd_mult
	if s.pierce > 0.0:
		s.pierce += float(mods.pierce_bonus)
	if s.count > 0.0:
		s.count += float(mods.count_bonus)
	if s.chain_count > 0.0:
		s.chain_count += float(mods.count_bonus)
	if s.max_mines > 0.0:
		s.max_mines += float(mods.count_bonus / 2)
	if s.damage > 0.0:
		s.damage *= mods.suit_dmg_mult
	if s.dps > 0.0:
		s.dps *= mods.suit_dmg_mult
	# 進化加成
	if w.evolved:
		var evo: Dictionary = def["evo"]
		var dmg_mult := WeaponData.num(evo, "dmgMult")
		if dmg_mult > 0.0:
			if s.damage > 0.0:
				s.damage *= dmg_mult
			if s.dps > 0.0:
				s.dps *= dmg_mult
		var cd_mult_e := WeaponData.num(evo, "cdMult")
		if cd_mult_e > 0.0 and s.cooldown > 0.0:
			s.cooldown *= cd_mult_e
		if s.pierce > 0.0:
			s.pierce += WeaponData.num(evo, "pierceAdd")
		if s.count > 0.0:
			s.count += WeaponData.num(evo, "countAdd")
		if s.chain_count > 0.0:
			s.chain_count += WeaponData.num(evo, "chainCountAdd")
		if s.splash > 0.0:
			s.splash += WeaponData.num(evo, "splashRadiusAdd")
		if s.radius > 0.0:
			s.radius += WeaponData.num(evo, "radiusAdd")
		if s.blast_radius > 0.0:
			s.blast_radius += WeaponData.num(evo, "blastRadiusAdd")
		if cat == "beam_continuous" and evo.has("radius"):
			s.radius = WeaponData.num(evo, "radius")   # plasmaStorm 力場半徑
		if String(evo.get("category", "")) == "beam_continuous" and s.dps <= 0.0:
			s.dps = (s.damage if s.damage > 0.0 else 10.0) * 2.4   # absoluteZero 換算dps
	if s.damage > 0.0 and rng.randf() < mods.crit_chance:
		s.damage *= 2.0
	return s


func _effective_category(w: WeaponInst) -> String:
	var def: Dictionary = WeaponData.WEAPONS[w.id]
	if w.evolved:
		var evo: Dictionary = def["evo"]
		return String(evo.get("category", def["category"]))
	return String(def["category"])


# ---------- 中央更新 ----------
func tick(dt: float) -> void:
	_update_weapons(dt)
	_update_projectiles(dt)
	_update_bombs(dt)
	_update_novas(dt)
	_update_mines(dt)
	_update_pulses(dt)
	for i in range(lightning.size() - 1, -1, -1):
		lightning[i].life -= dt
		if lightning[i].life <= 0.0:
			lightning.remove_at(i)
	queue_redraw()
	ground.queue_redraw()


func _update_weapons(dt: float) -> void:
	for w in weapons:
		var cat := _effective_category(w)
		if cat == "beam_continuous":
			_tick_continuous_beam(w, weapon_stats(w), dt)
			continue
		if cat == "orbit_field":
			_tick_orbit_field(w, weapon_stats(w), dt)
			continue
		if cat == "orbit_aura":
			_tick_orbit_aura(w, weapon_stats(w), dt)
			continue
		w.timer -= dt
		if w.timer > 0.0:
			continue
		var s := weapon_stats(w)
		match cat:
			"projectile":
				if game.enemies.size() > 0:
					_fire_projectile_volley(w, s)
				w.timer = s.cooldown
			"directional":
				_fire_directional_wave(w, s)
				w.timer = s.cooldown
			"radial_burst":
				_fire_radial_burst(w, s)
				w.timer = s.cooldown
			"homing":
				if game.enemies.size() > 0:
					_fire_homing(w, s)
				w.timer = s.cooldown
			"placed_bomb":
				_drop_bomb(w, s)
				w.timer = s.drop_interval
			"delayed_nova":
				_schedule_nova(w, s)
				w.timer = s.cooldown
			"chain":
				if game.enemies.size() > 0:
					_fire_chain(w, s)
				w.timer = s.cooldown
			"mine":
				_drop_mine(w, s)
				w.timer = s.drop_interval
			"pulse":
				_fire_pulse(w, s)
				w.timer = s.cooldown


func _nearest_enemy(from: Vector2) -> EnemyUnit:
	var best: EnemyUnit = null
	var bd := INF
	for e in game.enemies:
		var d: float = e.position.distance_squared_to(from)
		if d < bd:
			bd = d
			best = e
	return best


func _push(p: Proj) -> void:
	if projectiles.size() >= MAX_PROJECTILES:
		projectiles.pop_front()
	projectiles.append(p)


# ---------- 各類發射 ----------
func _fire_projectile_volley(w: WeaponInst, s: Stats) -> void:
	var def: Dictionary = WeaponData.WEAPONS[w.id]
	var evo: Dictionary = def["evo"]
	var target := _nearest_enemy(player.position)
	if target == null:
		return
	sfx.play("shoot")
	var base_ang := (target.position - player.position).angle()
	var count := maxi(1, roundi(s.count))
	var spread := WeaponData.num(def, "spreadAngle", 0.16)
	for i in range(count):
		var ang := base_ang + (float(i) - float(count - 1) / 2.0) * spread
		var p := Proj.new()
		p.pos = player.position
		p.vel = Vector2.from_angle(ang) * s.speed
		p.dmg = s.damage
		p.pierce = roundi(s.pierce)
		p.life = 1.6
		p.color = Color(String(evo["color"])) if w.evolved else Color(String(def["color"]))
		p.wavy = bool(def.get("wavy", false))
		p.shape = String(def.get("shape", "bolt"))
		p.evolved = w.evolved
		p.weapon_id = w.id
		var slow_base := WeaponData.num(def, "slowBase")
		if slow_base > 0.0:
			p.slow = slow_base + (float(w.level) - 1.0) * WeaponData.num(def, "slowPerLv")
		p.freeze = w.evolved and bool(evo.get("freeze", false))
		_push(p)


func _fire_directional_wave(w: WeaponInst, s: Stats) -> void:
	var def: Dictionary = WeaponData.WEAPONS[w.id]
	var evo: Dictionary = def["evo"]
	var ang: float
	if w.evolved:
		# 進化後（Cascade Beam）不跟隨移動方向，改為自動旋轉掃射
		w.spin_angle += WeaponData.num(evo, "spinPerShot", 0.7)
		ang = w.spin_angle
	else:
		ang = player.last_move_angle
	var count := maxi(1, roundi(s.count))
	var perp := ang + PI / 2.0
	var spacing := 5.5 if w.evolved else 9.0   # 進化後光束間隔更密
	for i in range(count):
		var off := (float(i) - float(count - 1) / 2.0) * spacing
		var p := Proj.new()
		p.pos = player.position + Vector2.from_angle(perp) * off
		p.vel = Vector2.from_angle(ang) * s.speed
		p.dmg = s.damage
		p.pierce = roundi(s.pierce)
		p.life = 1.3
		p.color = Color(String(evo["color"])) if w.evolved else Color(String(def["color"]))
		p.wavy = true
		p.shape = String(def.get("shape", "ribbon"))
		p.evolved = w.evolved
		p.weapon_id = w.id
		_push(p)


func _fire_radial_burst(w: WeaponInst, s: Stats) -> void:
	sfx.play("shoot")
	var def: Dictionary = WeaponData.WEAPONS[w.id]
	var evo: Dictionary = def["evo"]
	var count := 18 if w.evolved else maxi(1, roundi(s.count) * 3)
	var prism: bool = String(evo.get("id", "")) == "prismaticSpazer"
	for i in range(count):
		var ang := TAU / float(count) * float(i)
		var p := Proj.new()
		p.pos = player.position
		p.vel = Vector2.from_angle(ang) * (s.speed if s.speed > 0.0 else 460.0)
		p.dmg = s.damage
		p.pierce = roundi(s.pierce) if s.pierce > 0.0 else 4
		p.life = 1.1
		p.color = Color(PRISM_COLORS[i % 5]) if prism else Color(String(evo["color"]))
		p.shape = String(def.get("shape", "star"))
		p.evolved = true
		p.weapon_id = w.id
		_push(p)
	fx.spawn_burst(player.position, Color(String(evo["color"])), 12, 90.0, 0.3)


func _tick_continuous_beam(w: WeaponInst, s: Stats, dt: float) -> void:
	var def: Dictionary = WeaponData.WEAPONS[w.id]
	var evo: Dictionary = def["evo"]
	var beam_range := WeaponData.num(def, "range", 260.0)
	if w.evolved and evo.has("range"):
		beam_range = WeaponData.num(evo, "range")
	var target := _nearest_enemy(player.position)
	w.beam_target = null
	if target != null:
		var reach := beam_range + target.radius   # 以身體邊緣計距（HTML v1.9.2教訓）
		if player.position.distance_squared_to(target.position) < reach * reach:
			w.beam_target = target
	if w.beam_target == null:
		return
	game.damage_enemy(w.beam_target, s.dps * dt)
	if not is_instance_valid(w.beam_target) or w.beam_target.dead:
		w.beam_target = null
		return
	if w.evolved and bool(evo.get("freeze", false)):
		# 絕對零度射線：持續凍結目標；巨型頭目走 freeze_cd 防永凍
		var e := w.beam_target
		if e.giant:
			if not (e.freeze_cd > 0.0) and not e.entering:
				e.frozen_timer = 0.8
				e.freeze_cd = 4.0
		else:
			e.frozen_timer = maxf(e.frozen_timer, 0.35)
		if rng.randf() < dt * 14.0:
			var jitter := Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * e.radius * 0.6
			fx.spawn_burst(e.position + jitter, Color("#bfeaff"), 1, 48.0, 0.4)


func _tick_orbit_field(w: WeaponInst, s: Stats, dt: float) -> void:
	w.draw_radius = s.radius
	var r2 := s.radius * s.radius
	for e: EnemyUnit in game.enemies.duplicate():
		if is_instance_valid(e) and not e.dead and player.position.distance_squared_to(e.position) < r2:
			game.damage_enemy(e, s.dps * dt * 0.6)


func _tick_orbit_aura(w: WeaponInst, s: Stats, dt: float) -> void:
	var def: Dictionary = WeaponData.WEAPONS[w.id]
	var evo: Dictionary = def["evo"]
	w.draw_radius = s.radius
	var r2 := s.radius * s.radius
	for e: EnemyUnit in game.enemies.duplicate():
		if is_instance_valid(e) and not e.dead and player.position.distance_squared_to(e.position) < r2:
			game.damage_enemy(e, s.dps * dt)
	if w.evolved and bool(evo.get("pulseBurst", false)):
		w.burst_timer -= dt
		if w.burst_timer <= 0.0:
			w.burst_timer = 1.5
			var rr := s.radius * 1.4
			var rr2 := rr * rr
			for e: EnemyUnit in game.enemies.duplicate():
				if is_instance_valid(e) and not e.dead and player.position.distance_squared_to(e.position) < rr2:
					game.damage_enemy(e, s.dps * 1.2)
			fx.spawn_burst(player.position, Color(String(evo["color"])), 24, 160.0, 0.4)


func _cmp_dist(a: EnemyUnit, b: EnemyUnit) -> bool:
	return a.position.distance_squared_to(_sort_from) < b.position.distance_squared_to(_sort_from)


func _fire_homing(w: WeaponInst, s: Stats) -> void:
	var def: Dictionary = WeaponData.WEAPONS[w.id]
	var evo: Dictionary = def["evo"]
	var count := roundi(s.count)
	sfx.play("missile")
	_sort_from = player.position
	var sorted := game.enemies.duplicate()
	sorted.sort_custom(_cmp_dist)
	var targets: Array = sorted.slice(0, count)
	if targets.size() == 0:
		return
	for i in range(count):
		var target: EnemyUnit = targets[i % targets.size()]
		var spread := (float(i) - float(count - 1) / 2.0) * 0.3 if targets.size() < count else 0.0
		var ang := (target.position - player.position).angle() + spread
		var p := Proj.new()
		p.pos = player.position
		p.vel = Vector2.from_angle(ang) * 300.0
		p.dmg = s.damage
		p.r = 8.0 if w.evolved else 6.0
		p.homing = true
		p.target = target
		p.life = 2.4
		p.splash = s.splash
		p.color = Color(String(evo["color"])) if w.evolved else Color(String(def["color"]))
		p.evolved = w.evolved
		p.is_missile = true
		p.weapon_id = w.id
		_push(p)


func _drop_bomb(w: WeaponInst, s: Stats) -> void:
	var b := Bomb.new()
	b.pos = player.position
	b.fuse = s.fuse_time
	b.blast_radius = s.blast_radius
	b.dmg = s.damage
	b.weapon_id = w.id
	b.evolved = w.evolved
	bombs.append(b)


func _explode_bomb(b: Bomb) -> void:
	sfx.play("explosion")
	game.add_shake(1.0)   # 高頻爆炸，震動壓低
	var def: Dictionary = WeaponData.WEAPONS[b.weapon_id]
	var evo: Dictionary = def["evo"]
	var color := Color(String(evo["color"])) if b.evolved else Color(String(def["color"]))
	fx.spawn_burst(b.pos, color, 26 if b.evolved else 14, 200.0 if b.evolved else 120.0, 0.4)
	fx.add_ring(b.pos, b.blast_radius, color)
	var r2 := b.blast_radius * b.blast_radius
	for e: EnemyUnit in game.enemies.duplicate():
		if is_instance_valid(e) and not e.dead and b.pos.distance_squared_to(e.position) < r2:
			game.damage_enemy(e, b.dmg)
	if b.evolved and bool(evo.get("chainTrigger", false)):
		var rr := b.blast_radius * 1.6
		var rr2 := rr * rr
		for other in bombs:
			if other != b and other.fuse > 0.05 and b.pos.distance_squared_to(other.pos) < rr2:
				other.fuse = 0.05


func _update_bombs(dt: float) -> void:
	for i in range(bombs.size() - 1, -1, -1):
		var b := bombs[i]
		b.fuse -= dt
		if b.fuse <= 0.0:
			bombs.remove_at(i)
			_explode_bomb(b)


func _schedule_nova(w: WeaponInst, s: Stats) -> void:
	var count := maxi(1, roundi(s.count))
	for i in range(count):
		var n := Nova.new()
		if i == 0:
			n.pos = player.position
		else:
			var ang := rng.randf_range(0.0, TAU)
			var d := rng.randf_range(90.0, 240.0)
			n.pos = Vector2(
				clampf(player.position.x + cos(ang) * d, 40.0, Game.W - 40.0),
				clampf(player.position.y + sin(ang) * d, 40.0, Game.H - 40.0))
		n.delay = s.delay + float(i) * 0.12
		n.total_delay = n.delay
		n.dmg = s.damage
		n.radius = s.radius
		n.weapon_id = w.id
		n.evolved = w.evolved
		novas.append(n)


func _update_novas(dt: float) -> void:
	for i in range(novas.size() - 1, -1, -1):
		var n := novas[i]
		n.delay -= dt
		if n.delay > 0.0:
			continue
		novas.remove_at(i)
		sfx.play("explosion")
		# 強力炸彈不震動：Lv高時9連發等於整場狂震，傷眼（玩家回饋移除）
		var def: Dictionary = WeaponData.WEAPONS[n.weapon_id]
		var evo: Dictionary = def["evo"]
		var color := Color(String(evo["color"])) if n.evolved else Color(String(def["color"]))
		fx.spawn_burst(n.pos, color, 40 if n.evolved else 22, 260.0 if n.evolved else 160.0, 0.6)
		fx.add_ring(n.pos, n.radius, color)
		fx.add_ring(n.pos, n.radius * 0.6, Color.WHITE)
		var r2 := n.radius * n.radius
		for e: EnemyUnit in game.enemies.duplicate():
			if is_instance_valid(e) and not e.dead and n.pos.distance_squared_to(e.position) < r2:
				game.damage_enemy(e, n.dmg)
		if n.evolved:
			var heal := WeaponData.num(evo, "healOnDetonate")
			if heal > 0.0:
				player.hp = minf(player.max_hp, player.hp + player.max_hp * heal)


func _fire_chain(w: WeaponInst, s: Stats) -> void:
	var def: Dictionary = WeaponData.WEAPONS[w.id]
	var color := Color.WHITE if w.evolved else Color(String(def["color"]))
	var last := player.position
	var excluded := {}
	var segs := PackedVector2Array()
	for i in range(roundi(s.chain_count)):
		var best: EnemyUnit = null
		var bd := INF
		for e in game.enemies:
			if excluded.has(e):
				continue
			var rr: float = s.range_ + e.radius   # 以身體邊緣計距，巨型頭目才連得到
			var d: float = last.distance_squared_to(e.position)
			if d < bd and d < rr * rr:
				bd = d
				best = e
		if best == null:
			break
		var bpos := best.position
		game.damage_enemy(best, s.damage)
		fx.spawn_burst(bpos, color, 10 if w.evolved else 6, 130.0, 0.3)
		segs.append(last)
		segs.append(bpos)
		excluded[best] = true
		last = bpos
	if segs.size() > 0:
		var l := LightFX.new()
		l.segments = segs
		l.color = color
		l.evolved = w.evolved
		lightning.append(l)
		if w.evolved:
			# 連鎖電網：每個節點留下短暫殘光
			for si in range(1, segs.size(), 2):
				fx.spawn_burst(segs[si], Color("#eaffff"), 3, 40.0, 0.5)


func _drop_mine(w: WeaponInst, s: Stats) -> void:
	var existing := 0
	for m in mines:
		if m.weapon_id == w.id:
			existing += 1
	if existing >= roundi(s.max_mines):
		return
	var ang := rng.randf_range(0.0, TAU)
	var d := rng.randf_range(50.0, 120.0)
	var m := MineUnit.new()
	m.pos = Vector2(
		clampf(player.position.x + cos(ang) * d, 20.0, Game.W - 20.0),
		clampf(player.position.y + sin(ang) * d, 20.0, Game.H - 20.0))
	m.dmg = s.damage
	m.trigger_radius = s.trigger_radius
	m.blast_radius = s.blast_radius
	m.weapon_id = w.id
	m.evolved = w.evolved
	mines.append(m)


func _explode_mine(m: MineUnit) -> void:
	sfx.play("explosion")
	game.add_shake(1.5)   # 高頻爆炸，震動壓低
	var def: Dictionary = WeaponData.WEAPONS[m.weapon_id]
	var evo: Dictionary = def["evo"]
	var color := Color(String(evo["color"])) if m.evolved else Color(String(def["color"]))
	fx.spawn_burst(m.pos, color, 30 if m.evolved else 16, 220.0 if m.evolved else 130.0, 0.5)
	fx.add_ring(m.pos, m.blast_radius, color)
	var r2 := m.blast_radius * m.blast_radius
	for e: EnemyUnit in game.enemies.duplicate():
		if is_instance_valid(e) and not e.dead and m.pos.distance_squared_to(e.position) < r2:
			game.damage_enemy(e, m.dmg)


func _update_mines(dt: float) -> void:
	for i in range(mines.size() - 1, -1, -1):
		var m := mines[i]
		m.life -= dt
		if m.life <= 0.0:
			mines.remove_at(i)
			_explode_mine(m)
			continue
		if not m.pulling:
			var trig2 := m.trigger_radius * m.trigger_radius
			var tripped := false
			for e in game.enemies:
				if m.pos.distance_squared_to(e.position) < trig2:
					tripped = true
					break
			if tripped:
				var def: Dictionary = WeaponData.WEAPONS[m.weapon_id]
				var evo: Dictionary = def["evo"]
				if m.evolved and bool(evo.get("pullEffect", false)):
					m.pulling = true
					m.pull_timer = 0.7
				else:
					mines.remove_at(i)
					_explode_mine(m)
		else:
			# 重力井：先吸聚再引爆
			m.pull_timer -= dt
			var pull_r := m.blast_radius * 2.3
			var pr2 := pull_r * pull_r
			for e in game.enemies:
				var d2: float = m.pos.distance_squared_to(e.position)
				if d2 < pr2:
					var ang := (m.pos - e.position).angle()
					var strength := 260.0 * (1.0 - d2 / pr2 * 0.4)
					e.position += Vector2.from_angle(ang) * strength * dt
					if rng.randf() < 0.3:
						fx.spawn_burst(e.position, Color("#e0c8ff"), 1, 30.0, 0.3)
			if m.pull_timer <= 0.0:
				mines.remove_at(i)
				_explode_mine(m)


func _fire_pulse(w: WeaponInst, s: Stats) -> void:
	var p := PulseRing.new()
	p.pos = player.position
	p.max_radius = s.radius
	p.dmg = s.damage
	p.speed = s.radius / 0.45
	p.weapon_id = w.id
	p.evolved = w.evolved
	pulses.append(p)


func _update_pulses(dt: float) -> void:
	for i in range(pulses.size() - 1, -1, -1):
		var p := pulses[i]
		p.radius += p.speed * dt
		var def: Dictionary = WeaponData.WEAPONS[p.weapon_id]
		var evo: Dictionary = def["evo"]
		var chain_pulse: bool = p.evolved and bool(evo.get("chainPulse", false))
		for e: EnemyUnit in game.enemies.duplicate():
			if not is_instance_valid(e) or e.dead:
				continue
			if p.hit_set.has(e):
				continue
			if p.pos.distance_to(e.position) <= p.radius:
				p.hit_set[e] = true
				var epos := e.position
				game.damage_enemy(e, p.dmg)
				if chain_pulse and p.gen < 1 and rng.randf() < 0.3:
					var q := PulseRing.new()
					q.pos = epos
					q.max_radius = 60.0
					q.dmg = p.dmg * 0.7
					q.speed = 60.0 / 0.3
					q.weapon_id = p.weapon_id
					q.evolved = true
					q.gen = p.gen + 1
					pulses.append(q)
		if p.radius >= p.max_radius:
			pulses.remove_at(i)


func _update_projectiles(dt: float) -> void:
	for i in range(projectiles.size() - 1, -1, -1):
		var p := projectiles[i]
		p.age += dt
		if p.homing:
			if p.target == null or not is_instance_valid(p.target) or p.target.dead:
				p.target = _nearest_enemy(p.pos)
			if p.target != null:
				var ang := (p.target.position - p.pos).angle()
				var spd := p.vel.length()
				if spd <= 0.0:
					spd = 300.0
				var turn := clampf(dt * 6.0, 0.0, 1.0)
				p.vel = p.vel.lerp(Vector2.from_angle(ang) * spd, turn)
		if p.wavy:
			var perp := p.vel.angle() + PI / 2.0
			var wob := sin(p.age * 14.0) * 46.0 * dt
			p.pos += Vector2.from_angle(perp) * wob
		p.pos += p.vel * dt
		p.life -= dt
		if p.evolved and rng.randf() < dt * 26.0:
			fx.spawn_burst(p.pos - p.vel * 0.02, p.color, 1, 30.0, 0.35)
		if p.life <= 0.0 or p.pos.x < -20.0 or p.pos.x > Game.W + 20.0 or p.pos.y < -20.0 or p.pos.y > Game.H + 20.0:
			projectiles.remove_at(i)
			continue
		for j in range(game.enemies.size() - 1, -1, -1):
			var e: EnemyUnit = game.enemies[j]
			var rr: float = p.r + e.radius
			if p.pos.distance_squared_to(e.position) < rr * rr:
				fx.spawn_burst(p.pos, p.color, 5, 90.0, 0.3)
				fx.impact_flash(p.pos, 14.0 if p.evolved else 9.0)
				var was_alive: bool = e.hp > 0.0
				game.damage_enemy(e, p.dmg)
				var alive := is_instance_valid(e) and not e.dead
				if p.slow > 0.0 and was_alive and alive:
					e.speed_mult = maxf(0.25, e.speed_mult - p.slow)
					e.slow_timer = 1.4
				if p.freeze and was_alive and alive:
					if e.giant:
						# 巨型頭目防永凍：短凍結＋免疫冷卻（高射速冰束否則會讓頭目全程不能動）
						if not (e.freeze_cd > 0.0) and not e.entering:
							e.frozen_timer = 0.8
							e.freeze_cd = 4.0
					else:
						e.frozen_timer = 1.0
				if p.is_missile:
					var radius := p.splash if p.splash > 0.0 else 34.0
					fx.spawn_burst(p.pos, p.color, 24 if p.evolved else 10, 200.0 if p.evolved else 120.0, 0.6 if p.evolved else 0.35)
					var sr2 := radius * radius
					for other: EnemyUnit in game.enemies.duplicate():
						if other != e and is_instance_valid(other) and not other.dead and p.pos.distance_squared_to(other.position) < sr2:
							game.damage_enemy(other, p.dmg * 0.5)
					p.pierce = 0
				else:
					p.pierce -= 1
				if p.pierce <= 0:
					projectiles.remove_at(i)
				break


# ---------- 繪製 ----------
func _draw() -> void:
	_draw_pulses()
	_draw_beams()
	_draw_orbits()
	_draw_projectiles()
	_draw_lightning()


func _ca(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)


func _qpoints(p0: Vector2, c: Vector2, p1: Vector2, n: int) -> PackedVector2Array:
	# 二次貝茲取樣（模擬 canvas quadraticCurveTo）
	var pts := PackedVector2Array()
	for i in range(n + 1):
		var t := float(i) / float(n)
		var a := p0.lerp(c, t)
		var b := c.lerp(p1, t)
		pts.append(a.lerp(b, t))
	return pts


func _spike_poly(spikes: int, r_out: float, r_in: float, spin: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(spikes * 2):
		var rad := r_out if i % 2 == 0 else r_in
		var a := PI / float(spikes) * float(i) + spin
		pts.append(Vector2(cos(a), sin(a)) * rad)
	return pts


func _dashed_circle(c: CanvasItem, center: Vector2, radius: float, color: Color, width: float) -> void:
	var segs := 14
	for i in range(segs):
		var a0 := TAU * float(i) / float(segs)
		c.draw_arc(center, radius, a0, a0 + TAU / float(segs) * 0.55, 4, color, width)


func _draw_projectiles() -> void:
	for p in projectiles:
		var ang := p.vel.angle()
		var col := p.color
		if p.evolved:
			draw_set_transform(p.pos, ang, Vector2.ONE)
			draw_circle(Vector2.ZERO, 11.0, _ca(col, 0.3))
		if p.is_missile:
			draw_set_transform(p.pos, ang, Vector2.ONE)
			# 暗描邊彈體＋白亮彈頭＋雙層尾焰
			draw_colored_polygon(PackedVector2Array([Vector2(13, 0), Vector2(-6, -6), Vector2(-3, 0), Vector2(-6, 6)]), Color(0.03, 0.05, 0.06, 0.8))
			draw_colored_polygon(PackedVector2Array([Vector2(11, 0), Vector2(-5, -4.6), Vector2(-2, 0), Vector2(-5, 4.6)]), col)
			draw_rect(Rect2(5, -1.2, 5, 2.4), Color.WHITE)
			var flick := 4.0 + sin(p.age * 40.0) * 3.0
			draw_colored_polygon(PackedVector2Array([Vector2(-5, -3.4), Vector2(-15.0 - flick, 0), Vector2(-5, 3.4)]), Color(1.0, 0.59, 0.2, 0.7))
			draw_colored_polygon(PackedVector2Array([Vector2(-5, -1.6), Vector2(-9.0 - flick * 0.5, 0), Vector2(-5, 1.6)]), Color(1.0, 0.94, 0.71, 0.9))
		elif p.shape == "bolt":
			# 彗星型：亮圓頭＋鋸齒漸細尾（尾緣顫動），放大1.4倍
			draw_set_transform(p.pos, ang, Vector2(1.4, 1.4))
			var j := sin(p.age * 28.0) * 1.6
			var halo := PackedVector2Array([
				Vector2(9, 0), Vector2(4, -5.5), Vector2(-6, -3.2 + j),
				Vector2(-17, j * 0.5), Vector2(-6, 3.2 + j * 0.4), Vector2(4, 5.5)])
			draw_colored_polygon(halo, _ca(col, 0.35))
			var body := PackedVector2Array([
				Vector2(8, 0), Vector2(3.5, -3.6), Vector2(-4, -2.1 + j * 0.5),
				Vector2(-13, j * 0.3), Vector2(-4, 2.1 + j * 0.3), Vector2(3.5, 3.6)])
			draw_colored_polygon(body, col)
			draw_circle(Vector2(4.5, 0), 2.7, Color.WHITE)
			draw_colored_polygon(PackedVector2Array([Vector2(4, -1.5), Vector2(-8, j * 0.2), Vector2(4, 1.5)]), Color.WHITE)
		elif p.shape == "shard":
			draw_set_transform(p.pos, ang, Vector2.ONE)
			draw_colored_polygon(PackedVector2Array([Vector2(13, 0), Vector2(1, -7), Vector2(-10, 0), Vector2(1, 7)]), _ca(col, 0.3))
			draw_colored_polygon(PackedVector2Array([Vector2(10, 0), Vector2(1, -5), Vector2(-8, 0), Vector2(1, 5)]), col)
			draw_colored_polygon(PackedVector2Array([Vector2(7, 0), Vector2(1, -2.4), Vector2(-3, 0), Vector2(1, 2.4)]), Color.WHITE)
		elif p.shape == "ribbon":
			draw_set_transform(p.pos, ang, Vector2.ONE)
			var outer := _qpoints(Vector2(-11, 0), Vector2(-3, -9), Vector2(7, 0), 6)
			outer.append_array(_qpoints(Vector2(7, 0), Vector2(-3, 9), Vector2(-11, 0), 6))
			draw_colored_polygon(outer, _ca(col, 0.32))
			var mid := _qpoints(Vector2(-9, 0), Vector2(-3, -7), Vector2(5, 0), 6)
			mid.append_array(_qpoints(Vector2(5, 0), Vector2(-3, 7), Vector2(-9, 0), 6))
			draw_colored_polygon(mid, col)
			var core := _qpoints(Vector2(-5, 0), Vector2(-2, -3), Vector2(3, 0), 5)
			core.append_array(_qpoints(Vector2(3, 0), Vector2(-2, 3), Vector2(-5, 0), 5))
			draw_colored_polygon(core, Color(1, 1, 1, 0.85))
		elif p.shape == "star":
			draw_set_transform(p.pos, ang + p.age * 8.0, Vector2.ONE)
			draw_colored_polygon(_spike_poly(5, 11.0, 4.4, 0.0), _ca(col, 0.3))
			draw_colored_polygon(_spike_poly(5, 8.0, 3.2, 0.0), col)
			draw_circle(Vector2.ZERO, 2.6, Color.WHITE)
		else:
			draw_set_transform(p.pos, ang, Vector2.ONE)
			draw_rect(Rect2(-7, -2, 14, 4), col)
			draw_rect(Rect2(-4, -1, 10, 2), Color.WHITE)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_beams() -> void:
	for w in weapons:
		if _effective_category(w) != "beam_continuous":
			continue
		var t := w.beam_target
		if t == null or not is_instance_valid(t) or t.dead:
			continue
		var def: Dictionary = WeaponData.WEAPONS[w.id]
		var evo: Dictionary = def["evo"]
		var col := Color(String(evo["color"])) if w.evolved else Color(String(def["color"]))
		var freeze_beam: bool = w.evolved and bool(evo.get("freeze", false))
		if freeze_beam:
			# 絕對零度：加粗三層＋沿射線流動的能量球（輸送感，玩家回饋）
			draw_line(player.position, t.position, _ca(col, 0.28), 15.0)
			draw_line(player.position, t.position, _ca(col, 0.85), 7.5)
			draw_line(player.position, t.position, Color(1, 1, 1, 0.95), 2.6)
			var dirv := t.position - player.position
			var beam_len := dirv.length()
			if beam_len > 1.0:
				var nv := dirv / beam_len
				var spacing := 34.0
				var d := fmod(game.elapsed * 300.0, spacing)
				while d < beam_len:
					var bp := player.position + nv * d
					draw_circle(bp, 5.0, _ca(col, 0.5))
					draw_circle(bp, 2.4, Color(1, 1, 1, 0.9))
					d += spacing
			draw_circle(t.position, 12.0 + sin(game.elapsed * 20.0) * 3.0, _ca(col, 0.5))
			draw_circle(t.position, 4.5, Color(1, 1, 1, 0.95))
		else:
			# 三層光束：寬暈＋色體＋白芯（不用發光濾鏡，透明度分層）
			draw_line(player.position, t.position, _ca(col, 0.3), 9.0)
			draw_line(player.position, t.position, _ca(col, 0.9), 4.0)
			draw_line(player.position, t.position, Color(1, 1, 1, 1), 1.6)
			draw_circle(t.position, 9.0 + sin(game.elapsed * 20.0) * 2.0, _ca(col, 0.5))
			draw_circle(t.position, 3.5, Color(1, 1, 1, 0.95))


func _draw_orbits() -> void:
	for w in weapons:
		var cat := _effective_category(w)
		if cat != "orbit_aura" and cat != "orbit_field":
			continue
		if w.draw_radius <= 0.0:
			continue
		var def: Dictionary = WeaponData.WEAPONS[w.id]
		var evo: Dictionary = def["evo"]
		var col := Color(String(evo["color"])) if w.evolved else Color(String(def["color"]))
		var radius := w.draw_radius
		if cat == "orbit_aura":
			var blades := 5 if w.evolved else 3
			for i in range(blades):
				var a: float = game.elapsed * 5.0 + TAU / float(blades) * float(i)
				var blade := PackedVector2Array([Vector2(4, -3), Vector2(radius, -7), Vector2(radius, 7), Vector2(4, 3)])
				if w.evolved:
					# 刀刃殘影
					draw_set_transform(player.position, a - 0.28, Vector2.ONE)
					draw_colored_polygon(blade, _ca(col, 0.2))
				draw_set_transform(player.position, a, Vector2.ONE)
				draw_colored_polygon(blade, _ca(col, 0.55))
				var tip := PackedVector2Array([Vector2(radius * 0.4, -1.5), Vector2(radius, -3), Vector2(radius, 3), Vector2(radius * 0.4, 1.5)])
				draw_colored_polygon(tip, Color(1, 1, 1, 0.75))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			draw_arc(player.position, radius, 0.0, TAU, 48, _ca(col, 0.28), 1.0)
		else:
			var blobs := 8 if w.evolved else 6
			for i in range(blobs):
				var a: float = game.elapsed * 3.0 + TAU / float(blobs) * float(i)
				var bpos := player.position + Vector2.from_angle(a) * radius
				draw_circle(bpos, 10.0 if w.evolved else 8.0, _ca(col, 0.65))
				draw_circle(bpos, 4.0 if w.evolved else 3.0, Color(1, 1, 1, 0.9))
			if w.evolved:
				# 風暴旋轉電弧：外圈＋內圈反向（HTML 2897-2900 同構）
				draw_arc(player.position, radius, game.elapsed * 3.0, game.elapsed * 3.0 + PI * 1.15, 32, _ca(col, 0.35), 3.0)
				draw_arc(player.position, radius * 0.72, -game.elapsed * 4.0, -game.elapsed * 4.0 + PI * 0.9, 24, _ca(col, 0.35), 3.0)
			# 力場半透明底盤（HTML 2902-2903：讓力場有「範圍實體感」而非只有外框）
			draw_circle(player.position, radius, _ca(col, 0.1))


func _draw_lightning() -> void:
	for l in lightning:
		var a := clampf(l.life / l.max_life, 0.0, 1.0)
		var si := 0
		var seg_i := 0
		while si + 1 < l.segments.size():
			var from := l.segments[si]
			var to := l.segments[si + 1]
			# 鋸齒閃電：兩個中繼點垂直抖動、隨時間劈啪跳動
			var d := to - from
			var len := d.length()
			if len < 1.0:
				len = 1.0
			var perp := Vector2(-d.y, d.x) / len
			var w1: float = sin(game.elapsed * 42.0 + float(seg_i) * 2.1) * len * 0.09
			var w2: float = sin(game.elapsed * 38.0 + float(seg_i) * 3.7 + 2.0) * len * 0.09
			var pts := PackedVector2Array([from, from + d * 0.33 + perp * w1, from + d * 0.66 + perp * w2, to])
			draw_polyline(pts, _ca(l.color, a), 5.0 if l.evolved else 3.5)
			draw_polyline(pts, Color(1, 1, 1, a), 1.4)
			si += 2
			seg_i += 1


func _draw_pulses() -> void:
	for p in pulses:
		if p.radius < 1.0:
			continue
		var def: Dictionary = WeaponData.WEAPONS[p.weapon_id]
		var evo: Dictionary = def["evo"]
		var col := Color(String(evo["color"])) if p.evolved else Color(String(def["color"]))
		var fade := clampf(1.0 - p.radius / p.max_radius, 0.0, 1.0)
		# 寬暈＋色環＋內側白環 三層
		draw_arc(p.pos, p.radius, 0.0, TAU, 64, _ca(col, fade * 0.35), 7.0)
		draw_arc(p.pos, p.radius, 0.0, TAU, 64, _ca(col, fade * 0.85), 3.0)
		if p.radius > 3.0:
			draw_arc(p.pos, p.radius - 2.5, 0.0, TAU, 64, Color(1, 1, 1, fade * 0.9), 1.2)


func draw_ground(c: CanvasItem) -> void:
	# 地雷
	for m in mines:
		var dash_col := Color(0.878, 0.784, 1.0, 0.4) if m.evolved else Color(1.0, 0.722, 0.188, 0.45)
		_dashed_circle(c, m.pos, m.trigger_radius, dash_col, 1.0)
		if m.pulling:
			for i in range(3):
				var rr: float = m.blast_radius * 0.5 * (1.0 - float(i) * 0.28)
				var a0: float = game.elapsed * 8.0 + float(i)
				c.draw_arc(m.pos, rr, a0, a0 + PI * 1.3, 16, Color(0.878, 0.784, 1.0, 0.5), 1.5)
		var base_r := 9.0 if m.pulling else 6.0
		var spin: float = game.elapsed * 10.0 if m.pulling else 0.0
		var outline := _spike_poly(6, base_r + 1.6, base_r * 0.45 + 1.6, spin)
		var body := _spike_poly(6, base_r, base_r * 0.45, spin)
		for k in range(outline.size()):
			outline[k] += m.pos
		for k in range(body.size()):
			body[k] += m.pos
		c.draw_colored_polygon(outline, Color(0.03, 0.04, 0.055, 0.75))
		var body_col := Color("#e0c8ff") if m.pulling else (Color("#c8a0ff") if m.evolved else Color("#ffb830"))
		c.draw_colored_polygon(body, body_col)
		var lamp := Color.WHITE if sin(game.elapsed * 6.0 + m.pos.x) > 0.0 else Color("#ff5b3d")
		c.draw_circle(m.pos, 2.0, lamp)
	# 炸彈
	for b in bombs:
		var urgency := clampf(1.0 - b.fuse / 0.8, 0.0, 1.0)
		var blink := 8.0 + urgency * 22.0
		var pulse := 1.0 + sin(b.fuse * blink) * 0.22
		var dash_col := Color(1.0, 0.902, 0.627, 0.3) if b.evolved else Color(1.0, 0.812, 0.239, 0.28)
		_dashed_circle(c, b.pos, b.blast_radius, dash_col, 1.0)
		c.draw_circle(b.pos, 8.0, Color(0.165, 0.102, 0.02))
		var core_col: Color
		if sin(b.fuse * blink) > 0.0:
			core_col = Color("#ffe6a0") if b.evolved else Color("#ffcf3d")
		else:
			core_col = Color("#ff5b3d")
		c.draw_circle(b.pos, 5.0 * pulse, core_col)
	# 強力炸彈預警圈
	for n in novas:
		var prog := 1.0 - n.delay / n.total_delay
		if n.radius * prog > 1.0:
			c.draw_arc(n.pos, n.radius * prog, 0.0, TAU, 48, Color(1.0, 0.357, 0.239, 0.5), 3.0)
