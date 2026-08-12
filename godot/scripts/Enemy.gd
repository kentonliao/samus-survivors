extends Node2D
class_name EnemyUnit
## 雜兵資料容器：行為由 Game.gd 中央迴圈驅動（HTML版同構）

var hp := 10.0
var max_hp := 10.0
var dmg := 5.0
var spd := 60.0
var radius := 12.0
var flyer := false
var dash := false
var explode := false
var elite := false
var phase := 0.0
var dash_timer := 2.0
var hit_flash := 0.0
var spr: Sprite2D
