## predator_behavior.gd
## Comportamento cacciatore: vagabonda, rileva le prede, le insegue e le attacca.
##
## Come usarlo:
##   1. Nella scena del predatore (es. wolf.tscn), aggiungi un nodo figlio
##      di tipo Node e chiamalo "BehaviorController"
##   2. Assegna questo script al BehaviorController
##   3. Aggiungi un nodo Area3D chiamato "DetectionArea" con CollisionShape3D
##      come figlio del body (raggio detection_radius)
##   4. Aggiungi un Area3D chiamato "AttackArea" più piccolo (raggio attack_range)

class_name Predator
extends AnimalBase

# ─── CACCIA ──────────────────────────────────────────────────────────────────
@export_group("Caccia")
@export var chase_speed_multiplier: float = 1.5    # velocità inseguimento
@export var attack_range: float = 1.5              # distanza entro cui attacca
@export var attack_damage: float = 25.0
@export var attack_cooldown: float = 1.2           # secondi tra un attacco e l'altro
@export var give_up_distance: float = 20.0         # abbandona la caccia oltre questa distanza
@export var give_up_time: float = 8.0              # oppure dopo N secondi senza avvicinarsi

# ─── FAME ────────────────────────────────────────────────────────────────────
@export_group("Fame")
@export var hunger_max: float    = 100.0
@export var hunger_drain: float  = 1.5   # unità / secondo
@export var hunt_hunger_threshold: float = 0.6  # sotto questa % di fame, inizia a cacciare

# ─── STATO INTERNO ───────────────────────────────────────────────────────────
var _prey_in_range: Array[Node3D] = []    # prede nell'area di rilevamento
var _current_target: Node3D = null
var _attack_timer: float = 0.0
var _give_up_timer: float = 0.0
var _hunger: float
var _last_dist_to_target: float = INF

# ─────────────────────────────────────────────────────────────────────────────
func _on_ready() -> void:
	_hunger = hunger_max

	var detect_area := body.get_node_or_null("DetectionArea") as Area3D
	if detect_area:
		detect_area.body_entered.connect(_on_prey_detected)
		detect_area.body_exited.connect(_on_prey_left)
	else:
		push_warning(name + ": nessun nodo 'DetectionArea' trovato nel body.")

	var attack_area := body.get_node_or_null("AttackArea") as Area3D
	if attack_area:
		attack_area.body_entered.connect(_on_attack_range_entered)

# ─────────────────────────────────────────────────────────────────────────────
func _tick(delta: float) -> void:
	_hunger = max(0.0, _hunger - hunger_drain * delta)
	_attack_timer = max(0.0, _attack_timer - delta)

	match current_state:
		State.IDLE, State.WANDERING:
			_tick_idle(delta)
			_tick_wander(delta)
			# Inizia la caccia se ha fame e c'è una preda vicina
			if is_hungry() and not _prey_in_range.is_empty():
				_start_hunt()

		State.HUNTING:
			_tick_hunt(delta)

		State.EATING:
			_tick_eat_prey(delta)

# ─── CACCIA ──────────────────────────────────────────────────────────────────
func _start_hunt() -> void:
	_current_target = _get_closest_prey()
	if _current_target:
		_give_up_timer = give_up_time
		_last_dist_to_target = INF
		_set_state(State.HUNTING)

func _tick_hunt(delta: float) -> void:
	# Verifica che il target sia ancora valido
	if not is_instance_valid(_current_target) \
			or not _current_target.is_inside_tree() \
			or _is_target_dead():
		_abandon_hunt()
		return

	var dist = body.global_position.distance_to(_current_target.global_position)

	# Abbandona se troppo lontano
	if dist > give_up_distance:
		_abandon_hunt()
		return

	# Abbandona se non si avvicina nel tempo
	if dist >= _last_dist_to_target:
		_give_up_timer -= delta
		if _give_up_timer <= 0.0:
			_abandon_hunt()
			return
	else:
		_give_up_timer = give_up_time  # si sta avvicinando: resetta il timer

	_last_dist_to_target = dist

	# Avanza verso il target
	_move_toward_position(_current_target.global_position, sprint_speed * chase_speed_multiplier, delta)

	# Attacca se vicino e cooldown pronto
	if dist <= attack_range and _attack_timer <= 0.0:
		_attack()

func _attack() -> void:
	_attack_timer = attack_cooldown
	# Infligge danno al BehaviorController (AnimalBase) della preda
	var prey_behavior := _current_target.get_node_or_null("BehaviorController") as AnimalBase
	if prey_behavior:
		prey_behavior.take_damage(attack_damage)

func _abandon_hunt() -> void:
	_current_target = null
	_set_state(State.IDLE)

func _tick_eat_prey(delta: float) -> void:
	# Recupera fame mangiando la preda uccisa
	_hunger = min(hunger_max, _hunger + 30.0 * delta)
	if _hunger >= hunger_max * 0.9:
		_set_state(State.IDLE)

# ─── RILEVAMENTO ─────────────────────────────────────────────────────────────
func _on_prey_detected(other: Node3D) -> void:
	var behavior := other.get_node_or_null("BehaviorController")
	if behavior is Prey:
		if not _prey_in_range.has(other):
			_prey_in_range.append(other)
		# Inizia subito la caccia se ha fame e non stava già cacciando
		if is_hungry() and current_state != State.HUNTING:
			_start_hunt()

func _on_prey_left(other: Node3D) -> void:
	_prey_in_range.erase(other)
	if _current_target == other:
		_abandon_hunt()

func _on_attack_range_entered(other: Node3D) -> void:
	# Attacco immediato se è la preda corrente e il cooldown è pronto
	if other == _current_target and _attack_timer <= 0.0:
		_attack()

# ─── MORTE PREDA ─────────────────────────────────────────────────────────────
func _is_target_dead() -> bool:
	var behavior := _current_target.get_node_or_null("BehaviorController") as AnimalBase
	if behavior:
		return not behavior.is_alive()
	return false

## Chiamato da outside quando una preda muore vicino al predatore
func notify_prey_killed(prey_body: Node3D) -> void:
	if prey_body == _current_target:
		_set_state(State.EATING)
		_current_target = null

# ─── UTILITÀ ─────────────────────────────────────────────────────────────────
func _get_closest_prey() -> Node3D:
	_prey_in_range = _prey_in_range.filter(
		func(p): return is_instance_valid(p) and p.is_inside_tree()
	)
	var closest: Node3D = null
	var closest_dist := INF
	for p in _prey_in_range:
		var d = body.global_position.distance_squared_to(p.global_position)
		if d < closest_dist:
			closest_dist = d
			closest = p
	return closest

func is_hungry() -> bool:
	return _hunger < hunger_max * hunt_hunger_threshold

func get_hunger_ratio() -> float:
	return _hunger / hunger_max
