## herbivore.gd
## Erbivoro: mangia piante, beve acqua, si riproduce, fugge dai predatori.
## Esempi: cervo, coniglio, zebra.
##
## Nodi richiesti nella scena del body:
##   - DetectionArea (Area3D)  → rileva cibo/acqua/minacce/mate
##   - CollisionShape3D sferica (raggio = detection_radius)
##
## Nota: per distinguere piante/acqua/predatori, usa i layer di collisione:
##   layer 1 = animali | layer 2 = piante | layer 3 = acqua

class_name Herbivore
extends AnimalBase

@export_group("Erbivoro")
@export var eat_rate: float        = 25.0   # punti fame recuperati/sec mentre mangia
@export var eat_heal_rate: float   = 5.0    # HP recuperati/sec mentre mangia
@export var drink_rate: float      = 30.0
@export var attack_range: float    = 2.0    # distanza alla quale attacca la pianta (o raggiunge acqua)

@export_group("Erbivoro/Ricerca")
## Raggio entro cui scansionare globalmente per cibo/acqua quando i bisogni
## sono critici (oltre la portata della DetectionArea). Simula olfatto/memoria.
@export var search_radius: float        = 60.0
## Ogni quanti secondi può ripetere la scansione globale (evita stress CPU).
@export var search_cooldown_sec: float  = 2.0

# Liste aggiornate dal rilevamento
var _food_sources: Array[Node3D]   = []   # piante/erba rilevate
var _water_sources: Array[Node3D]  = []   # punti acqua rilevati
var _predators_near: Array[Node3D] = []   # minacce rilevate
var _mates_near: Array[Node3D]     = []   # potenziali partner

# Timer scansioni globali (ms)
var _last_food_scan_ms: int  = -100000
var _last_water_scan_ms: int = -100000

# Throttle per i print di debug (ms)
var _last_seek_print_ms: int = -100000

# ─────────────────────────────────────────────────────────────────────────────
func _on_ready() -> void:
	# Override default: gli erbivori sono tendenzialmente più lenti e più sociali
	move_speed   = 3.0
	sprint_speed = 7.5
	# Protezione: l'attack_range NON deve mai essere ≤ 0 (altrimenti il check
	# `dist <= attack_range` non passa mai e l'animale non entra mai in
	# EATING/DRINKING). Se l'Inspector ha un valore strano (es. -1.85),
	# clampiamo a un minimo sano.
	if attack_range <= 0.0:
		push_warning("[%s] attack_range non valido (%.2f), clamp a 2.0" % [name, attack_range])
		attack_range = 2.0

# ─────────────────────────────────────────────────────────────────────────────
## Aggiunge la priorità HUNTING con una penalità per gli erbivori (non cacciano).
func _compute_priorities() -> Dictionary:
	var p = super._compute_priorities()

	# Se ha fame/sete e non ha fonti in vista, fai una scansione globale
	# (simula olfatto/memoria — trova la pianta o pozza d'acqua più vicina).
	if needs["hunger"].urgency() > seek_food_threshold and _food_sources.is_empty():
		_global_scan_into(_food_sources, "food", _last_food_scan_ms)
	if needs["thirst"].urgency() > seek_water_threshold and _water_sources.is_empty():
		_global_scan_into(_water_sources, "water", _last_water_scan_ms)

	# Gli erbivori non hanno mai SEEKING_FOOD → cibo = piante vicine
	p.erase(State.SEEKING_FOOD)
	if needs["hunger"].urgency() > seek_food_threshold and not _food_sources.is_empty():
		p[State.SEEKING_FOOD] = needs["hunger"].urgency() * 0.90

	# Acqua: cerca se c'è una fonte rilevata
	p.erase(State.SEEKING_WATER)
	if needs["thirst"].urgency() > seek_water_threshold and not _water_sources.is_empty():
		p[State.SEEKING_WATER] = needs["thirst"].urgency() * 0.95

	# Mate: cerca solo se ci sono partner nella zona
	p.erase(State.SEEKING_MATE)
	if needs["reproduction"].urgency() > seek_mate_threshold \
			and not _mates_near.is_empty() \
			and get_health_ratio() >= min_health_to_reproduce \
			and needs["energy"].urgency() < 0.5:
		p[State.SEEKING_MATE] = needs["reproduction"].urgency() * 0.70

	return p

# ─── TICK STATI ──────────────────────────────────────────────────────────────
func _tick_seek_food(delta: float) -> void:
	# Filtra invalidi e blacklistati (l'animale non riprova a target abbandonati)
	_food_sources = _food_sources.filter(
		func(f): return is_instance_valid(f) and f.is_inside_tree() and not is_blacklisted(f)
	)
	if _food_sources.is_empty():
		_focus_target = null
		_ensure_state(State.WANDERING)
		return

	_focus_target = _get_closest(_food_sources)
	var dist = body.global_position.distance_to(_focus_target.global_position)
	var effective_range: float = max(attack_range, 2.0)

	if dist <= effective_range:
		_ensure_state(State.EATING)
		return

	# Stuck detection: se non avanziamo da troppo tempo, blacklistiamo il
	# target (terreno impossibile?) e camminiamo via.
	if is_stuck(delta):
		print("[", body.name, "] STUCK su food, blacklist ", _focus_target.name)
		blacklist_target(_focus_target)
		var stuck_at: Vector3 = _focus_target.global_position
		_food_sources.erase(_focus_target)
		_focus_target = null
		wander_away_from(stuck_at)
		_ensure_state(State.WANDERING)
		return

	_move_toward(_focus_target.global_position, move_speed, delta)

