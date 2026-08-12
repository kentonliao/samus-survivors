class_name PlayerUnit
extends Node2D
## 薩姆斯：移動＋跑步動畫（M1）＋受擊/減傷/備用能量槽＋動力服切換（M3）
## 流暢度修正：改用 _process（每渲染幀更新，等同 HTML 版 rAF 方式）。
## 遊戲不用物理引擎碰撞（沿用 HTML 版的手動距離判定），所以不需要 _physics_process。

signal reserve_triggered   # 備用能量槽發動（Game 接去放粒子特效）

const ARENA_MIN := Vector2(24, 24)
const ARENA_MAX := Vector2(960 - 24, 540 - 24)

var speed := 190.0
var hp := 100.0
var max_hp := 100.0
var invul := 0.0
var suit := "power"  # power / varia / gravity / hyper（由進化數驅動，見 Game._check_suit_tier）
var facing := 1
var last_move_angle := 0.0   # 波動光束發射方向（跟隨最後移動方向）
var dmg_reduction := 0.0     # 動力服減傷（每幀由 Game 依 mods 同步）
var reserve_charges := 0     # 備用能量槽次數
var reserve_heal_pct := 0.3
var sfx: Sfx = null          # 受傷音效（Game 於 _ready 注入）


func hurt(dmg: float) -> void:
	if invul > 0.0:
		return
	if sfx != null:
		sfx.play("hurt")
	hp -= dmg * (1.0 - dmg_reduction)
	invul = 0.6
	if hp <= 0.0 and reserve_charges > 0:
		# 備用能量槽：瀕死觸發回復（HTML applyDamageToPlayer 同構）
		reserve_charges -= 1
		hp = max_hp * reserve_heal_pct
		invul = 1.2
		reserve_triggered.emit()


@onready var anim: AnimatedSprite2D = $Anim


func _ready() -> void:
	_build_frames()
	anim.play("idle")
	anim.scale = Vector2(1.05, 1.05)


func _build_frames() -> void:
	var frames := SpriteFrames.new()
	frames.add_animation("idle")
	frames.set_animation_speed("idle", 1)
	frames.add_frame("idle", load("res://assets/samus_idle_%s.png" % suit))
	frames.add_animation("run")
	frames.set_animation_speed("run", 15)
	frames.set_animation_loop("run", true)
	for i in range(10):
		frames.add_frame("run", load("res://assets/samus_run_%s_%d.png" % [suit, i]))
	anim.sprite_frames = frames


func set_suit(tier: String) -> void:
	suit = tier
	var current := anim.animation
	_build_frames()
	anim.play(current)


func _process(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		dir.x += 1
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		dir.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		dir.y += 1

	if invul > 0.0:
		invul -= delta
		anim.visible = int(Time.get_ticks_msec() / 50.0) % 2 == 0  # 受擊閃爍
	else:
		anim.visible = true

	if dir != Vector2.ZERO:
		var ndir := dir.normalized()
		last_move_angle = ndir.angle()
		position += ndir * speed * delta
		position = position.clamp(ARENA_MIN, ARENA_MAX)
		if dir.x != 0:
			facing = 1 if dir.x > 0 else -1
			anim.flip_h = facing < 0
		if anim.animation != "run":
			anim.play("run")
			anim.scale = Vector2(1.22, 1.22)  # 跑步幀37列，對齊站姿高度
	else:
		if anim.animation != "idle":
			anim.play("idle")
			anim.scale = Vector2(1.05, 1.05)
		# 待機呼吸（squash & stretch）
		var breathe := 1.0 + sin(Time.get_ticks_msec() / 1000.0 * 2.2) * 0.035
		anim.scale.y = 1.05 * breathe
