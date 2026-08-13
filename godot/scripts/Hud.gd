class_name GameHud
extends CanvasLayer
## M5 SM風格 UI（index.html v1.9/v1.9.1 規格移植）：
## 深色HUD角面板+硬陰影、粉紅能量格/綠色XP格（repeating分段）、圖示槽位列、
## 「裝備框」升級卡片（深色透底+紫光框+標題騎框線+hover橘色啟用態）、
## 公告 overlay（黑底+紫格線；頭目警告=紅底紅格線+閃爍紅面板）、勝敗畫面、
## 變身白閃（動力服專屬）、橫幅。字體用系統預設（像素字型留待後續資產）。

signal card_picked(card: Dictionary)
signal reroll_requested
signal banish_requested(card: Dictionary)
signal menu_action(action: String)   # resume / restart / title（暫停與結算選單共用）

const W := 960.0
const H := 540.0
const C_ORANGE := Color("#e8a020")
const C_ORANGE_HI := Color("#f8d878")
const C_ORANGE_DK := Color("#8a5a10")
const C_PINK := Color("#f070a8")
const C_PINK_DK := Color("#a04070")
const C_GREEN := Color("#58d854")
const C_GREEN_DK := Color("#2a8830")
const C_RED := Color("#e03028")
const C_BLUE := Color("#6888f8")
const C_GOLD := Color("#ffd76a")
const C_TEXT := Color("#dfe8f0")
const C_TEXT_DIM := Color("#9aa4b8")
const C_HP_RED := Color("#ff3b3b")
const C_HP_RED_DK := Color("#8a1010")
const GRID_PURPLE := Color(0.353, 0.176, 0.51, 0.35)
const GRID_RED := Color(0.549, 0.118, 0.118, 0.25)


class SegBar:
	extends Control
	## SM式能量格：彩色方塊+暗縫+黑縫（repeating-linear-gradient 同構）
	var ratio := 1.0
	var seg_w := 9.0
	var dark_w := 2.0
	var gap_w := 2.0
	var col := Color.WHITE
	var col_dark := Color.GRAY
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.02, 0.05))
		var total := size.x * clampf(ratio, 0.0, 1.0)
		var x := 0.0
		while x < total:
			var w1 := minf(seg_w, total - x)
			draw_rect(Rect2(x, 0, w1, size.y), col)
			if x + seg_w < total:
				var w2 := minf(dark_w, total - x - seg_w)
				draw_rect(Rect2(x + seg_w, 0, w2, size.y), col_dark)
			x += seg_w + dark_w + gap_w


class GridPattern:
	extends Control
	## 24px 格線紋（overlay 背景）
	var grid_col := Color.WHITE
	func _draw() -> void:
		var x := 0.0
		while x <= size.x:
			draw_line(Vector2(x, 0), Vector2(x, size.y), grid_col, 1.0)
			x += 24.0
		var y := 0.0
		while y <= size.y:
			draw_line(Vector2(0, y), Vector2(size.x, y), grid_col, 1.0)
			y += 24.0


var hp_num: Label
var hp_bar: SegBar
var timer_label: Label
var lv_label: Label
var xp_bar: SegBar
var suit_label: Label
var slot_rows: Array[HBoxContainer] = []
var banner_label: Label
var banner_time := 0.0
var boss_bar_name: Label
var boss_bar_bg: ColorRect
var boss_bar_fill: ColorRect
var flash_rect: ColorRect
var flash_time := 0.0

var levelup_overlay: Control
var cards_box: HBoxContainer
var card_buttons: Array[Button] = []   # 測試/自動化點卡用
var reroll_btn: Button
var evo_overlay: Control
var evo_icon: TextureRect
var evo_name: Label
var evo_desc: Label
var boss_overlay: Control
var boss_warn: Label
var boss_title: Label
var boss_flavor: Label
var end_overlay: Control
var end_title: Label
var end_stats: Label
var end_hint: Label
var title_overlay: Control
var title_best: Label
var title_hint: Label
var pause_overlay: Control
# 變身 cut-in（玩家提供立繪 ref/cut-in.jpg 去背）
var cutin_layer: Control
var cutin_dim: ColorRect
var cutin_stripes: CutinStripes
var cutin_portrait: TextureRect
var cutin_name: Label
var cutin_hint: Label
var cutin_t := -1.0            # <0 = 未播放
var cutin_dismissed := false   # 定格等待任意鍵（Game 呼叫 dismiss_cutin 才滑出）
var evo_hint: Label
var boss_hint: Label
const CUTIN_TOTAL := 1.75