func _tick_eating(delta: float) -> void:
	if not _focus_target or not is_instance_valid(_focus_target):
		_ensure_state(State.IDLE)
		return
	# Ruota il muso verso il target così l'animazione di pasto guarda la pianta
	_face_target(_focus_target.global_position, delta)
	# Stai mangiando: soddisfa fame e cura
	needs["hunger"].satisfy(eat_rate * delta)
	heal(eat_heal_rate * delta)
	# Finito di mangiare? Consuma l'albero/pianta e torna ad IDLE.
	if not needs["hunger"].is_critical(seek_food_threshold * 0.3):
		if is_instance_valid(_focus_target):
			_food_sources.erase(_focus_target)
			_focus_target.queue_free()
		_focus_target = null
		_ensure_state(State.IDLE)

func _tick_seek_water(delta: float) -> void:
	_water_sources = _water_sources.filter(
		func(f): return is_instance_valid(f) and f.is_inside_tree() and not is_blacklisted(f)
	)
	if _water_sources.is_empty():
		_focus_target = null
		_ensure_state(State.WANDERING)
		return

	_focus_target = _get_closest(_water_sources)
	var dist = body.global_position.distance_to(_focus_target.global_position)
	# L'acqua ha un range più stretto perché il marker è già esattamente sulla
	# riva (vedi acqua_2.gd marker_shore_offset). Vogliamo che l'animale ci
	# arrivi davvero sopra prima di iniziare a bere.
	var effective_range: float = clamp(attack_range, 1.2, 1.8)

	if dist <= effective_range:
		_ensure_state(State.DRINKING)
		return

	if is_stuck(delta):
		print("[", body.name, "] STUCK su water, blacklist ", _focus_target.name)
		blacklist_target(_focus_target)
		var stuck_at: Vector3 = _focus_target.global_position
		_water_sources.erase(_focus_target)
		_focus_target = null
		wander_away_from(stuck_at)
		_ensure_state(State.WANDERING)
		return

	_move_toward(_focus_target.global_position, move_speed, delta)

func _tick_drinking(delta: float) -> void:
	# Ruota il muso verso l'acqua così l'animazione di bere è diretta dal verso giusto
	if _focus_target and is_instance_valid(_focus_target):
		_face_target(_focus_target.global_position, delta)
	needs["thirst"].satisfy(drink_rate * delta)
	if not needs["thirst"].is_critical(0.1):
		_ensure_state(State.IDLE)

func _tick_seek_mate(delta: float) -> void:
	_mates_near = _mates_near.filter(func(m): return is_instance_valid(m) and m.is_inside_tree())
	if _mates_near.is_empty():
		_ensure_state(State.WANDERING)
		return

	_focus_target = _get_closest(_mates_near)
	var dist = body.global_position.distance_to(_focus_target.global_position)
	if dist <= 2.0:
		# Propone l'accoppiamento al partner
		var partner_ctrl := _focus_target.get_node_or_null("BehaviorController") as AnimalBase
		if partner_ctrl and partner_ctrl.current_state == State.SEEKING_MATE:
			accept_mating(partner_ctrl)
	else:
		_move_toward(_focus_target.global_position, move_speed * 0.8, delta)

# ─── RILEVAMENTO ─────────────────────────────────────────────────────────────
func _on_body_detected(other: Node3D) -> void:
	# Minaccia: qualunque Carnivore o Omnivore nella zona
	var ctrl := other.get_node_or_null("BehaviorController")
	if ctrl is Carnivore or ctrl is Omnivore:
		add_threat(other)
		_predators_near.append(other)
		return

	# Cibo: nodi nel gruppo "food" (erba, cespugli, ecc.)
	if other.is_in_group("food"):
		_food_sources.append(other)
		return

	# Acqua: nodi nel gruppo "water"
	if other.is_in_group("water"):
		_water_sources.append(other)
		return

	# Potenziale partner: stesso tipo, sesso opposto
	if ctrl:
		print(ctrl.get_class())
	if ctrl is Herbivore and ctrl._is_female != _is_female:
		_mates_near.append(other)

func _on_body_lost(other: Node3D) -> void:
	super._on_body_lost(other)
	_food_sources.erase(other)
	_water_sources.erase(other)
	_predators_near.erase(other)
	_mates_near.erase(other)
	remove_threat(other)

# ─── SCANSIONE GLOBALE (olfatto/memoria) ─────────────────────────────────────
## Cerca nei nodi del gruppo `group_name` il più vicino entro `search_radius`
## e lo aggiunge a `list`. Usa un cooldown (in ms) per non scandire ogni frame.
## `last_scan_ms_ref` non viene passato per riferimento (GDScript non lo permette
## sui primitivi): la funzione legge/scrive direttamente nelle variabili membro
## attraverso `group_name` ("food" o "water").
func _global_scan_into(list: Array[Node3D], group_name: String, _unused: int) -> void:
	var now: int = Time.get_ticks_msec()
	var last_ms: int
	if group_name == "food":
		last_ms = _last_food_scan_ms
	else:
		last_ms = _last_water_scan_ms

	if now - last_ms < int(search_cooldown_sec * 1000.0):
		return

	if group_name == "food":
		_last_food_scan_ms = now
	else:
		_last_water_scan_ms = now

	var best: Node3D = null
	var best_d2: float = search_radius * search_radius
	for n in get_tree().get_nodes_in_group(group_name):
		if not (n is Node3D) or not n.is_inside_tree():
			continue
		var d2: float = body.global_position.distance_squared_to(n.global_position)
		if d2 < best_d2:
			best_d2 = d2
			best = n
	if best and not list.has(best):
		list.append(best)
