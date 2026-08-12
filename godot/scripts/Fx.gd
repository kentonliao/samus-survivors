class_name FxLayer
extends Node2D
## 粒子爆發／鋸齒星芒命中閃光／爆風擴張環（HTML particles + blastRings 同構）
## 全部由中央 tick 驅動、單一 _draw 統一繪製；上限裁剪防無限增長（HTML效能守則）

const MAX_PARTICLES := 420


class Particle:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var life := 0.4
	var max_life := 0.4
	var color := Color.WHITE
	var size := 3.0
	var flash := false
	var rot := 0.0


class Ring:
	var pos := Vector2.ZERO
	var radius := 0.0
	var max_radius := 40.0
	var life := 0.35
	var max_life := 0.35
	var color := Color.WHITE


var particles: Array[Particle] = []
var rings: Array[Ring] = []
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()


func spawn_burst(pos: Vector2, color: Color, count: int, speed: float, life: float) -> void:
	while particles.size() + count > MAX_PARTICLES and particles.size() > 0:
		particles.pop_front()
	for i in range(count):
		var p := Particle.new()
		p.pos = pos
		var a := rng.randf_range(0.0, TAU)
		p.vel = Vector2.from_angle(a) * rng.randf_range(speed * 0.3, speed)
		p.life = life
		p.max_life = life
		p.color = color
		p.size = rng.randf_range(2.0, 4.0)
		particles.append(p)


func impact_flash(pos: Vector2, size: float) -> void:
	if particles.size() >= MAX_PARTICLES:
		particles.pop_front()
	var p := Particle.new()
	p.pos = pos
	p.life = 0.13
	p.max_life = 0.13
	p.size = size
	p.flash = true
	p.rot = rng.randf_range(0.0, PI)
	particles.append(p)


func add_ring(pos: Vector2, max_radius: float, color: Color) -> void:
	var r := Ring.new()
	r.pos = pos
	r.max_radius = max_radius
	r.color = color
	rings.append(r)


func tick(dt: float) -> void:
	for i in range(particles.size() - 1, -1, -1):
		var p := particles[i]
		p.pos += p.vel * dt
		p.vel *= 0.94
		p.life -= dt
		if p.life <= 0.0:
			particles.remove_at(i)
	for i in range(rings.size() - 1, -1, -1):
		var r := rings[i]
		r.life -= dt
		r.radius = r.max_radius * (1.0 - maxf(0.0, r.life) / r.max_life)
		if r.life <= 0.0:
			rings.remove_at(i)
	queue_redraw()


func _draw() -> void:
	for p in particles:
		var a := clampf(p.life / p.max_life, 0.0, 1.0)
		if p.flash:
			# 命中閃光：鋸齒四芒星，隨生命縮小（HTML參考圖風格）
			var s := p.size * a
			if s < 0.8:
				continue   # 縮到近零的多邊形會三角化失敗
			var pts := PackedVector2Array()
			var dirs := [
				Vector2(s, 0), Vector2(s * 0.22, -s * 0.22), Vector2(0, -s), Vector2(-s * 0.22, -s * 0.22),
				Vector2(-s, 0), Vector2(-s * 0.22, s * 0.22), Vector2(0, s), Vector2(s * 0.22, s * 0.22),
			]
			for d in dirs:
				pts.append(p.pos + Vector2(d).rotated(p.rot))
			draw_colored_polygon(pts, Color(1, 1, 1, a))
			continue
		var c := Color(p.color.r, p.color.g, p.color.b, a)
		draw_rect(Rect2(p.pos - Vector2(p.size / 2.0, p.size / 2.0), Vector2(p.size, p.size)), c)
	for r in rings:
		var a := clampf(r.life / r.max_life, 0.0, 1.0) * 0.85
		if r.radius > 0.5:
			draw_arc(r.pos, r.radius, 0.0, TAU, 48, Color(r.color.r, r.color.g, r.color.b, a), 4.0)