class CutinStripes:
	extends Control
	## 斜切色帶（依動力服主色）：一寬帶+兩細線，-9° 斜角
	var col := Color.WHITE
	func _draw() -> void:
		var skew := 150.0
		var bands := [[210.0, 190.0, 0.42], [150.0, 16.0, 0.8], [432.0, 10.0, 0.8]]
		for b in bands:
			var y0: float = b[0]
			var hh: float = b[1]
			var a: float = b[2]
			var pts := PackedVector2Array([
				Vector2(-80, y0), Vector2(1100, y0 - skew),
				Vector2(1100, y0 - skew + hh), Vector2(-80, y0 + hh)])
			draw_colored_polygon(pts, Color(col.r * 0.55, col.g * 0.55, col.b * 0.55, a))
		# 亮緣
		draw_line(Vector2(-80, 205), Vector2(1100, 205 - skew), col, 4.0)
		draw_line(Vector2(-80, 405), Vector2(1100, 405 - skew), col, 4.0)


func _ready() -> void:
	_build()


func _process(delta: float) -> void:
	if banner_time > 0.0:
		banner_time -= delta
		banner_label.modulate.a = clampf(banner_time / 0.4, 0.0, 1.0)
		if banner_time <= 0.0:
			banner_label.visible = false
	if flash_time > 0.0:
		flash_time -= delta
		flash_rect.modulate.a = clampf(flash_time / 0.6, 0.0, 1.0) * 0.9
		flash_rect.visible = flash_time > 0.0
	# 閃爍（0.6s steps(2)：警告面板；1.2s：結算提示）
	var tms := Time.get_ticks_msec()
	if boss_overlay.visible:
		boss_warn.visible = tms % 600 < 300
		boss_hint.modulate.a = 1.0 if tms % 1200 < 600 else 0.2
	if evo_overlay.visible:
		evo_hint.modulate.a = 1.0 if tms % 1200 < 600 else 0.2
	if end_overlay.visible:
		end_hint.modulate.a = 1.0 if tms % 1200 < 600 else 0.15
	if title_overlay.visible:
		title_hint.modulate.a = 1.0 if tms % 1200 < 600 else 0.15
	# 變身 cut-in 程序動畫：滑入(0.22s)→定格（等任意鍵）→加速滑出(1.4s起)
	if cutin_t >= 0.0:
		cutin_t += delta
		if cutin_t >= 1.4 and not cutin_dismissed:
			cutin_t = 1.4   # 定格：等 Game 收到輸入呼叫 dismiss_cutin()
		var in_p := clampf(cutin_t / 0.22, 0.0, 1.0)
		var ease_in := 1.0 - pow(1.0 - in_p, 3.0)
		var out_p := clampf((cutin_t - 1.4) / 0.3, 0.0, 1.0)
		var ease_out := out_p * out_p
		cutin_portrait.position.x = lerpf(-520.0, 60.0, ease_in) + ease_out * 1200.0
		cutin_name.position.x = lerpf(W + 40.0, 460.0, ease_in) - ease_out * 1400.0
		cutin_stripes.position.x = lerpf(-W, 0.0, ease_in) + ease_out * W
		cutin_dim.modulate.a = minf(in_p, 1.0 - ease_out)
		cutin_hint.visible = cutin_t >= 0.9 and not cutin_dismissed and tms % 1200 < 600
		if cutin_t >= CUTIN_TOTAL:
			hide_cutin()


