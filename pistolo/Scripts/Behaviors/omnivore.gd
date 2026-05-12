## omnivore.gd
## Onnivoro: mangia sia piante che carne, comportamento opportunista.
## La preferenza tra piante e carne dipende dalla disponibilità e dalla fame.
## Esempi: cinghiale, orso, corvo.
##
## Nodi richiesti nel body:
##   - DetectionArea (Area3D)
##   - AttackArea    (Area3D, piccola) — usata se attacca

class_name Omnivore
extends AnimalBase

@export_group("Onnivoro")
@export var plant_eat_rate: float     = 15.0
@export var meat_eat_rate: float      = 22.0
@export var eat_heal_rate: float      = 6.0
@export var drink_rate: float         = 30.0
@export var attack_damage: float      = 20.0
@export var attack_cooldown: float    = 1.2
@export var attack_range: float       = 2.0
## Sopra questa urgenza fame preferisce carne (più calorica) alle piante
@export var prefer_meat_threshold: float = 0.65

# Rilevamento
var _food_plants: Array[Node3D]    = []
var _food_animals: Array[Node3D]   = []  # solo prede più piccole
var _water_sources: Array[Node3D]  = []
var _mates_near: Array[Node3D]     = []
var _threats: Array[Node3D]        = []

var _attack_timer: float  = 0.0
var _eating_timer: float  = 3.5
var _eating_plants: bool  = false   # true = sta mangiando piante, false = carne

# ─────────────────────────────────────────────────────────────────────────────
func _on_ready() -> void:
	move_speed   = 3.5
	sprint_speed = 8.0

	var attack_area := body.get_node_or_null("AttackArea") as Area3D
	if attack_area:
		attack_area.body_entered.connect(_on_attack_range_entered)

func _process(delta: float) -> void:
	_attack_timer = max(0.0, _attack_timer - delta)
	super._process(delta)

# ─────────────────────────────────────────────────────────────────────────────
func _compute_priorities() -> Dictionary:
	var p = super._compute_priorities()
	p.erase(State.SEEKING_FOOD)

	var hunger = needs["hunger"].urgency()
	var has_plants  = not _food_plants.is_empty()
	var has_animals = not _food_animals.is_empty()

	if hunger > seek_food_threshold:
		if hunger >= prefer_meat_threshold and has_animals:
			# Preferisce cacciare se abbastanza affamato e c'è una preda
			p[State.SEEKING_FOOD] = hunger * 0.92
		elif has_plants:
			# Altrimenti si accontenta delle piante
			p[State.SEEKING_FOOD] = hunger * 0.85
		elif has_animals:
			# Fallback: caccia anche a fame moderata se non ci sono piante
			p[State.SEEKING_FOOD] = hunger * 0.78

	p.erase(State.SEEKING_WATER)
	if needs["thirst"].urgency() > seek_water_threshold and not _water_sources.is_empty():
		p[State.SEEKING_WATER] = needs["thirst"].urgency() * 0.95

	p.erase(State.SEEKING_MATE)
	if needs["reproduction"].urgency() > seek_mate_threshold \
			and not _mates_near.is_empty() \
			and get_health_ratio() >= min_health_to_reproduce \
			and needs["energy"].urgency() < 0.5:
		p[State.SEEKING_MATE] = needs["reproduction"].urgency() * 0.68

	return p

