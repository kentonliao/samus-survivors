extends CharacterBody2D
## 薩姆斯：移動＋跑步動畫（M1）
## 對應 HTML 版：baseSpeed 190、面向翻轉、站姿呼吸/跑步10幀

const SPEED := 190.0
const ARENA := Rect2(24, 24, 960 - 48, 600 - 48)

var suit := "power"  # power / varia / gravity / hyper（之後由進化數驅動）

@onready var anim: AnimatedSprite2D = $Anim

func _ready() -> void:
	_build_frames()
	anim.play("idle")

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

func _physics_process(_delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		dir.x += 1
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		dir.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		dir.y += 1

	velocity = dir.normalized() * SPEED
	move_and_slide()
	position = position.clamp(ARENA.position, ARENA.end)

	if dir != Vector2.ZERO:
		if anim.animation != "run":
			anim.play("run")
			anim.scale = Vector2(1.22, 1.22)  # 跑步幀37列，對齊站姿高度
		if dir.x != 0:
			anim.flip_h = dir.x < 0
	else:
		if anim.animation != "idle":
			anim.play("idle")
			anim.scale = Vector2(1.05, 1.05)
		# 待機呼吸（squash & stretch，腳底錨定由 offset 處理）
	if anim.animation == "idle":
		var breathe := 1.0 + sin(Time.get_ticks_msec() / 1000.0 * 2.2) * 0.035
		anim.scale.y = 1.05 * breathe