# ---------- 樣式工廠 ----------
func _sb(bg: Color, border: Color, bw: int, shadow_col := Color(0, 0, 0, 0.8), shadow_size := 0, shadow_off := Vector2(4, 4)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(bw)
	sb.border_color = border
	if shadow_size > 0 or shadow_off != Vector2.ZERO:
		sb.shadow_color = shadow_col
		sb.shadow_size = shadow_size
		sb.shadow_offset = shadow_off
	sb.set_content_margin_all(8.0)
	return sb


func _label(text: String, size: int, color: Color, shadow := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if shadow:
		l.add_theme_color_override("font_shadow_color", Color.BLACK)
		l.add_theme_constant_override("shadow_offset_x", 2)
		l.add_theme_constant_override("shadow_offset_y", 2)
	return l


func _menu_button(text: String, action: String) -> Button:
	# 暫停/結算選單按鈕（橘框樣式）
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 15)
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(200, 44)
	var sb := _sb(Color(0.1, 0.06, 0.01, 0.9), C_ORANGE_DK, 2, Color(0, 0, 0, 0), 0, Vector2.ZERO)
	btn.add_theme_stylebox_override("normal", sb)
	var sb_h := _sb(Color(0.2, 0.12, 0.02, 0.95), C_ORANGE, 2, Color(0.91, 0.627, 0.125, 0.4), 5, Vector2.ZERO)
	btn.add_theme_stylebox_override("hover", sb_h)
	btn.add_theme_stylebox_override("pressed", sb_h)
	btn.add_theme_color_override("font_color", C_ORANGE)
	btn.pressed.connect(_on_menu_action.bind(action))
	return btn


func _on_menu_action(action: String) -> void:
	menu_action.emit(action)


func _wrap_center(c: Control) -> CenterContainer:
	var w := CenterContainer.new()
	w.add_child(c)
	return w


func _panel_label(text: String, size: int, fg: Color, bg: Color, border: Color) -> Label:
	# SM式面板文字：彩色底+黑框+硬陰影
	var l := _label(text, size, fg, false)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sb := _sb(bg, border, 3)
	sb.set_content_margin(SIDE_LEFT, 22.0)
	sb.set_content_margin(SIDE_RIGHT, 22.0)
	sb.set_content_margin(SIDE_TOP, 10.0)
	sb.set_content_margin(SIDE_BOTTOM, 10.0)
	l.add_theme_stylebox_override("normal", sb)
	return l


func _corner_panel(pos: Vector2, panel_size: Vector2) -> Panel:
	var p := Panel.new()
	p.position = pos
	p.size = panel_size
	var sb := _sb(Color(0.012, 0.004, 0.024, 0.88), Color("#c8c8d8"), 2, Color(0, 0, 0, 0.7), 2, Vector2(2, 2))
	p.add_theme_stylebox_override("panel", sb)
	return p


func _overlay_base(dim: Color, grid: Color) -> Control:
	var o := Control.new()
	o.size = Vector2(W, H)
	o.visible = false
	o.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 裝飾層不得攔截滑鼠（排除鈕無效bug排查）
	var bg := ColorRect.new()
	bg.color = dim
	bg.size = Vector2(W, H)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	o.add_child(bg)
	var g := GridPattern.new()
	g.grid_col = grid
	g.size = Vector2(W, H)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	o.add_child(g)
	add_child(o)
	return o


func _icon_rect(id: String, px: float) -> TextureRect:
	var tr := TextureRect.new()
	var path := "res://assets/icon_%s.png" % id
	if ResourceLoader.exists(path):
		tr.texture = load(path)
	tr.custom_minimum_size = Vector2(px, px)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return tr


# ---------- 建構 ----------
func _build() -> void:
	# HP 面板（左上）
	var hp_panel := _corner_panel(Vector2(14, 14), Vector2(236, 58))
	add_child(hp_panel)
	var hp_title := _label("ENERGY", 12, Color.WHITE)
	hp_title.position = Vector2(12, 6)
	hp_panel.add_child(hp_title)
	hp_num = _label("100/100", 12, C_BLUE)
	hp_num.position = Vector2(120, 6)
	hp_num.size = Vector2(104, 18)
	hp_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hp_panel.add_child(hp_num)
	hp_bar = SegBar.new()
	hp_bar.position = Vector2(12, 32)
	hp_bar.size = Vector2(212, 14)
	hp_bar.col = C_PINK
	hp_bar.col_dark = C_PINK_DK
	hp_panel.add_child(hp_bar)
	# 計時面板（右上）——用 Label 自身 get_minimum_size 量寬（與實際渲染字型一致；
	# ThemeDB.fallback_font 量測會低估導致文字被切，實測踩到）
	timer_label = _label("88:88", 22, C_ORANGE)
	var depth := _label("CRATERIA SURFACE", 9, Color("#c8c8d8"))
	var tp_w := maxf(timer_label.get_minimum_size().x, depth.get_minimum_size().x) + 30.0
	var t_panel := _corner_panel(Vector2(W - 14 - tp_w, 14), Vector2(tp_w, 58))
	add_child(t_panel)
	timer_label.text = "00:00"
	timer_label.position = Vector2(12, 4)
	timer_label.size = Vector2(tp_w - 24, 30)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	t_panel.add_child(timer_label)
	depth.position = Vector2(12, 38)
	depth.size = Vector2(tp_w - 24, 14)
	depth.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	t_panel.add_child(depth)
	# XP 面板（底部中央）
	var xp_panel := _corner_panel(Vector2(W / 2 - 210, H - 60), Vector2(420, 46))
	add_child(xp_panel)
	lv_label = _label("LV. 1", 13, C_ORANGE)
	lv_label.position = Vector2(0, 4)
	lv_label.size = Vector2(420, 18)
	lv_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	xp_panel.add_child(lv_label)
	xp_bar = SegBar.new()
	xp_bar.position = Vector2(12, 28)
	xp_bar.size = Vector2(396, 8)
	xp_bar.col = C_GREEN
	xp_bar.col_dark = C_GREEN_DK
	xp_bar.seg_w = 6.0
	xp_bar.dark_w = 1.0
	xp_bar.ratio = 0.0
	xp_panel.add_child(xp_bar)
	# 動力服名（右下）
	suit_label = _label("POWER SUIT", 12, C_ORANGE)
	suit_label.position = Vector2(W - 254, H - 32)
	suit_label.size = Vector2(240, 20)
	suit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(suit_label)
	# 槽位列（頂部中央，兩排6格）
	var slot_center := CenterContainer.new()
	slot_center.position = Vector2(0, 80)
	slot_center.size = Vector2(W, 60)
	add_child(slot_center)
	var slot_v := VBoxContainer.new()
	slot_v.add_theme_constant_override("separation", 4)
	slot_center.add_child(slot_v)
	for r in range(2):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		slot_v.add_child(row)
		slot_rows.append(row)
	# 頭目血條（頂部）
	boss_bar_name = _label("", 15, C_GOLD)
	boss_bar_name.position = Vector2(0, 2)
	boss_bar_name.size = Vector2(W, 20)
	boss_bar_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_bar_name.visible = false
	add_child(boss_bar_name)
	boss_bar_bg = ColorRect.new()
	boss_bar_bg.position = Vector2(W / 2 - 192, 26)
	boss_bar_bg.size = Vector2(384, 14)
	boss_bar_bg.color = Color(0, 0, 0, 0.65)
	boss_bar_bg.visible = false
	add_child(boss_bar_bg)
	boss_bar_fill = ColorRect.new()
	boss_bar_fill.position = Vector2(W / 2 - 190, 28)
	boss_bar_fill.size = Vector2(380, 10)
	boss_bar_fill.color = C_GOLD
	boss_bar_fill.visible = false
	add_child(boss_bar_fill)
	# 橫幅
	banner_label = _label("", 26, C_GOLD)
	banner_label.position = Vector2(0, 150)
	banner_label.size = Vector2(W, 34)
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_label.visible = false
	add_child(banner_label)
	# 升級選單
	levelup_overlay = _overlay_base(Color(0.012, 0.004, 0.024, 0.94), GRID_PURPLE)
	var lv_center := CenterContainer.new()
	lv_center.size = Vector2(W, H)
	levelup_overlay.add_child(lv_center)
	var lv_box := VBoxContainer.new()
	lv_box.add_theme_constant_override("separation", 30)
	lv_box.alignment = BoxContainer.ALIGNMENT_CENTER
	lv_center.add_child(lv_box)
	var lv_title := _label("── 能量吸收：選擇強化 ──", 18, Color.WHITE, false)
	lv_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var lt_sb := _sb(Color.BLACK, Color.WHITE, 2)
	lv_title.add_theme_stylebox_override("normal", lt_sb)
	lv_box.add_child(lv_title)
	cards_box = HBoxContainer.new()
	cards_box.add_theme_constant_override("separation", 18)
	cards_box.alignment = BoxContainer.ALIGNMENT_CENTER
	lv_box.add_child(cards_box)
	# 重選鈕（卡片列下方，open_levelup 時更新剩餘次數）
	reroll_btn = Button.new()
	reroll_btn.text = "↻ 重選這一組"
	reroll_btn.add_theme_font_size_override("font_size", 14)
	reroll_btn.focus_mode = Control.FOCUS_NONE
	var rr_sb := _sb(Color(0.1, 0.06, 0.01, 0.9), C_ORANGE_DK, 2, Color(0, 0, 0, 0), 0, Vector2.ZERO)
	reroll_btn.add_theme_stylebox_override("normal", rr_sb)
	var rr_sb_h := _sb(Color(0.2, 0.12, 0.02, 0.95), C_ORANGE, 2, Color(0.91, 0.627, 0.125, 0.4), 5, Vector2.ZERO)
	reroll_btn.add_theme_stylebox_override("hover", rr_sb_h)
	reroll_btn.add_theme_color_override("font_color", C_ORANGE)
	reroll_btn.pressed.connect(_on_reroll)
	var rr_wrap := CenterContainer.new()
	rr_wrap.add_child(reroll_btn)
	lv_box.add_child(rr_wrap)
	# 進化公告
	evo_overlay = _overlay_base(Color(0.016, 0.008, 0.031, 0.93), GRID_PURPLE)
	var evo_center := CenterContainer.new()
	evo_center.size = Vector2(W, H)
	evo_overlay.add_child(evo_center)
	var evo_box := VBoxContainer.new()
	evo_box.add_theme_constant_override("separation", 16)
	evo_box.alignment = BoxContainer.ALIGNMENT_CENTER
	evo_center.add_child(evo_box)
	var evo_title := _panel_label("◆ 武器進化 ◆", 15, Color.WHITE, C_PINK, Color.BLACK)
	var evo_tc := CenterContainer.new()
	evo_tc.add_child(evo_title)
	evo_box.add_child(evo_tc)
	var evo_ic := CenterContainer.new()
	evo_icon = _icon_rect("powerBeam", 56.0)
	evo_ic.add_child(evo_icon)
	evo_box.add_child(evo_ic)
	evo_name = _label("", 26, C_GOLD)
	evo_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	evo_box.add_child(evo_name)
	evo_desc = _panel_label("", 15, Color("#241200"), C_ORANGE, Color.BLACK)
	var evo_dc := CenterContainer.new()
	evo_dc.add_child(evo_desc)
	evo_box.add_child(evo_dc)
	evo_hint = _label("▼ 按任意鍵繼續", 13, C_TEXT_DIM)
	evo_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	evo_box.add_child(evo_hint)
	# 頭目警告
	boss_overlay = _overlay_base(Color(0.024, 0.0, 0.0, 0.93), GRID_RED)
	var b_center := CenterContainer.new()
	b_center.size = Vector2(W, H)
	boss_overlay.add_child(b_center)
	var b_box := VBoxContainer.new()
	b_box.add_theme_constant_override("separation", 20)
	b_box.alignment = BoxContainer.ALIGNMENT_CENTER
	b_center.add_child(b_box)
	boss_warn = _panel_label("★ 威脅偵測 ★", 16, Color.WHITE, C_RED, Color.BLACK)
	var bw_c := CenterContainer.new()
	bw_c.custom_minimum_size = Vector2(0, 56)
	bw_c.add_child(boss_warn)
	b_box.add_child(bw_c)
	boss_title = _label("", 30, C_GREEN)
	boss_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b_box.add_child(boss_title)
	boss_flavor = _panel_label("", 14, Color("#241200"), C_ORANGE, Color.BLACK)
	var bf_c := CenterContainer.new()
	bf_c.add_child(boss_flavor)
	b_box.add_child(bf_c)
	boss_hint = _label("▼ 按任意鍵迎擊", 13, C_TEXT_DIM)
	boss_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b_box.add_child(boss_hint)
	# 勝敗結算
	end_overlay = _overlay_base(Color(0.012, 0.004, 0.024, 0.94), GRID_PURPLE)
	var e_center := CenterContainer.new()
	e_center.size = Vector2(W, H)
	end_overlay.add_child(e_center)
	var e_box := VBoxContainer.new()
	e_box.add_theme_constant_override("separation", 22)
	e_box.alignment = BoxContainer.ALIGNMENT_CENTER
	e_center.add_child(e_box)
	end_title = _panel_label("", 26, Color("#180c00"), C_GOLD, Color.BLACK)
	var et_c := CenterContainer.new()
	et_c.add_child(end_title)
	e_box.add_child(et_c)
	end_stats = _label("", 15, Color.WHITE)
	end_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	e_box.add_child(end_stats)
	end_hint = _label("R 再次挑戰｜T 回到標題", 14, C_TEXT_DIM)
	end_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	e_box.add_child(end_hint)
	var end_btns := HBoxContainer.new()
	end_btns.add_theme_constant_override("separation", 16)
	end_btns.alignment = BoxContainer.ALIGNMENT_CENTER
	end_btns.add_child(_menu_button("再次挑戰", "restart"))
	end_btns.add_child(_menu_button("回到標題", "title"))
	e_box.add_child(end_btns)
	# 標題畫面
	title_overlay = _overlay_base(Color(0.012, 0.004, 0.024, 1.0), GRID_PURPLE)
	var ti_center := CenterContainer.new()
	ti_center.size = Vector2(W, H)
	title_overlay.add_child(ti_center)
	var ti_box := VBoxContainer.new()
	ti_box.add_theme_constant_override("separation", 20)
	ti_box.alignment = BoxContainer.ALIGNMENT_CENTER
	ti_center.add_child(ti_box)
	var ti_title := _panel_label("SAMUS SURVIVORS", 36, Color("#180c00"), C_ORANGE, Color.BLACK)
	var ti_tc := CenterContainer.new()
	ti_tc.add_child(ti_title)
	ti_box.add_child(ti_tc)
	var ti_sub := _label("類銀河戰士 × 吸血鬼倖存者", 15, C_TEXT_DIM)
	ti_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ti_box.add_child(ti_sub)
	var ti_flavor := _label("未知行星的地底深處，孤獨的獵人甦醒。\n擊殺、吸收、進化——直到動力服完全覺醒。", 14, C_TEXT)
	ti_flavor.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ti_box.add_child(ti_flavor)
	title_best = _label("", 13, C_GOLD)
	title_best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ti_box.add_child(title_best)
	title_hint = _label("▼ 按任意鍵出擊", 17, Color.WHITE)
	title_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ti_box.add_child(title_hint)
	var ti_controls := _label("WASD / 方向鍵 移動｜ESC 暫停｜M 靜音", 11, C_TEXT_DIM)
	ti_controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ti_box.add_child(ti_controls)
	var ti_ver := _label(Game.GAME_VERSION, 10, C_TEXT_DIM)
	ti_ver.position = Vector2(12, H - 24)
	ti_ver.size = Vector2(500, 16)
	title_overlay.add_child(ti_ver)
	# 暫停選單
	pause_overlay = _overlay_base(Color(0.01, 0.0, 0.03, 0.82), GRID_PURPLE)
	var pa_center := CenterContainer.new()
	pa_center.size = Vector2(W, H)
	pause_overlay.add_child(pa_center)
	var pa_box := VBoxContainer.new()
	pa_box.add_theme_constant_override("separation", 18)
	pa_box.alignment = BoxContainer.ALIGNMENT_CENTER
	pa_center.add_child(pa_box)
	var pa_title := _panel_label("PAUSED", 24, Color.WHITE, Color(0.05, 0.02, 0.1), C_ORANGE)
	var pa_tc := CenterContainer.new()
	pa_tc.add_child(pa_title)
	pa_box.add_child(pa_tc)
	pa_box.add_child(_wrap_center(_menu_button("繼續（ESC）", "resume")))
	pa_box.add_child(_wrap_center(_menu_button("重新開始", "restart")))
	pa_box.add_child(_wrap_center(_menu_button("回到標題", "title")))
	# 變身 cut-in（白閃之下、其他overlay之上）
	cutin_layer = Control.new()
	cutin_layer.size = Vector2(W, H)
	cutin_layer.visible = false
	add_child(cutin_layer)
	cutin_dim = ColorRect.new()
	cutin_dim.color = Color(0.01, 0.0, 0.03, 0.55)
	cutin_dim.size = Vector2(W, H)
	cutin_layer.add_child(cutin_dim)
	cutin_stripes = CutinStripes.new()
	cutin_stripes.size = Vector2(W, H)
	cutin_layer.add_child(cutin_stripes)
	cutin_portrait = TextureRect.new()
	if ResourceLoader.exists("res://assets/cutin_samus.png"):
		cutin_portrait.texture = load("res://assets/cutin_samus.png")
	# 注意順序：先設 expand_mode 再設 size——預設 EXPAND_KEEP_SIZE 的最小尺寸=貼圖原寸，
	# 先設 size 會被 clamp 回 740x975（實測踩到）
	cutin_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cutin_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cutin_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	cutin_portrait.size = Vector2(364, 480)   # 740x975 → 高480
	cutin_portrait.position = Vector2(-520, 40)
	cutin_layer.add_child(cutin_portrait)
	cutin_name = _label("", 40, C_GOLD)
	cutin_name.position = Vector2(W + 40, 240)
	cutin_name.size = Vector2(520, 60)
	cutin_layer.add_child(cutin_name)
	cutin_hint = _label("▼ 按任意鍵繼續", 13, C_TEXT_DIM)
	cutin_hint.position = Vector2(W - 240, H - 34)
	cutin_hint.size = Vector2(220, 20)
	cutin_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cutin_hint.visible = false
	cutin_layer.add_child(cutin_hint)
	# 變身白閃（最上層）
	flash_rect = ColorRect.new()
	flash_rect.color = Color.WHITE
	flash_rect.size = Vector2(W, H)
	flash_rect.visible = false
	add_child(flash_rect)


# ---------- 每幀狀態 ----------
func update_status(hp: float, max_hp: float, elapsed: float, level: int, xp_ratio: float, suit_text: String, boss: EnemyUnit) -> void:
	hp_num.text = "%d/%d" % [ceili(maxf(0, hp)), int(max_hp)]
	hp_bar.ratio = clampf(hp / max_hp, 0.0, 1.0)
	var low := hp / max_hp < 0.3
	hp_bar.col = C_HP_RED if low else C_PINK
	hp_bar.col_dark = C_HP_RED_DK if low else C_PINK_DK
	hp_bar.queue_redraw()
	timer_label.text = "%02d:%02d" % [int(elapsed) / 60, int(elapsed) % 60]
	lv_label.text = "LV. %d" % level
	xp_bar.ratio = clampf(xp_ratio, 0.0, 1.0)
	xp_bar.queue_redraw()
	suit_label.text = suit_text
	var show_bar := boss != null and is_instance_valid(boss) and not boss.dead
	boss_bar_name.visible = show_bar
	boss_bar_bg.visible = show_bar
	boss_bar_fill.visible = show_bar
	if show_bar:
		boss_bar_name.text = boss.boss_name
		boss_bar_fill.size.x = 380.0 * clampf(boss.hp / boss.max_hp, 0.0, 1.0)
		boss_bar_fill.color = Color("#1e9628") if boss.is_final_boss else C_GOLD


func refresh_slots(ws: WeaponSystem) -> void:
	for row in slot_rows:
		for c in row.get_children():
			c.queue_free()
	for i in range(6):
		var w: WeaponSystem.WeaponInst = ws.weapons[i] if i < ws.weapons.size() else null
		slot_rows[0].add_child(_make_slot(w.id if w != null else "", w.evolved if w != null else false, "MAX" if w != null and w.evolved else (str(w.level) if w != null else "")))
	for i in range(6):
		var p: WeaponSystem.PassiveInst = ws.passives[i] if i < ws.passives.size() else null
		slot_rows[1].add_child(_make_slot(p.id if p != null else "", false, str(p.level) if p != null else ""))


func _make_slot(icon_id: String, evolved: bool, lv_text: String) -> Panel:
	var slot := Panel.new()
	slot.custom_minimum_size = Vector2(26, 26)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.039, 0.055, 0.094, 0.8)
	sb.set_border_width_all(1)
	sb.border_color = Color("#ffe066") if evolved else Color("#1c5a6e")
	if evolved:
		sb.shadow_color = Color(1.0, 0.878, 0.4, 0.5)
		sb.shadow_size = 4
	slot.add_theme_stylebox_override("panel", sb)
	if icon_id == "":
		slot.modulate.a = 0.25
		return slot
	var tr := _icon_rect(icon_id, 18.0)
	tr.position = Vector2(4, 4)
	tr.size = Vector2(18, 18)
	slot.add_child(tr)
	var lv := _label(lv_text, 9, Color("#4fd8ff"), false)
	lv.position = Vector2(12, 15)
	var lv_sb := StyleBoxFlat.new()
	lv_sb.bg_color = Color.BLACK
	lv_sb.set_content_margin_all(1.0)
	lv.add_theme_stylebox_override("normal", lv_sb)
	slot.add_child(lv)
	return slot


