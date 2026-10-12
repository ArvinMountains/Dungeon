class_name UiKit
extends RefCounted
## UI 设计系统（单一来源）：颜色 / 间距 / 字号 / 圆角 全部在此定义，
## GameUI 与 UIPanels 只引用这里的 token，避免散落硬编码。
## 纪律（来自 UI 设计规范调研）：
## - 深色主题只用 off-black / off-white，绝不用纯黑纯白；
## - 全局只有一个强调色（金色 GOLD），一套圆角（R）；
## - 间距走 4 基准刻度；字号分 6 档，正文不小于 12。

# ---------- 颜色 ----------
const BG := Color(0.055, 0.070, 0.062, 0.94)        # 面板底
const BG_SOFT := Color(0.085, 0.105, 0.092, 0.94)    # 次级块底
const BG_SLOT := Color(0.095, 0.115, 0.100)          # 格子/槽位
const BG_DIM := Color(0.030, 0.040, 0.036, 0.55)     # 遮罩（off-black，替代纯黑）
const BORDER := Color(0.34, 0.30, 0.19)
const BORDER_HI := Color(0.56, 0.46, 0.25)
const GOLD := Color(0.86, 0.71, 0.42)                # 唯一强调色
const GOLD_DIM := Color(0.60, 0.50, 0.30)
const TEXT := Color(0.90, 0.88, 0.80)
const TEXT_DIM := Color(0.66, 0.63, 0.55)
const TEXT_MUTE := Color(0.46, 0.44, 0.38)
const HP := Color(0.72, 0.30, 0.22)
const HP_GHOST := Color(0.86, 0.66, 0.42)            # 伤害延迟层
const MP := Color(0.42, 0.56, 0.86)
const OK := Color(0.58, 0.78, 0.47)
const WARN := Color(0.88, 0.62, 0.28)
const DANGER := Color(0.82, 0.32, 0.28)

# ---------- 间距（4 基准刻度） ----------
const S1 := 4.0
const S2 := 8.0
const S3 := 12.0
const S4 := 16.0
const S6 := 24.0

# ---------- 圆角（全局一套） ----------
const R := 6
const R_SM := 4

# ---------- 字号 ----------
const F_TINY := 11
const F_SMALL := 12
const F_BODY := 13
const F_LABEL := 15
const F_TITLE := 18
const F_HERO := 26

# ---------- 形状工具 ----------
static func stylebox(bg: Color = BG, border: Color = BORDER, radius: int = R, width: int = 1, margin: float = S3) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	return sb

static func panel(bg: Color = BG, border: Color = BORDER, margin: float = S3) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", stylebox(bg, border, R, 1, margin))
	return p

static func label(text: String, size: int = F_BODY, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

## 小节标题：小字号 + 暗色 + 下方金色细线（替代字距调整）。
static func section(text: String, color: Color = TEXT_MUTE) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.add_child(label(text, F_TINY, color))
	var rule := ColorRect.new()
	rule.color = Color(GOLD_DIM.r, GOLD_DIM.g, GOLD_DIM.b, 0.45)
	rule.custom_minimum_size = Vector2(0, 1)
	v.add_child(rule)
	return v

static func button(text: String, cb: Callable, accent: bool = false, size: int = F_SMALL) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	var sb := stylebox(Color(0.15, 0.17, 0.14) if not accent else Color(0.28, 0.23, 0.12),
		GOLD if accent else Color(0.32, 0.31, 0.23), R_SM, 1, S2)
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	var hover := sb.duplicate() as StyleBoxFlat
	hover.bg_color = sb.bg_color.lightened(0.12)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("disabled", sb)
	b.add_theme_color_override("font_disabled_color", TEXT_MUTE)
	b.pressed.connect(cb)
	return b

static func spacer(w: float = 0.0, h: float = 0.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	return c

## 可横向撑开的空白（HBox 用）。
static func hspacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c

static func vspacer() -> Control:
	var c := Control.new()
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c

## 进度条：底 + 填充（返回 {bg, fill}，调用方设置 custom_minimum_size 宽度比例）。
static func bar(w: float, h: float, fill_color: Color = HP) -> Dictionary:
	var bg := ColorRect.new()
	bg.color = Color(0.13, 0.12, 0.11)
	bg.custom_minimum_size = Vector2(w, h)
	bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := ColorRect.new()
	fill.color = fill_color
	fill.custom_minimum_size = Vector2(w, h)
	bg.add_child(fill)
	return {"bg": bg, "fill": fill}

## 任务/状态标记：形状优先于颜色（进行中=竖条，可领赏=菱形，完成=对勾字符）。
static func marker(kind: String) -> Control:
	match kind:
		"done":
			var l := label("✓", F_SMALL, OK)
			l.custom_minimum_size = Vector2(14, 0)
			return l
		"claim":
			var d := label("◆", F_SMALL, GOLD)
			d.custom_minimum_size = Vector2(14, 0)
			return d
		"tracked":
			var t := label("▌", F_SMALL, GOLD)
			t.custom_minimum_size = Vector2(14, 0)
			return t
		_:
			var d2 := label("·", F_SMALL, TEXT_MUTE)
			d2.custom_minimum_size = Vector2(14, 0)
			return d2
