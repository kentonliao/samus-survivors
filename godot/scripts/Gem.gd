extends Node2D
class_name GemPickup
## 經驗晶石：暖金鑽石+暗描邊+白芯；整合結晶=紅八芒星（對應HTML v1.8視覺）

var value := 2.0
var radius := 5.0
var consolidator := false
var vx := 0.0
var vy := 0.0
var phase := 0.0

func setup(v: float, r: float, consol: bool) -> void:
	value = v
	radius = r
	consolidator = consol
	queue_redraw()

func _draw() -> void:
	if consolidator:
		var pts: PackedVector2Array = []
		for i in range(8):
			var rad := (radius if i % 2 == 0 else radius * 0.55) + 2.0
			var a := PI / 4.0 * i
			pts.append(Vector2(cos(a), sin(a)) * rad)
		draw_colored_polygon(pts, Color(0.03, 0.04, 0.055, 0.7))
		pts = []
		for i in range(8):
			var rad := radius if i % 2 == 0 else radius * 0.55
			var a := PI / 4.0 * i
			pts.append(Vector2(cos(a), sin(a)) * rad)
		draw_colored_polygon(pts, Color("#ff2e4d"))
		draw_circle(Vector2.ZERO, radius * 0.3, Color.WHITE)
	else:
		var s := radius
		var col := Color("#ffe27a") if value > 2.0 else Color("#ffb347")
		var dia := PackedVector2Array([Vector2(0, -s-1.5), Vector2(s+1.5, 0), Vector2(0, s+1.5), Vector2(-s-1.5, 0)])
		draw_colored_polygon(dia, Color(0.03, 0.04, 0.055, 0.75))
		dia = PackedVector2Array([Vector2(0, -s), Vector2(s, 0), Vector2(0, s), Vector2(-s, 0)])
		draw_colored_polygon(dia, col)
		var c := s * 0.45
		dia = PackedVector2Array([Vector2(0, -c), Vector2(c, 0), Vector2(0, c), Vector2(-c, 0)])
		draw_colored_polygon(dia, Color(1, 1, 1, 0.9))