# ---------- 升級卡片 ----------
func open_levelup(picks: Array, reroll_left: int, banish_left: int) -> void:
	for c in cards_box.get_children():
		c.queue_free()
	card_buttons.clear()
	for pick in picks:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 8)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var btn := _make_card(pick)
		card_buttons.append(btn)
		col.add_child(btn)
		# 排除鈕：本場遊戲不再出現該項目
		var ban := Button.new()
		ban.text = "✖ 排除（剩 %d）" % banish_left
		ban.add_theme_font_size_override("font_size", 12)
		ban.focus_mode = Control.FOCUS_NONE
		ban.disabled = banish_left <= 0
		var ban_sb := _sb(Color(0.1, 0.02, 0.02, 0.9), Color("#7a2020"), 1, Color(0, 0, 0, 0), 0, Vector2.ZERO)
		ban_sb.set_content_margin_all(5.0)
		ban.add_theme_stylebox_override("normal", ban_sb)
		var ban_sb_h := _sb(Color(0.25, 0.05, 0.05, 0.95), C_RED, 1, Color(0, 0, 0, 0), 0, Vector2.ZERO)
		ban_sb_h.set_content_margin_all(5.0)
		ban.add_theme_stylebox_override("hover", ban_sb_h)
		ban.add_theme_color_override("font_color", Color("#e08080"))
		var card: Dictionary = pick["card"]
		ban.pressed.connect(_on_banish.bind(card))
		col.add_child(ban)
		cards_box.add_child(col)
	reroll_btn.text = "↻ 重選這一組（剩 %d）" % reroll_left
	reroll_btn.disabled = reroll_left <= 0
	levelup_overlay.visible = true


