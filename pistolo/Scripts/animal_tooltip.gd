## animal_tooltip.gd
## Pannello UI con vita/fame/sete/energia/riproduzione dell'animale più vicino
## al player. Compare quando il player entra entro `detection_radius` e si
## posiziona sopra la testa dell'animale (proiezione 3D→2D).
##
## Attacca a un CanvasLayer nella scena principale.
##
## Inspector:
##   - player          : il CharacterBody3D "controller" (osservatore con
##                       camera + capsula). Lascia vuoto per auto-detect.
##   - camera          : Camera3D usata per proiettare. Vuoto = usa quella
##                       attiva del viewport.
##   - detection_radius: raggio (in metri) entro cui mostrare il pannello.
##   - world_offset    : offset rispetto al body dell'animale (alza/abbassa la
##                       barra rispetto al modello).
##   - debug_log       : se true, stampa in console quando entra/esce dal raggio.

extends CanvasLayer

# ─── CONFIGURAZIONE ──────────────────────────────────────────────────────────
@export var player: Node3D
@export var camera: Camera3D
@export var detection_radius: float = 8.0
@export var world_offset: Vector3   = Vector3(0.0, 1.5, 0.0)
@export var smooth_fade: bool       = true
@export var fade_speed: float       = 8.0   # 1/secondi
@export var debug_log: bool         = false
## Mostra nel pannello le urgency dei bisogni e le soglie di attivazione.
@export var show_urgency_debug: bool = true

# ─── NODI UI ─────────────────────────────────────────────────────────────────
var _panel:       PanelContainer
var _name_label:  Label
var _sex_label:   Label
var _state_label: Label
var _debug_label: Label
var _bars: Dictionary = {}

const SEX_COLOR_FEMALE := Color(1.0, 0.45, 0.75)   # rosa
const SEX_COLOR_MALE   := Color(0.40, 0.70, 1.0)   # azzurro

# Definizioni barre: chiave → { icon, color }
const BAR_DEFS = {
	"health":       { "icon": "❤",  "color": Color(0.85, 0.15, 0.15) },
	"hunger":       { "icon": "🍖", "color": Color(0.90, 0.60, 0.10) },
	"thirst":       { "icon": "💧", "color": Color(0.20, 0.55, 0.95) },
	"reproduction": { "icon": "✿",  "color": Color(0.85, 0.30, 0.75) },
	"energy":       { "icon": "⚡", "color": Color(0.95, 0.85, 0.10) },
}

var _current_animal: Node = null
var _alpha: float = 0.0

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	_build_ui()
	_panel.visible = false
	_panel.modulate.a = 0.0

# ─────────────────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if not _ensure_refs():
		_panel.visible = false
		return

	# Trova l'animale più vicino entro il raggio
	var best: Node    = null
	var best_d: float = detection_radius
	var p_pos: Vector3 = player.global_position

	for ctrl in get_tree().get_nodes_in_group("animal_behavior"):
		if not ctrl or not ctrl.has_method("get_need_urgency"):
			continue
		var b: Node = ctrl.get_parent()
		if not (b is Node3D):
			continue
		# NB: mostriamo ANCHE gli animali morti (stato "Morto" visibile nel
		# tooltip finché il cadavere non viene rimosso dalla scena tramite
		# il timer di corpse_duration_sec in animal_base.gd).
		var d: float = (b.global_position - p_pos).length()
		if d < best_d:
			best_d = d
			best   = ctrl

	# Log su cambio target
	if best != _current_animal:
		if debug_log:
			if _current_animal:
				print("[AnimalTooltip] USCITO: ", _readable_name(_current_animal))
			if best:
				print("[AnimalTooltip] ENTRATO: ", _readable_name(best),
					  "  dist=%.2fm" % best_d)
		_current_animal = best

	# Fade
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
	var found = get_tree().get_first_node_in_group("player")
	if found is Node3D:
		return found
	var by_name := _find_node_by_name(get_tree().root, "controller")
	if by_name is Node3D:
		return by_name
	var cam := get_viewport().get_camera_3d()
	if cam and cam.get_parent() is Node3D:
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

