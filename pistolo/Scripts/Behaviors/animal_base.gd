## animal_base.gd
## ─────────────────────────────────────────────────────────────────────────────
## Classe base per tutti gli animali dell'ecosistema.
## Usa un sistema di BISOGNI (Utility AI): ogni bisogno ha un'urgenza 0..1
## e lo stato con urgenza più alta prende il controllo.
##
## Gerarchia:
##   AnimalBase
##   ├── Herbivore  (mangia piante, fugge)
##   ├── Carnivore  (caccia, mangia carne)
##   └── Omnivore   (entrambi)
##
## Dove attaccare:
##   Aggiungi un nodo figlio "BehaviorController" (tipo: Node) alla radice
##   dell'animale e assegna lo script della sottoclasse (es. Herbivore).
## ─────────────────────────────────────────────────────────────────────────────

class_name AnimalBase
extends Node

# ─── SEGNALI ─────────────────────────────────────────────────────────────────
signal died(animal: AnimalBase)
signal state_changed(old: State, new_state: State)
signal reproduced(offspring_data: Dictionary)  # emesso quando nasce un figlio
signal need_critical(need_name: String)        # fame/sete critica → alert ecosistema

# ─── STATI ───────────────────────────────────────────────────────────────────
enum State {
	IDLE,
	WANDERING,
	SEEKING_FOOD,    # si avvicina a cibo/preda
	EATING,
	SEEKING_WATER,
	DRINKING,
	SLEEPING,        # recupera energia
	FLEEING,
	SEEKING_MATE,
	MATING,
	GESTATING,       # solo femmine (o animali ovipari)
	DEAD,
}

# ─── BISOGNI (inner class) ───────────────────────────────────────────────────
## Rappresenta un singolo bisogno dell'animale.
## urgency = 0.0 (soddisfatto) → 1.0 (critico)
class Need:
	var value: float        # valore attuale
	var max_value: float
	var drain_rate: float   # unità perse al secondo (0 = non si esaurisce da solo)
	var label: String

	func _init(p_label: String, p_max: float, p_drain: float) -> void:
		label      = p_label
		max_value  = p_max
		value      = p_max       # inizia soddisfatto
		drain_rate = p_drain

	## Urgenza: quanto è critico questo bisogno (0=ok, 1=disperato)
	func urgency() -> float:
		return 1.0 - clamp(value / max_value, 0.0, 1.0)

	## Avanza di delta secondi
	func tick(delta: float) -> void:
		value = max(0.0, value - drain_rate * delta)

	func satisfy(amount: float) -> void:
		value = min(max_value, value + amount)

	func is_critical(threshold: float = 0.8) -> bool:
		return urgency() >= threshold

# ─── EXPORT COMUNI ───────────────────────────────────────────────────────────
@export_group("Statistiche")
@export var max_health: float        = 100.0
@export var move_speed: float        = 3.5
@export var sprint_speed: float      = 7.0
## Velocità di rotazione (rad/sec). Più alto = gira più rapidamente verso la
## direzione di movimento. Valori tipici: 3.0 (lento, animale grande) – 12.0 (agile).
@export var turn_speed: float        = 6.0
## Quanto l'animale rallenta quando deve ancora ruotare verso la direzione target.
## 0.0 = velocità piena anche girando, 1.0 = si ferma del tutto fino ad allineamento.
@export_range(0.0, 1.0) var turn_brake: float = 0.85

@export_group("Bisogni - Drain rate (unità/sec)")
@export var hunger_drain: float      = 1.5
@export var thirst_drain: float      = 2.0
@export var energy_drain: float      = 0.8   # si esaurisce muovendosi
@export var repro_drain: float       = 0.3   # l'impulso riproduttivo cresce nel tempo

@export_group("Soglie urgenza")
@export var seek_food_threshold: float   = 0.45  # inizia a cercare cibo
@export var seek_water_threshold: float  = 0.50
@export var sleep_threshold: float       = 0.70  # energia troppo bassa → dorme
@export var seek_mate_threshold: float   = 0.60  # impulso riproduttivo alto → cerca mate

@export_group("Riproduzione")
@export var gestation_time: float    = 10.0  # secondi (scala con il tuo tempo di gioco)
@export var offspring_count_min: int = 1
@export var offspring_count_max: int = 3
@export var min_health_to_reproduce: float = 0.4  # almeno 40% HP per riprodursi

@export_group("Wander")
@export var wander_interval_min: float = 2.0
@export var wander_interval_max: float = 6.0
@export var idle_chance: float         = 0.35