func _on_reroll() -> void:
	reroll_requested.emit()


func _on_banish(card: Dictionary) -> void:
	banish_requested.emit(card)


func close_levelup() -> void:
	levelup_overlay.visible = false


func _make_card(info: Dictionary) -> Button:
	var is_new: bool = info["is_new"]
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(224, 210)
	btn.focus_mode = Control.FOCUS_NONE
	var border := C_GOLD if is_new else Color("#8a48d8")
	var glow := Color(1.0, 0.843, 0.416, 0.5) if is_new else Color(0.588, 0.314, 1.0, 0.4)
	var sb_n := _sb(Color(0.024, 0.008, 0.055, 0.92), border, 2, glow, 6, Vector2.ZERO)
	var sb_h := _sb(Color(0.157, 0.086, 0.016, 0.92), C_ORANGE, 2, Color(0.91, 0.627, 0.125, 0.55), 8, Vector2.ZERO)
	btn.add_theme_stylebox_override("normal", sb_n)
	btn.add_theme_stylebox_override("hover", sb_h)
	btn.add_theme_stylebox_override("pressed", sb_h)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	# 內容（全部 IGNORE：卡片內容物不得攔截點擊，點哪都要落在按鈕上）
	var box := VBoxContainer.new()
	box.position = Vector2(12, 22)
	box.size = Vector2(200, 176)
	box.add_theme_constant_override("separation", 10)
	box.alignment = BoxContainer.ALIGNMENT_BEGIN
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(box)
	var ic := CenterContainer.new()
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic.add_child(_icon_rect(String(info["icon"]), 44.0))
	box.add_child(ic)
	var lv := _label(String(info["lv_line"]), 12, C_GOLD if is_new else C_GREEN, false)
	lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(lv)
	var desc := _label(String(info["desc"]), 13, Color("#c8cede"), false)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(198, 0)
	box.add_child(desc)
	# 標題騎在上框線（●紅點=一般、★金=新取得）
	var chip_wrap := CenterContainer.new()
	chip_wrap.position = Vector2(0, -12)
	chip_wrap.size = Vector2(224, 24)
	chip_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(chip_wrap)
	var prefix := "★ " if is_new else "● "
	var chip := _label(prefix + String(info["name"]), 12, C_GOLD if is_new else C_ORANGE, false)
	var chip_sb := StyleBoxFlat.new()
	chip_sb.bg_color = Color("#05010a")
	chip_sb.set_content_margin(SIDE_LEFT, 8.0)
	chip_sb.set_content_margin(SIDE_RIGHT, 8.0)
	chip_sb.set_content_margin(SIDE_TOP, 2.0)
	chip_sb.set_content_margin(SIDE_BOTTOM, 2.0)
	chip.add_theme_stylebox_override("normal", chip_sb)
	chip_wrap.add_child(chip)
	var card: Dictionary = info["card"]
	btn.pressed.connect(_on_card.bind(card))
	return btn