# ─── NOME LEGGIBILE DELL'ANIMALE ─────────────────────────────────────────────
## Gli animali spawnati a runtime hanno nomi tipo "@CharacterBody3D@38". Proviamo
## a tirare fuori un nome più carino da:
##   1) ctrl.species_name (se la sottoclasse lo espone)
##   2) il nome dello script del BehaviorController (es. "carnivore.gd" → "Carnivore")
##   3) il nome del body se non inizia con "@"
##   4) fallback al nome del body così com'è
func _readable_name(ctrl: Node) -> String:
	if "species_name" in ctrl and ctrl.species_name != "":
		return str(ctrl.species_name)

	var script: Script = ctrl.get_script()
	if script:
		var fname: String = script.resource_path.get_file().get_basename()
		if fname != "":
			return fname.capitalize()

	var body: Node = ctrl.get_parent()
	if body and not body.name.begins_with("@"):
		return str(body.name)

	return str(body.name) if body else "Animale"

# ─── POSIZIONAMENTO PANNELLO ────────────────────────────────────────────────
func _position_panel_above(ctrl: Node) -> void:
	var b: Node3D = ctrl.get_parent() as Node3D
	if not b: return

	var world_pos: Vector3 = b.global_position + world_offset

	if camera.is_position_behind(world_pos):
		_panel.visible = false
		return

	var screen_pos := camera.unproject_position(world_pos)
	var vp_size    := get_viewport().get_visible_rect().size
	var pos := screen_pos - Vector2(_panel.size.x * 0.5, _panel.size.y + 8.0)
	pos.x = clamp(pos.x, 0.0, vp_size.x - _panel.size.x - 4.0)
	pos.y = clamp(pos.y, 0.0, vp_size.y - _panel.size.y - 4.0)
	_panel.position = pos

# ─── AGGIORNA PANNELLO ───────────────────────────────────────────────────────
func _update_panel(ctrl: Node) -> void:
	_name_label.text = _readable_name(ctrl)

	# Sesso (icona ♀/♂ colorata accanto al nome)
	if ctrl.has_method("is_female"):
		var female: bool = ctrl.is_female()
		_sex_label.text = "♀" if female else "♂"
		_sex_label.add_theme_color_override(
			"font_color", SEX_COLOR_FEMALE if female else SEX_COLOR_MALE
		)
	else:
		_sex_label.text = ""

	# Stato corrente (in italiano via animal_base.get_state_label)
	if ctrl.has_method("get_state_label"):
		_state_label.text = ctrl.get_state_label()
	else:
		_state_label.text = ""

	if _bars.has("health") and ctrl.has_method("get_health_ratio"):
		_bars["health"].value = ctrl.get_health_ratio() * 100.0

	for key in ["hunger", "thirst", "reproduction", "energy"]:
		if not _bars.has(key):
			continue
		var urgency: float = ctrl.get_need_urgency(key)
		_bars[key].value = (1.0 - urgency) * 100.0

	# Debug urgency + soglie
	if show_urgency_debug:
		_debug_label.visible = true
		_debug_label.text = _build_debug_text(ctrl)
	else:
		_debug_label.visible = false