# ─── STATO INTERNO ───────────────────────────────────────────────────────────
var health: float
var current_state: State = State.IDLE

## Dizionario dei bisogni — chiave: nome, valore: Need
var needs: Dictionary = {}

## Corpo fisico (genitore del BehaviorController)
var body: Node3D

## Cosa l'animale ha attualmente in "mente" (target di cibo, acqua, mate…)
var _focus_target: Node3D = null

# Timer / flag interni
var _wander_timer: float    = 0.0
var _wander_dir: Vector3    = Vector3.ZERO
var _flee_targets: Array[Node3D] = []
var _flee_timer: float      = 0.0
var _gestation_timer: float = 0.0
var _sleep_timer: float     = 0.0
var _is_female: bool        = true   # randomizzato in _ready o settabile dall'Inspector

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	body   = get_parent() as Node3D
	health = max_health
	_is_female = randf() > 0.5

	# Inizializza i 4 bisogni di base
	needs["hunger"]       = Need.new("hunger",       100.0, hunger_drain)
	needs["thirst"]       = Need.new("thirst",        100.0, thirst_drain)
	needs["energy"]       = Need.new("energy",        100.0, energy_drain)
	needs["reproduction"] = Need.new("reproduction",  100.0, repro_drain)
	# energy parte a metà per variare i cicli sonno/veglia
	needs["energy"].value = randf_range(50.0, 100.0)

	# Registrazione nel gruppo per UI/proximity scanning (es. animal_tooltip.gd)
	add_to_group("animal_behavior")

	_connect_detection_area()
	_on_ready()            # hook per le sottoclassi
	_reset_wander_timer()

## Hook per le sottoclassi — usalo invece di _ready() per evitare super()
func _on_ready() -> void:
	pass

# ─────────────────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if current_state == State.DEAD:
		return

	_tick_needs(delta)
	_check_critical_needs()

	# Priorità assoluta: fuga (viene dall'esterno, via segnale)
	if not _flee_targets.is_empty():
		_ensure_state(State.FLEEING)
	else:
		_choose_state()

	_tick_current_state(delta)

# ─── SISTEMA BISOGNI ─────────────────────────────────────────────────────────
func _tick_needs(delta: float) -> void:
	for need: Need in needs.values():
		need.tick(delta)
	# L'energia si consuma più velocemente mentre ci si muove
	if current_state in [State.SEEKING_FOOD, State.SEEKING_WATER,
						  State.SEEKING_MATE, State.FLEEING]:
		needs["energy"].tick(delta * 1.5)  # consumo extra durante attività intensa

func _check_critical_needs() -> void:
	for key in needs:
		if needs[key].is_critical(0.95):
			need_critical.emit(key)

# ─── SCELTA STATO (Utility AI) ───────────────────────────────────────────────
## Calcola le priorità e seleziona lo stato con urgenza più alta.
## Le sottoclassi possono override per aggiungere stati custom.
func _choose_state() -> void:
	# Non interrompere stati in corso (mangiare, bere, dormire, accoppiarsi)
	if current_state in [State.EATING, State.DRINKING, State.SLEEPING,
						  State.MATING, State.GESTATING]:
		return

	var priorities: Dictionary = _compute_priorities()
	var best_state  := State.IDLE
	var best_score  := 0.0

	for state in priorities:
		var score: float = priorities[state]
		if score > best_score:
			best_score = score
			best_state = state

	_ensure_state(best_state)

## Restituisce un dizionario { State → priorità 0..1 }.
## Override nelle sottoclassi per aggiungere/modificare priorità.
func _compute_priorities() -> Dictionary:
	var p := {}

	# Sonno: urgente quando l'energia è bassa
	var energy_urgency = needs["energy"].urgency()
	if energy_urgency > sleep_threshold:
		p[State.SLEEPING] = energy_urgency

	# Sete: seconda priorità biologica dopo il sonno
	var thirst_urgency = needs["thirst"].urgency()
	if thirst_urgency > seek_water_threshold:
		p[State.SEEKING_WATER] = thirst_urgency * 0.95

	# Fame
	var hunger_urgency = needs["hunger"].urgency()
	if hunger_urgency > seek_food_threshold:
		p[State.SEEKING_FOOD] = hunger_urgency * 0.90

	# Riproduzione: solo se salute sufficiente e energia ok
	var repro_urgency = needs["reproduction"].urgency()
	if repro_urgency > seek_mate_threshold \
			and get_health_ratio() >= min_health_to_reproduce \
			and needs["energy"].urgency() < 0.5:
		p[State.SEEKING_MATE] = repro_urgency * 0.70

	# Default: wandering/idle
	p[State.WANDERING] = 0.1

	return p

