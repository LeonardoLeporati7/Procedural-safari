## prey_behavior.gd
## Comportamento preda: vagabonda, rileva i predatori vicini e fugge.
##
## Come usarlo:
##   1. Nella scena della preda (es. deer.tscn), aggiungi un nodo figlio
##      di tipo Node e chiamalo "BehaviorController"
##   2. Assegna questo script al BehaviorController
##   3. Aggiungi un nodo Area3D chiamato "DetectionArea" con CollisionShape3D
##      come figlio del body, raggio = detection_radius
##   4. Nel body aggiungi un export var detection_area: Area3D e
##      collega i segnali body_entered/body_exited

class_name Prey
extends AnimalBase

# ─── FUGA ────────────────────────────────────────────────────────────────────
@export_group("Fuga")
@export var flee_speed_multiplier: float = 1.8   # velocità fuga = sprint_speed * mult
@export var flee_duration_after_lose: float = 3.0 # secondi di fuga dopo che il predatore sparisce
@export var safe_distance: float = 12.0           # torna all'idle sopra questa distanza

# ─── CIBO ────────────────────────────────────────────────────────────────────
@export_group("Alimentazione")
@export var hunger_max: float   = 100.0
@export var hunger_drain: float = 2.0    # unità / secondo
@export var eat_duration: float = 3.0    # secondi per mangiare
@export var eat_heal: float     = 20.0   # HP recuperati mangiando

# ─── STATO INTERNO ───────────────────────────────────────────────────────────
var _threats: Array[Node3D]   = []   # predatori rilevati nell'area
var _flee_target: Vector3     = Vector3.ZERO
var _flee_timer: float        = 0.0
var _hunger: float
var _eat_timer: float         = 0.0

# ─────────────────────────────────────────────────────────────────────────────
func _on_ready() -> void:
	_hunger = hunger_max
	# Connette l'Area3D di rilevamento se presente nel body
	var area := body.get_node_or_null("DetectionArea") as Area3D
	if area:
		area.body_entered.connect(_on_body_entered)
		area.body_exited.connect(_on_body_exited)
	else:
		push_warning(name + ": nessun nodo 'DetectionArea' trovato nel body. Il rilevamento predatori non funzionerà.")

# ─────────────────────────────────────────────────────────────────────────────
func _tick(delta: float) -> void:
	_hunger = max(0.0, _hunger - hunger_drain * delta)

	match current_state:
		State.IDLE, State.WANDERING:
			_tick_idle(delta)
			_tick_wander(delta)
			_check_threats()

		State.FLEEING:
			_tick_flee(delta)

		State.EATING:
			_tick_eat(delta)

# ─── FUGA ────────────────────────────────────────────────────────────────────
func _check_threats() -> void:
	# Rimuovi minacce morte o uscite dall'area
	_threats = _threats.filter(func(t): return is_instance_valid(t) and t.is_inside_tree())

	if _threats.is_empty():
		return

	# Calcola direzione opposta alla minaccia più vicina
	var closest_threat := _get_closest_threat()
	if closest_threat:
		var away = (body.global_position - closest_threat.global_position)
		away.y = 0.0
		_flee_target = body.global_position + away.normalized() * safe_distance
		_flee_timer = flee_duration_after_lose
		_set_state(State.FLEEING)

func _tick_flee(delta: float) -> void:
	if _threats.is_empty():
		_flee_timer -= delta
		if _flee_timer <= 0.0:
			_set_state(State.IDLE)
			return

	var flee_dir = (_flee_target - body.global_position)
	flee_dir.y = 0.0
	_move_toward_direction(flee_dir.normalized(), sprint_speed * flee_speed_multiplier, delta)

# ─── MANGIARE ────────────────────────────────────────────────────────────────
func _tick_eat(delta: float) -> void:
	_eat_timer -= delta
	if _eat_timer <= 0.0:
		heal(eat_heal)
		_hunger = min(hunger_max, _hunger + eat_heal)
		_set_state(State.IDLE)

## Chiama questo metodo quando la preda entra in contatto con cibo (erba, ecc.)
func start_eating() -> void:
	if current_state == State.FLEEING or not is_alive():
		return
	_eat_timer = eat_duration
	_set_state(State.EATING)

# ─── RILEVAMENTO ─────────────────────────────────────────────────────────────
func _on_body_entered(other: Node3D) -> void:
	# Considera minaccia solo i Predator
	var behavior := other.get_node_or_null("BehaviorController")
	if behavior is Predator:
		if not _threats.has(other):
			_threats.append(other)

func _on_body_exited(other: Node3D) -> void:
	_threats.erase(other)
	# Inizia il countdown di fuga ancora per flee_duration_after_lose secondi
	if _threats.is_empty() and current_state == State.FLEEING:
		_flee_timer = flee_duration_after_lose

# ─── UTILITÀ ─────────────────────────────────────────────────────────────────
func _get_closest_threat() -> Node3D:
	var closest: Node3D = null
	var closest_dist := INF
	for t in _threats:
		var d = body.global_position.distance_squared_to(t.global_position)
		if d < closest_dist:
			closest_dist = d
			closest = t
	return closest

func get_hunger_ratio() -> float:
	return _hunger / hunger_max

func is_hungry() -> bool:
	return _hunger < hunger_max * 0.4
