extends Node2D
## 薩姆斯：移動＋跑步動畫（M1）
## 流暢度修正：改用 _process（每渲染幀更新，等同 HTML 版 rAF 方式）。
## 遊戲不用物理引擎碰撞（沿用 HTML 版的手動距離判定），所以不需要 _physics_process。

const SPEED := 190.0
const ARENA_MIN := Vector2(24, 24)
const ARENA_MAX := Vector2(960 - 24, 600 - 24)

var suit := "power"  # power / varia / gravity / hyper（之後由進化數驅動）
var facing := 1

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

	if dir != Vector2.ZERO:
		position += dir.normalized() * SPEED * delta
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