func _on_card(card: Dictionary) -> void:
	card_picked.emit(card)


# ---------- 公告 ----------
func show_evolution(icon_id: String, evo_name_text: String, desc: String) -> void:
	var path := "res://assets/icon_%s.png" % icon_id
	if ResourceLoader.exists(path):
		evo_icon.texture = load(path)
	evo_name.text = evo_name_text
	evo_desc.text = desc
	evo_overlay.visible = true


func show_boss_announce(title: String, flavor: String) -> void:
	boss_title.text = title
	boss_flavor.text = flavor
	boss_overlay.visible = true


func hide_announce() -> void:
	evo_overlay.visible = false
	boss_overlay.visible = false


func show_cutin(tier: String, suit_color: Color, title: String) -> void:
	# 各套動力服專屬立繪（色相重映射產生，見 scratchpad/cutin_suits.py）
	var path := "res://assets/cutin_samus_%s.png" % tier
	if not ResourceLoader.exists(path):
		path = "res://assets/cutin_samus.png"
	if ResourceLoader.exists(path):
		cutin_portrait.texture = load(path)
	cutin_stripes.col = suit_color
	cutin_stripes.queue_redraw()
	cutin_name.text = title
	cutin_name.add_theme_color_override("font_color", suit_color.lightened(0.35))
	cutin_layer.visible = true
	cutin_t = 0.0
	cutin_dismissed = false
	cutin_hint.visible = false
	cutin_portrait.position.x = -520.0
	cutin_name.position.x = W + 40.0