# ─── TICK PER STATO ──────────────────────────────────────────────────────────
func _tick_current_state(delta: float) -> void:
	match current_state:
		State.IDLE:
			_tick_idle(delta)
		State.WANDERING:
			_tick_wander(delta)
		State.SEEKING_FOOD:
			_tick_seek_food(delta)
		State.EATING:
			_tick_eating(delta)
		State.SEEKING_WATER:
			_tick_seek_water(delta)
		State.DRINKING:
			_tick_drinking(delta)
		State.SLEEPING:
			_tick_sleeping(delta)
		State.FLEEING:
			_tick_fleeing(delta)
		State.SEEKING_MATE:
			_tick_seek_mate(delta)
		State.MATING:
			_tick_mating(delta)
		State.GESTATING:
			_tick_gestating(delta)

# ─── STATI: IMPLEMENTAZIONI BASE ─────────────────────────────────────────────

func _tick_idle(delta: float) -> void:
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_decide_next_wander()

func _tick_wander(delta: float) -> void:
	_wander_timer -= delta
	_move_in_direction(_wander_dir, move_speed, delta)
	if _wander_timer <= 0.0:
		_decide_next_wander()

## Override nelle sottoclassi: vai verso il cibo/preda rilevata
func _tick_seek_food(_delta: float) -> void:
	if not _focus_target or not is_instance_valid(_focus_target):
		_ensure_state(State.WANDERING)

## Override nelle sottoclassi: logica di mangiare
func _tick_eating(_delta: float) -> void:
	pass

## Override nelle sottoclassi: vai verso l'acqua
func _tick_seek_water(_delta: float) -> void:
	if not _focus_target or not is_instance_valid(_focus_target):
		_ensure_state(State.WANDERING)

func _tick_drinking(delta: float) -> void:
	needs["thirst"].satisfy(20.0 * delta)
	if not needs["thirst"].is_critical(0.1):
		_ensure_state(State.IDLE)

func _tick_sleeping(delta: float) -> void:
	needs["energy"].satisfy(15.0 * delta)
	if not needs["energy"].is_critical(sleep_threshold * 0.3):
		_ensure_state(State.IDLE)

func _tick_fleeing(delta: float) -> void:
	_flee_targets = _flee_targets.filter(
		func(t): return is_instance_valid(t) and t.is_inside_tree()
	)
	if _flee_targets.is_empty():
		_flee_timer -= delta
		if _flee_timer <= 0.0:
			_ensure_state(State.IDLE)
		return

	var closest := _get_closest(_flee_targets)
	if closest:
		var away = (body.global_position - closest.global_position)
		away.y = 0.0
		_move_in_direction(away.normalized(), sprint_speed, delta)

func _tick_seek_mate(_delta: float) -> void:
	if not _focus_target or not is_instance_valid(_focus_target):
		_ensure_state(State.WANDERING)

func _tick_mating(delta: float) -> void:
	# Durata fissa 2 secondi, poi passa a gestazione (femmine) o idle (maschi)
	_sleep_timer -= delta   # riuso come timer generico
	if _sleep_timer <= 0.0:
		needs["reproduction"].satisfy(needs["reproduction"].max_value)
		if _is_female:
			_gestation_timer = gestation_time
			_ensure_state(State.GESTATING)
		else:
			_ensure_state(State.IDLE)

func _tick_gestating(delta: float) -> void:
	_gestation_timer -= delta
	if _gestation_timer <= 0.0:
		_give_birth()
		_ensure_state(State.IDLE)

# ─── RIPRODUZIONE ─────────────────────────────────────────────────────────────
func _give_birth() -> void:
	var count = randi_range(offspring_count_min, offspring_count_max)
	var data  = {
		"parent": self,
		"count":  count,
		"position": body.global_position,
		"species": get_script().resource_path,
	}
	reproduced.emit(data)
	# L'EcosystemManager (listener del segnale) spawna effettivamente i figli

## Chiamato da fuori quando un mate accetta l'accoppiamento
func accept_mating(partner: AnimalBase) -> void:
	if current_state == State.SEEKING_MATE and is_alive():
		_sleep_timer = 2.0   # durata mating
		_ensure_state(State.MATING)
		# Notifica il partner
		if partner.current_state != State.MATING:
			partner.accept_mating(self)

# ─── RILEVAMENTO (override nelle sottoclassi) ─────────────────────────────────
## Chiamato quando un body entra nell'Area3D di rilevamento.
## Le sottoclassi decidono se è cibo, acqua, minaccia o mate.
func _on_body_detected(other: Node3D) -> void:
	pass

