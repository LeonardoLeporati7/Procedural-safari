## carnivore.gd
## Carnivoro: caccia prede, beve acqua, si riproduce, può fuggire da predatori più grandi.
## Esempi: lupo, leone, aquila.
##
## Nodi richiesti nel body:
##   - DetectionArea (Area3D, sfera grande)  → vista ampia
##   - AttackArea    (Area3D, sfera piccola) → zona corpo a corpo

class_name Carnivore
extends AnimalBase

@export_group("Caccia")
@export var attack_damage: float      = 30.0
@export var attack_cooldown: float    = 1.0
@export var attack_range: float       = 1.8
@export var give_up_time: float       = 8.0   # secondi prima di abbandonare la caccia
@export var give_up_distance: float   = 22.0  # distanza massima di inseguimento
@export var eat_rate: float           = 20.0  # soddisfazione fame mentre mangia carcassa
@export var eat_heal_rate: float      = 8.0
@export var drink_rate: float         = 30.0

# Liste rilevamento
var _prey_in_range: Array[Node3D]    = []
var _water_sources: Array[Node3D]    = []
var _mates_near: Array[Node3D]       = []
var _larger_threats: Array[Node3D]   = []

# Timer caccia
var _attack_timer: float    = 0.0
var _give_up_timer: float   = 0.0
var _eating_timer: float    = 4.0  # secondi per mangiare una carcassa

# ─────────────────────────────────────────────────────────────────────────────
func _on_ready() -> void:
	move_speed   = 4.0
	sprint_speed = 9.0

	var attack_area := body.get_node_or_null("AttackArea") as Area3D
	if attack_area:
		attack_area.body_entered.connect(_on_attack_range_entered)

# ─────────────────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	_attack_timer = max(0.0, _attack_timer - delta)
	super._process(delta)

func _compute_priorities() -> Dictionary:
	var p = super._compute_priorities()

	# Caccia: priorità cresce con la fame E la presenza di prede
	p.erase(State.SEEKING_FOOD)
	if needs["hunger"].urgency() > seek_food_threshold and not _prey_in_range.is_empty():
		p[State.SEEKING_FOOD] = needs["hunger"].urgency() * 0.92

	# Acqua
	p.erase(State.SEEKING_WATER)
	if needs["thirst"].urgency() > seek_water_threshold and not _water_sources.is_empty():
		p[State.SEEKING_WATER] = needs["thirst"].urgency() * 0.95

	# Mate
	p.erase(State.SEEKING_MATE)
	if needs["reproduction"].urgency() > seek_mate_threshold \
			and not _mates_near.is_empty() \
			and get_health_ratio() >= min_health_to_reproduce \
			and needs["energy"].urgency() < 0.5:
		p[State.SEEKING_MATE] = needs["reproduction"].urgency() * 0.68

	return p

# ─── TICK STATI ──────────────────────────────────────────────────────────────
func _tick_seek_food(delta: float) -> void:
	# Rimuovi prede morte o uscite dalla scena
	_prey_in_range = _prey_in_range.filter(
		func(p): return is_instance_valid(p) and p.is_inside_tree() and _is_alive_animal(p)
	)
	if _prey_in_range.is_empty():
		_focus_target = null
		_ensure_state(State.WANDERING)
		return

	_focus_target = _get_closest(_prey_in_range)
	var dist = body.global_position.distance_to(_focus_target.global_position)

	# Abbandona se troppo lontano o troppo a lungo senza avvicinarsi
	if dist > give_up_distance:
		_abandon_hunt()
		return
	_give_up_timer -= delta
	if _give_up_timer <= 0.0:
		_abandon_hunt()
		return

	if dist <= attack_range and _attack_timer <= 0.0:
		_attack()
	else:
		_move_toward(_focus_target.global_position, sprint_speed, delta)
		_give_up_timer = give_up_time  # aggiorna mentre ci si avvicina

func _abandon_hunt() -> void:
	_focus_target = null
	_give_up_timer = give_up_time
	_ensure_state(State.WANDERING)

func _attack() -> void:
	_attack_timer = attack_cooldown
	var prey_ctrl := _focus_target.get_node_or_null("BehaviorController") as AnimalBase
	if prey_ctrl:
		prey_ctrl.take_damage(attack_damage)
		# Se la preda è morta: passa a mangiare
		if not prey_ctrl.is_alive():
			_eating_timer = 4.0
			_ensure_state(State.EATING)

func _tick_eating(delta: float) -> void:
	needs["hunger"].satisfy(eat_rate * delta)
	heal(eat_heal_rate * delta)
	_eating_timer -= delta
	if _eating_timer <= 0.0 or not needs["hunger"].is_critical(0.1):
		_ensure_state(State.IDLE)

func _tick_seek_water(delta: float) -> void:
	_water_sources = _water_sources.filter(func(f): return is_instance_valid(f) and f.is_inside_tree())
	if _water_sources.is_empty():
		_ensure_state(State.WANDERING)
		return
	_focus_target = _get_closest(_water_sources)
	var dist = body.global_position.distance_to(_focus_target.global_position)
	if dist <= 2.0:
		_ensure_state(State.DRINKING)
	else:
		_move_toward(_focus_target.global_position, move_speed, delta)

func _tick_drinking(delta: float) -> void:
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
		var partner_ctrl := _focus_target.get_node_or_null("BehaviorController") as AnimalBase
		if partner_ctrl and partner_ctrl.current_state == State.SEEKING_MATE:
			accept_mating(partner_ctrl)
	else:
		_move_toward(_focus_target.global_position, move_speed * 0.8, delta)

# ─── RILEVAMENTO ─────────────────────────────────────────────────────────────
func _on_body_detected(other: Node3D) -> void:
	var ctrl := other.get_node_or_null("BehaviorController")

	# Predatori più grandi → fuga
	if ctrl is Carnivore and _is_bigger(other):
		add_threat(other)
		_larger_threats.append(other)
		return

	# Prede: Herbivore o animali più piccoli
	if ctrl is Herbivore or (ctrl is Omnivore and _is_smaller(other)):
		_prey_in_range.append(other)
		return

	# Acqua
	if other.is_in_group("water"):
		_water_sources.append(other)
		return

	# Mate: stesso tipo, sesso opposto
	if ctrl is Carnivore and ctrl._is_female != _is_female:
		_mates_near.append(other)

func _on_body_lost(other: Node3D) -> void:
	super._on_body_lost(other)
	_prey_in_range.erase(other)
	_water_sources.erase(other)
	_mates_near.erase(other)
	_larger_threats.erase(other)
	remove_threat(other)

func _on_attack_range_entered(other: Node3D) -> void:
	if other == _focus_target and _attack_timer <= 0.0 and current_state == State.SEEKING_FOOD:
		_attack()

# ─── UTILITÀ ─────────────────────────────────────────────────────────────────
func _is_alive_animal(node: Node3D) -> bool:
	var ctrl := node.get_node_or_null("BehaviorController") as AnimalBase
	return ctrl == null or ctrl.is_alive()

## Stima "grandezza" tramite max_health — estendibile con una stat dedicata
func _is_bigger(other: Node3D) -> bool:
	var ctrl := other.get_node_or_null("BehaviorController") as AnimalBase
	return ctrl != null and ctrl.max_health > max_health * 1.3

func _is_smaller(other: Node3D) -> bool:
	var ctrl := other.get_node_or_null("BehaviorController") as AnimalBase
	return ctrl != null and ctrl.max_health < max_health * 0.8
