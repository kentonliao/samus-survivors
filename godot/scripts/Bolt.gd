extends Node2D
class_name BoltShot
## 力量光束彈幕：彗星型（亮圓頭+鋸齒尾+白芯，對應HTML v1.8.2視覺）

var vx := 0.0
var vy := 0.0
var dmg := 8.0
var pierce := 1
var life := 1.6
var age := 0.0
var col := Color("#dffcff")

func _draw() -> void:
	var j := sin(age * 28.0) * 1.6
	var k := 1.4  # 放大係數（同HTML）
	# 外暈
	var halo := PackedVector2Array([
		Vector2(9, 0) * k, Vector2(4, -5.5) * k, Vector2(-6, -3.2 + j) * k,
		Vector2(-17, j * 0.5) * k, Vector2(-6, 3.2 + j * 0.4) * k, Vector2(4, 5.5) * k])
	draw_colored_polygon(halo, Color(col.r, col.g, col.b, 0.35))
	# 本體
	var body := PackedVector2Array([
		Vector2(8, 0) * k, Vector2(3.5, -3.6) * k, Vector2(-4, -2.1 + j * 0.5) * k,
		Vector2(-13, j * 0.3) * k, Vector2(-4, 2.1 + j * 0.3) * k, Vector2(3.5, 3.6) * k])
	draw_colored_polygon(body, col)
	# 白熱頭
	draw_circle(Vector2(4.5, 0) * k, 2.7 * k, Color.WHITE)
	var core := PackedVector2Array([Vector2(4, -1.5) * k, Vector2(-8, j * 0.2) * k, Vector2(4, 1.5) * k])
	draw_colored_polygon(core, Color.WHITE)
