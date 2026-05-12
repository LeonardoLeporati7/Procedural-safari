## animal_tooltip.gd
## Mostra un pannello UI con i dati dell'animale (vita, fame, sete, energia,
## riproduzione) quando il PLAYER si avvicina entro `detection_radius`.
## Il pannello viene posizionato sopra la testa dell'animale (proiezione 3D→2D).
##
## Attacca questo script a un nodo CanvasLayer nella scena principale.
##
## Setup nell'Inspector:
##   - player          : assegna il CharacterBody3D "controller" (l'osservatore
##                       con camera + capsula). Se lasciato vuoto, lo cerca
##                       automaticamente nel gruppo "player" o per nome
##                       ("controller").
##   - camera          : la Camera3D usata per il rendering. Se vuoto, usa
##                       quella attiva del viewport.
##   - detection_radius: raggio entro cui mostrare il tooltip.
##   - world_offset    : offset in mondo rispetto al body dell'animale (di
##                       default 1.5m sopra, per stare sopra la testa).

extends CanvasLayer

# ─── CONFIGURAZIONE ──────────────────────────────────────────────────────────
@export var player: Node3D
@export var camera: Camera3D
@export var detection_radius: float = 8.0
@export var world_offset: Vector3   = Vector3(0.0, 1.5, 0.0)
## Quando ci sono più animali nel raggio, sceglie il più vicino. Se true,
## il pannello fa un piccolo fade quando l'animale entra/esce dal raggio.
@export var smooth_fade: bool       = true
@export var fade_speed: float       = 8.0   # 1/secondi

# ─── NODI UI (creati in _ready) ───────────────────────────────────────────────
var _panel:       PanelContainer
var _name_label:  Label
var _bars: Dictionary = {}   # { "health": ProgressBar, "hunger": ..., ... }

# Dati barre: chiave → { icon, color }
const BAR_DEFS = {
	"health":       { "icon": "❤",  "color": Color(0.85, 0.15, 0.15) },
	"hunger":       { "icon": "🍖", "color": Color(0.90, 0.60, 0.10) },
	"thirst":       { "icon": "💧", "color": Color(0.20, 0.55, 0.95) },
	"reproduction": { "icon": "✿",  "color": Color(0.85, 0.30, 0.75) },
	"energy":       { "icon": "⚡", "color": Color(0.95, 0.85, 0.10) },
}

var _current_animal: Node = null   # BehaviorController correntemente mostrato
var _alpha: float = 0.0            # opacità per il fade

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	_build_ui()
	_panel.visible = false
	_panel.modulate.a = 0.0

# ─────────────────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	# Risolvi player/camera se non ancora pronti
	if not _ensure_refs():
		_panel.visible = false
		return

	var animal := _find_closest_animal_in_range()

	if animal != _current_animal:
		_current_animal = animal

	# Fade in/out
	var target_alpha := 1.0 if _current_animal else 0.0
	if smooth_fade:
		_alpha = lerp(_alpha, target_alpha, clamp(fade_speed * delta, 0.0, 1.0))
	else:
		_alpha = target_alpha
	_panel.modulate.a = _alpha
	_panel.visible    = _alpha > 0.01

	if _current_animal:
		_update_panel(_current_animal)
		_position_panel_above(_current_animal)

# ─── REFS ────────────────────────────────────────────────────────────────────
func _ensure_refs() -> bool:
	if not is_instance_valid(player):
		player = _autodetect_player()
	if not is_instance_valid(camera):
		camera = get_viewport().get_camera_3d()
	return is_instance_valid(player) and is_instance_valid(camera)

func _autodetect_player() -> Node3D:
	# 1) Gruppo "player" (consigliato: aggiungi il controller a questo gruppo)
	var found = get_tree().get_first_node_in_group("player")
	if found is Node3D:
		return found
	# 2) Cerca per nome "controller" (è il nodo definito in controller.tscn)
	var by_name := _find_node_by_name(get_tree().root, "controller")
	if by_name is Node3D:
		return by_name
	# 3) Fallback: usa il parent della camera attiva (di solito il body player)
	var cam := get_viewport().get_camera_3d()
	if cam and cam.get_parent() is CharacterBody3D:
		return cam.get_parent()
	return null

func _find_node_by_name(n: Node, target_name: String) -> Node:
	if n.name == target_name:
		return n
	for child in n.get_children():
		var f := _find_node_by_name(child, target_name)
		if f:
			return f
	return null