func _on_body_lost(other: Node3D) -> void:
	if _focus_target == other:
		_focus_target = null

# ─── SALUTE ──────────────────────────────────────────────────────────────────
func take_damage(amount: float) -> void:
	if not is_alive(): return
	health = max(0.0, health - amount)
	if health <= 0.0:
		_die()

func heal(amount: float) -> void:
	health = min(max_health, health + amount)

func _die() -> void:
	_ensure_state(State.DEAD)
	died.emit(self)
	_on_death()

## Hook per animazioni di morte, drop risorse, ecc.
func _on_death() -> void:
	pass

# ─── MOVIMENTO ───────────────────────────────────────────────────────────────
## Muove il body verso `dir`, ma prima lo ruota gradualmente in quella direzione.
## L'animale si muove SEMPRE lungo il proprio forward attuale (-Z): se deve
## cambiare direzione di molto, prima gira la "testa" e poi parte, invece di
## scivolare all'indietro.
func _move_in_direction(dir: Vector3, speed: float, delta: float) -> void:
	if not body or dir.length_squared() < 0.001: return

	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.001: return
	flat = flat.normalized()

	# 1) Rotazione smooth verso la direzione desiderata (yaw attorno all'asse Y).
	# I modelli di questo progetto hanno il "naso" orientato lungo +Z.
	var target_yaw := atan2(flat.x, flat.z)
	var rot_t := 1.0 - exp(-turn_speed * delta)   # framerate-indipendent
	body.rotation.y = lerp_angle(body.rotation.y, target_yaw, rot_t)

	# 2) Calcola il forward attuale del body (dopo la rotazione).
	var forward := body.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.001: return
	forward = forward.normalized()

	# 3) Riduci la velocità finché non sei allineato al target.
	# alignment va da 0 (direzione opposta) a 1 (perfettamente allineato).
	var alignment := (forward.dot(flat) + 1.0) * 0.5
	var move_factor :float= lerp(1.0, alignment * alignment, turn_brake)

	if body is CharacterBody3D:
		var cb := body as CharacterBody3D
		if not cb.is_on_floor():
			cb.velocity += cb.get_gravity() * delta
		cb.velocity.x = forward.x * speed * move_factor
		cb.velocity.z = forward.z * speed * move_factor
		cb.move_and_slide()
	else:
		body.global_translate(forward * speed * move_factor * delta)

func _move_toward(target_pos: Vector3, speed: float, delta: float) -> void:
	var dir = target_pos - body.global_position
	dir.y = 0.0
	if dir.length_squared() < 0.04: return
	_move_in_direction(dir.normalized(), speed, delta)

# ─── WANDER ──────────────────────────────────────────────────────────────────
func _decide_next_wander() -> void:
	_reset_wander_timer()
	if randf() < idle_chance:
		_wander_dir = Vector3.ZERO
		_ensure_state(State.IDLE)
	else:
		var angle = randf_range(0.0, TAU)
		_wander_dir = Vector3(cos(angle), 0.0, sin(angle))
		_ensure_state(State.WANDERING)

func _reset_wander_timer() -> void:
	_wander_timer = randf_range(wander_interval_min, wander_interval_max)

# ─── AGGIUNGE MINACCIA (chiamabile da fuori) ───────────────────────────────
func add_threat(threat: Node3D) -> void:
	if not _flee_targets.has(threat):
		_flee_targets.append(threat)
		_flee_timer = 4.0

func remove_threat(threat: Node3D) -> void:
	_flee_targets.erase(threat)

# ─── UTILITÀ ─────────────────────────────────────────────────────────────────
func _connect_detection_area() -> void:
	var area := body.get_node_or_null("DetectionArea") as Area3D
	if area:
		area.body_entered.connect(_on_body_detected)
		area.body_exited.connect(_on_body_lost)
	else:
		push_warning(name + ": nessun nodo 'DetectionArea' nel body — il rilevamento non funzionerà.")

func _ensure_state(new_state: State) -> void:
	if new_state == current_state: return
	var old = current_state
	current_state = new_state
	state_changed.emit(old, new_state)

func _get_closest(list: Array[Node3D]) -> Node3D:
	var closest: Node3D = null
	var best := INF
	for n in list:
		var d = body.global_position.distance_squared_to(n.global_position)
		if d < best:
			best = d
			closest = n
	return closest

func is_alive() -> bool:
	return current_state != State.DEAD

func get_health_ratio() -> float:
	return health / max_health

func get_need_urgency(need_name: String) -> float:
	return needs[need_name].urgency() if needs.has(need_name) else 0.0