func dismiss_cutin() -> void:
	cutin_dismissed = true


func hide_cutin() -> void:
	cutin_layer.visible = false
	cutin_t = -1.0
	cutin_dismissed = false


func show_banner(text: String) -> void:
	banner_label.text = text
	banner_label.visible = true
	banner_label.modulate.a = 1.0
	banner_time = 1.8


func flash_white() -> void:
	flash_time = 0.6
	flash_rect.visible = true


func show_title(best_line: String) -> void:
	title_best.text = best_line
	title_overlay.visible = true


func hide_title() -> void:
	title_overlay.visible = false


func show_pause() -> void:
	pause_overlay.visible = true


func hide_pause() -> void:
	pause_overlay.visible = false


func show_victory(stats: String) -> void:
	end_title.text = "MISSION COMPLETE"
	var sb: StyleBoxFlat = end_title.get_theme_stylebox("normal")
	sb.bg_color = C_GOLD
	end_title.add_theme_color_override("font_color", Color("#180c00"))
	end_stats.text = stats
	end_overlay.visible = true


func show_dead(stats: String) -> void:
	end_title.text = "ENERGY DEPLETED"
	var sb: StyleBoxFlat = end_title.get_theme_stylebox("normal")
	sb.bg_color = C_RED
	end_title.add_theme_color_override("font_color", Color.WHITE)
	end_stats.text = stats
	end_overlay.visible = true