# ─── PROXIMITY SCAN ─────────────────────────────────────────────────────────
func _find_closest_animal_in_range() -> Node:
	var best: Node = null
	var best_d2 := detection_radius * detection_radius
	var p_pos: Vector3 = player.global_position

	for ctrl in get_tree().get_nodes_in_group("animal_behavior"):
		if not ctrl or not ctrl.has_method("get_need_urgency"):
			continue
		var b: Node = ctrl.get_parent()
		if not (b is Node3D):
			continue
		# Animali morti non vengono mostrati
		if ctrl.has_method("is_alive") and not ctrl.is_alive():
			continue
		var d2: float = (b.global_position - p_pos).length_squared()
		if d2 < best_d2:
			best_d2 = d2
			best    = ctrl
	return best

# ─── POSIZIONAMENTO PANNELLO ────────────────────────────────────────────────
func _position_panel_above(ctrl: Node) -> void:
	var b: Node3D = ctrl.get_parent() as Node3D
	if not b: return

	var world_pos: Vector3 = b.global_position + world_offset

	# Se il punto è dietro la camera, nascondi
	if camera.is_position_behind(world_pos):
		_panel.visible = false
		return

	var screen_pos := camera.unproject_position(world_pos)
	var vp_size    := get_viewport().get_visible_rect().size
	# Centra orizzontalmente sul punto, ancora la base del pannello al punto
	var pos := screen_pos - Vector2(_panel.size.x * 0.5, _panel.size.y + 8.0)
	pos.x = clamp(pos.x, 0.0, vp_size.x - _panel.size.x - 4.0)
	pos.y = clamp(pos.y, 0.0, vp_size.y - _panel.size.y - 4.0)
	_panel.position = pos

# ─── AGGIORNA PANNELLO ────────────────────────────────────────────────────────
func _update_panel(ctrl: Node) -> void:
	# Nome: usa il nome del nodo genitore (il body)
	_name_label.text = ctrl.get_parent().name

	# HP
	if _bars.has("health") and ctrl.has_method("get_health_ratio"):
		_bars["health"].value = ctrl.get_health_ratio() * 100.0

	# Bisogni da needs dictionary
	for key in ["hunger", "thirst", "reproduction", "energy"]:
		if not _bars.has(key):
			continue
		# urgency va da 0 (pieno) a 1 (critico) — invertiamo per la barra
		var urgency: float = ctrl.get_need_urgency(key)
		_bars[key].value = (1.0 - urgency) * 100.0

# ─── COSTRUZIONE UI ──────────────────────────────────────────────────────────
func _build_ui() -> void:
	# Pannello principale
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(180, 0)
	# Non intercetta i click del mouse (è solo informativo)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	# Stile pannello: sfondo scuro semitrasparente
	var style := StyleBoxFlat.new()
	style.bg_color           = Color(0.08, 0.08, 0.08, 0.82)
	style.corner_radius_top_left     = 6
	style.corner_radius_top_right    = 6
	style.corner_radius_bottom_left  = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left   = 10
	style.content_margin_right  = 10
	style.content_margin_top    = 8
	style.content_margin_bottom = 8
	_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	_panel.add_child(vbox)

	# Nome animale
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 13)
	_name_label.add_theme_color_override("font_color", Color(1, 1, 1))
	vbox.add_child(_name_label)

	# Separatore
	var sep := HSeparator.new()
	sep.add_theme_color_override("color", Color(1, 1, 1, 0.2))
	vbox.add_child(sep)

	# Barre bisogni
	for key in BAR_DEFS:
		var def   = BAR_DEFS[key]
		var hbox  := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 6)
		vbox.add_child(hbox)

		# Icona
		var icon := Label.new()
		icon.text = def["icon"]
		icon.custom_minimum_size = Vector2(20, 0)
		icon.add_theme_font_size_override("font_size", 12)
		hbox.add_child(icon)

		# Barra
		var bar := ProgressBar.new()
		bar.min_value = 0
		bar.max_value = 100
		bar.value     = 100
		bar.custom_minimum_size   = Vector2(130, 12)
		bar.show_percentage       = false
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		# Colore barra
		var bar_style := StyleBoxFlat.new()
		bar_style.bg_color             = def["color"]
		bar_style.corner_radius_top_left     = 3
		bar_style.corner_radius_top_right    = 3
		bar_style.corner_radius_bottom_left  = 3
		bar_style.corner_radius_bottom_right = 3
		bar.add_theme_stylebox_override("fill", bar_style)

		# Sfondo barra
		var bg_style := StyleBoxFlat.new()
		bg_style.bg_color = Color(0.2, 0.2, 0.2, 0.8)
		bg_style.corner_radius_top_left     = 3
		bg_style.corner_radius_top_right    = 3
		bg_style.corner_radius_bottom_left  = 3
		bg_style.corner_radius_bottom_right = 3
		bar.add_theme_stylebox_override("background", bg_style)

		hbox.add_child(bar)
		_bars[key] = bar