func _build_debug_text(ctrl: Node) -> String:
	# Urgency dei bisogni
	var u_hunger: float = ctrl.get_need_urgency("hunger")
	var u_thirst: float = ctrl.get_need_urgency("thirst")
	var u_energy: float = ctrl.get_need_urgency("energy")
	var u_repro:  float = ctrl.get_need_urgency("reproduction")

	# Soglie (export su AnimalBase)
	var t_food: float   = ctrl.seek_food_threshold  if "seek_food_threshold"  in ctrl else 0.45
	var t_water: float  = ctrl.seek_water_threshold if "seek_water_threshold" in ctrl else 0.50
	var t_sleep: float  = ctrl.sleep_threshold      if "sleep_threshold"      in ctrl else 0.70
	var t_mate: float   = ctrl.seek_mate_threshold  if "seek_mate_threshold"  in ctrl else 0.60

	# Una freccia ↑ se l'urgency ha superato la soglia
	var mark := func(u: float, t: float) -> String:
		return "↑" if u >= t else " "

	var s := "─ debug ─\n"
	s += "fame   %5.2f / %.2f %s\n" % [u_hunger, t_food,  mark.call(u_hunger, t_food)]
	s += "sete   %5.2f / %.2f %s\n" % [u_thirst, t_water, mark.call(u_thirst, t_water)]
	s += "enrgy  %5.2f / %.2f %s\n" % [u_energy, t_sleep, mark.call(u_energy, t_sleep)]
	s += "repro  %5.2f / %.2f %s"   % [u_repro,  t_mate,  mark.call(u_repro,  t_mate)]

	# Rilevamento: quanti body nell'Area3D totale + minacce
	var detect_line := ""
	if ctrl.has_method("get_detected_count"):
		detect_line = "vede: %d  minacce: %d" % [
			ctrl.get_detected_count(),
			ctrl.get_threats_count() if ctrl.has_method("get_threats_count") else 0
		]
	if detect_line != "":
		s += "\n" + detect_line

	# Liste filtrate per tipo (food/water/prey/mate)
	var lists := []
	if "_food_sources"   in ctrl: lists.append("food:%d"    % (ctrl._food_sources   as Array).size())
	if "_water_sources"  in ctrl: lists.append("water:%d"   % (ctrl._water_sources  as Array).size())
	if "_prey_in_range"  in ctrl: lists.append("prey:%d"    % (ctrl._prey_in_range  as Array).size())
	if "_mates_near"     in ctrl: lists.append("mates:%d"   % (ctrl._mates_near     as Array).size())
	if "_predators_near" in ctrl: lists.append("pred:%d"    % (ctrl._predators_near as Array).size())
	if not lists.is_empty():
		s += "\n" + " ".join(lists)
	return s

# ─── COSTRUZIONE UI ──────────────────────────────────────────────────────────
func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(180, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

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

	# Riga "nome + sesso" sulla stessa linea
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	vbox.add_child(name_row)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 13)
	_name_label.add_theme_color_override("font_color", Color(1, 1, 1))
	name_row.add_child(_name_label)

	_sex_label = Label.new()
	_sex_label.add_theme_font_size_override("font_size", 14)
	# Il colore viene impostato dinamicamente in _update_panel
	name_row.add_child(_sex_label)

	# Etichetta dello stato corrente (es. "Vagando", "Cerca cibo", ...)
	_state_label = Label.new()
	_state_label.add_theme_font_size_override("font_size", 11)
	_state_label.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0, 0.9))
	vbox.add_child(_state_label)

	var sep := HSeparator.new()
	sep.add_theme_color_override("color", Color(1, 1, 1, 0.2))
	vbox.add_child(sep)

	for key in BAR_DEFS:
		var def   = BAR_DEFS[key]
		var hbox  := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 6)
		vbox.add_child(hbox)

		var icon := Label.new()
		icon.text = def["icon"]
		icon.custom_minimum_size = Vector2(20, 0)
		icon.add_theme_font_size_override("font_size", 12)
		hbox.add_child(icon)

		var bar := ProgressBar.new()
		bar.min_value = 0
		bar.max_value = 100
		bar.value     = 100
		bar.custom_minimum_size   = Vector2(130, 12)
		bar.show_percentage       = false
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var bar_style := StyleBoxFlat.new()
		bar_style.bg_color             = def["color"]
		bar_style.corner_radius_top_left     = 3
		bar_style.corner_radius_top_right    = 3
		bar_style.corner_radius_bottom_left  = 3
		bar_style.corner_radius_bottom_right = 3
		bar.add_theme_stylebox_override("fill", bar_style)

		var bg_style := StyleBoxFlat.new()
		bg_style.bg_color = Color(0.2, 0.2, 0.2, 0.8)
		bg_style.corner_radius_top_left     = 3
		bg_style.corner_radius_top_right    = 3
		bg_style.corner_radius_bottom_left  = 3
		bg_style.corner_radius_bottom_right = 3
		bar.add_theme_stylebox_override("background", bg_style)

		hbox.add_child(bar)
		_bars[key] = bar

	# Etichetta debug urgency (monospaziata, in coda al pannello)
	_debug_label = Label.new()
	_debug_label.add_theme_font_size_override("font_size", 10)
	_debug_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 0.9))
	# Usa font monospace per allineamento dei numeri
	var mono_font := ThemeDB.fallback_font
	_debug_label.add_theme_font_override("font", mono_font)
	vbox.add_child(_debug_label)