# ─── TICK STATI ──────────────────────────────────────────────────────────────
func _tick_seek_food(delta: float) -> void:
	var hunger = needs["hunger"].urgency()

	# Decide cosa cercare in base alla fame e disponibilità
	var chase_animal: bool = hunger >= prefer_meat_threshold and not _food_animals.is_empty()

	if chase_animal:
		_food_animals = _food_animals.filter(
			func(a): return is_instance_valid(a) and a.is_inside_tree() and _is_alive(a)
		)
		if _food_animals.is_empty():
			chase_animal = false

	if chase_animal:
		_focus_target  = _get_closest(_food_animals)
		_eating_plants = false
	elif not _food_plants.is_empty():
		_food_plants   = _food_plants.filter(func(p): return is_instance_valid(p) and p.is_inside_tree())
		_focus_target  = _get_closest(_food_plants)
		_eating_plants = true
	else:
		_focus_target = null
		_ensure_state(State.WANDERING)
		return

	var dist = body.global_position.distance_to(_focus_target.global_position)
	if dist <= attack_range:
		if not _eating_plants:
			_attack()
		else:
			_eating_timer = 3.0
			_ensure_state(State.EATING)
	else:
		var speed = sprint_speed if not _eating_plants else move_speed
		_move_toward(_focus_target.global_position, speed, delta)

func _attack() -> void:
	if _attack_timer > 0.0: return
	_attack_timer = attack_cooldown
	var prey_ctrl := _focus_target.get_node_or_null("BehaviorController") as AnimalBase
	if prey_ctrl:
		prey_ctrl.take_damage(attack_damage)
		if not prey_ctrl.is_alive():
			_eating_timer = 3.5
			_eating_plants = false
			_ensure_state(State.EATING)

func _tick_eating(delta: float) -> void:
	var rate = plant_eat_rate if _eating_plants else meat_eat_rate
	needs["hunger"].satisfy(rate * delta)
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
	if body.global_position.distance_to(_focus_target.global_position) <= 2.0:
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
	if body.global_position.distance_to(_focus_target.global_position) <= 2.0:
		var partner_ctrl := _focus_target.get_node_or_null("BehaviorController") as AnimalBase
		if partner_ctrl and partner_ctrl.current_state == State.SEEKING_MATE:
			accept_mating(partner_ctrl)
	else:
		_move_toward(_focus_target.global_position, move_speed * 0.8, delta)

# ─── RILEVAMENTO ─────────────────────────────────────────────────────────────
func _on_body_detected(other: Node3D) -> void:
	var ctrl := other.get_node_or_null("BehaviorController")

	# Minacce: Carnivori o Onnivori più grandi
	if (ctrl is Carnivore or ctrl is Omnivore) and _is_bigger(other):
		add_threat(other)
		_threats.append(other)
		return

	# Prede: Erbivori o animali più piccoli
	if ctrl is Herbivore or (ctrl is Omnivore and _is_smaller(other)):
		_food_animals.append(other)
		return

	# Piante
	if other.is_in_group("food"):
		_food_plants.append(other)
		return

	# Acqua
	if other.is_in_group("water"):
		_water_sources.append(other)
		return

	# Mate: stesso tipo, sesso opposto
	if ctrl is Omnivore and ctrl._is_female != _is_female:
		_mates_near.append(other)

func _on_body_lost(other: Node3D) -> void:
	super._on_body_lost(other)
	_food_plants.erase(other)
	_food_animals.erase(other)
	_water_sources.erase(other)
	_mates_near.erase(other)
	_threats.erase(other)
	remove_threat(other)

func _on_attack_range_entered(other: Node3D) -> void:
	if other == _focus_target and _attack_timer <= 0.0 \
			and current_state == State.SEEKING_FOOD and not _eating_plants:
		_attack()

# ─── UTILITÀ ─────────────────────────────────────────────────────────────────
func _is_alive(node: Node3D) -> bool:
	var ctrl := node.get_node_or_null("BehaviorController") as AnimalBase
	return ctrl == null or ctrl.is_alive()

func _is_bigger(other: Node3D) -> bool:
	var ctrl := other.get_node_or_null("BehaviorController") as AnimalBase
	return ctrl != null and ctrl.max_health > max_health * 1.3

func _is_smaller(other: Node3D) -> bool:
	var ctrl := other.get_node_or_null("BehaviorController") as AnimalBase
	return ctrl != null and ctrl.max_health < max_health * 0.8
