extends Node2D
class_name EnemyUnit
## 雜兵/頭目資料容器：行為由 Game.gd / BossSystem.gd 中央迴圈驅動（HTML版同構）

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
var dead := false          # 先標記再移除：防自爆連鎖無限遞迴（HTML v0.9教訓）
var speed_mult := 1.0      # 冰凍光束減速
var slow_timer := 0.0
var frozen_timer := 0.0    # 絕對零度凍結
var freeze_cd := 0.0       # 巨型頭目防永凍冷卻
var drain := false         # Metroid幼體：接觸吸血
var spr: Sprite2D

# ---- 巨型頭目欄位（M4，非頭目維持預設值） ----
var is_boss := false
var giant := false
var is_final_boss := false
var boss_name := ""
var side := ""             # left / right / top
var entering := false      # 進場中（無敵）
var target_pos := Vector2.ZERO
var sprite_scale := 1.0
var wpx := 0.0             # 畫面上的寬高（縮放後）
var hpx := 0.0
var face_right := false    # 素材面向左；左側登場時翻面
var base_x := 0.0
var base_y := 0.0
var alpha := 1.0           # Phantoon 淡出/死亡淡出
var dying := 0.0           # >0 死亡演出倒數（無敵、連環爆炸）
var death_fx_t := 0.0
var lunge_t := 0.0         # 攻擊前撲
var attack_timer := 0.0
var pattern_t := 0.0
var rock_timer := 0.0      # KRAID 落石
var tp_timer := 0.0        # PHANTOON 瞬移
var boss_dash_timer := 0.0 # RIDLEY 俯衝計時
var dash_phase := ""       # "" / telegraph / dash
var dash_t := 0.0
var dash_y := 0.0
var dash_vx := 0.0
var shock_timer := 0.0     # QUEEN 衝擊波
var egg_timer := 0.0       # QUEEN 產卵
var shake_x := 0.0
var shake_y := 0.0
