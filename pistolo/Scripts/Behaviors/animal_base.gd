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

@export_group("Danno da inedia/disidratazione")
## Sopra questa urgenza, fame o sete iniziano a togliere vita.
@export var starvation_urgency_threshold: float = 0.95
## HP/sec persi quando la fame è al massimo (urgency >= soglia).
@export var hunger_damage_per_sec: float = 2.0
## HP/sec persi quando la sete è al massimo. La disidratazione uccide più
## velocemente della fame (realismo biologico).
@export var thirst_damage_per_sec: float = 3.0

@export_group("Riproduzione")
@export var gestation_time: float    = 10.0  # secondi (scala con il tuo tempo di gioco)
@export var offspring_count_min: int = 1
@export var offspring_count_max: int = 3
@export var min_health_to_reproduce: float = 0.4  # almeno 40% HP per riprodursi
## Scena da istanziare per ogni figlio (es. la .tscn del Deer/Fox).
## Se null, _give_birth() emette solo il segnale `reproduced` ma non spawna.
@export var offspring_scene: PackedScene
## Raggio (m) entro cui spawnare i cuccioli attorno alla madre.
@export var offspring_spawn_radius: float = 2.0
## Limite globale di animali di questa specie nella scena. Se superato, la
## madre completa la gestazione ma non nasce nessuno (evita esplosioni di
## popolazione). 0 = nessun limite.
@export var max_population: int = 30
## Cuccioli partono con questa frazione di max_health (es. 0.6 = 60%) così
## non sono "fragili" ma neanche pienamente adulti.
@export var offspring_starting_health_ratio: float = 0.8

@export_group("Cadavere")
## Secondi che la carcassa resta nella scena dopo la morte prima di sparire.
## Durante questo tempo è marcata come `carrion` (i carnivori la possono
## mangiare in futuro). Metti a 0 per non rimuoverla mai.
@export var corpse_duration_sec: float = 60.0
## Se ON, dopo la morte la CollisionShape3D del body viene disabilitata così
## gli altri animali possono camminarci sopra senza bloccarsi.
@export var disable_collision_on_death: bool = true

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

# ─── HYSTERESIS FLEEING ──────────────────────────────────────────────────────
## Tempo (ms) entro cui lo stato FLEEING viene forzato anche se _flee_targets è
## momentaneamente vuoto. Evita il ping-pong FLEEING↔SEEKING quando la minaccia
## esce dalla DetectionArea per pochi frame.
@export var flee_lock_duration_sec: float = 3.0
var _flee_lock_until_ms: int = -1

# ─── STUCK DETECTION ─────────────────────────────────────────────────────────
## Se l'animale resta praticamente fermo per più di questo tempo mentre cerca
## cibo/acqua/mate, abbandona il target corrente e cambia rotta.
@export var stuck_timeout_sec: float    = 2.5
## Velocità sotto la quale consideriamo "fermo" (m/s).
@export var stuck_speed_threshold: float = 0.3
## Durata di "blacklist" per un target abbandonato (sec).
@export var blacklist_duration_sec: float = 15.0
var _stuck_timer: float                 = 0.0
## Mappa target → timestamp (ms) di scadenza blacklist.
var _blacklisted: Dictionary            = {}

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	body   = get_parent() as Node3D
	health = max_health
	_is_female = randf() > 0.5

	if body == null:
		push_error("[AnimalBase] body è NULL — get_parent() non restituisce Node3D!")

	# Inizializza i 4 bisogni di base
	needs["hunger"]       = Need.new("hunger",       100.0, hunger_drain)
	needs["thirst"]       = Need.new("thirst",        100.0, thirst_drain)
	needs["energy"]       = Need.new("energy",        100.0, energy_drain)
	needs["reproduction"] = Need.new("reproduction",  100.0, repro_drain)
	# energy parte a metà per variare i cicli sonno/veglia
	needs["energy"].value = randf_range(50.0, 100.0)

	# Registrazione nel gruppo per UI/proximity scanning (es. animal_tooltip.gd)
	add_to_group("animal_behavior")
	# Anche il body, per simmetria col conteggio popolazione dei cuccioli.
	if body:
		body.add_to_group("animal_behavior")
		body.add_to_group(_species_group_name())

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
	_apply_starvation_damage(delta)
	# IMPORTANTE: _apply_starvation_damage può chiamare _die() che setta lo
	# stato a DEAD. Senza questo re-check, il blocco fleeing sotto
	# sovrascriverebbe DEAD con FLEEING e l'animale "resusciterebbe" in loop.
	if current_state == State.DEAD:
		return
	_cleanup_blacklist()

	# Priorità assoluta: fuga. Una volta che entriamo in FLEEING il timer di
	# lock impedisce di uscire (anche se la minaccia sparisce dalla detection
	# area per qualche frame): così evitiamo il ping-pong FLEEING↔SEEKING.
	var now_ms: int = Time.get_ticks_msec()
	if not _flee_targets.is_empty():
		_flee_lock_until_ms = now_ms + int(flee_lock_duration_sec * 1000.0)
		_ensure_state(State.FLEEING)
	elif now_ms < _flee_lock_until_ms:
		# Ancora dentro il lock: continuiamo a fuggire usando l'ultimo wander
		# come direzione (calcolato in _tick_fleeing che vede _flee_targets
		# vuoto e fa countdown del _flee_timer normale).
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

## Quando fame/sete restano sopra `starvation_urgency_threshold`, l'animale
## perde HP nel tempo. Se la vita arriva a 0, `take_damage()` chiama `_die()`.
## La sete fa danno più velocemente della fame (vedi default).
var _starvation_print_accum: float = 0.0
func _apply_starvation_damage(delta: float) -> void:
	if not is_alive(): return
	var total_dmg := 0.0
	if needs.has("hunger") and needs["hunger"].urgency() >= starvation_urgency_threshold:
		total_dmg += hunger_damage_per_sec * delta
	if needs.has("thirst") and needs["thirst"].urgency() >= starvation_urgency_threshold:
		total_dmg += thirst_damage_per_sec * delta
	if total_dmg > 0.0:
		take_damage(total_dmg)
		# Print HP ogni ~2 secondi mentre sta morendo di fame/sete, così
		# vedi che il danno c'è davvero (debugging del flusso morte).
		_starvation_print_accum += delta
		if _starvation_print_accum >= 2.0:
			_starvation_print_accum = 0.0
			var who: String = body.name if body else name
			print("[", who, "] STARVING — HP=", "%.1f" % health,
				  "/", max_health,
				  "  hunger=", "%.2f" % needs["hunger"].urgency(),
				  "  thirst=", "%.2f" % needs["thirst"].urgency())

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

## True se l'animale è attualmente DENTRO l'acqua (sotto il pelo). Si basa
## sulla posizione globale e cerca un nodo nel gruppo "water_body" per leggere
## il livello dell'acqua. Fallback: usa la quota del primo Marker3D nel
## gruppo "water" (che è ~la quota della riva).
func _is_above_water() -> bool:
	if body == null: return false
	# Heuristica: se ci sono marker d'acqua nel mondo, prendiamo la quota
	# del più vicino come "pelo dell'acqua". Se siamo sotto (y < shore_y),
	# siamo in acqua.
	var closest_water: Node3D = null
	var best_d2 := INF
	for n in get_tree().get_nodes_in_group("water"):
		if not (n is Node3D) or not n.is_inside_tree(): continue
		var d2: float = body.global_position.distance_squared_to(n.global_position)
		if d2 < best_d2:
			best_d2 = d2
			closest_water = n
	if closest_water == null:
		return true   # niente acqua trovata → trattalo come terraferma
	# Se siamo più di 1m sotto la quota del marker, siamo nel lago
	return body.global_position.y >= closest_water.global_position.y - 1.0

## Restituisce un dizionario { State → priorità 0..1 }.
## Override nelle sottoclassi per aggiungere/modificare priorità.
func _compute_priorities() -> Dictionary:
	var p := {}

	# Sonno: urgente quando l'energia è bassa — MA non se siamo nel lago.
	var energy_urgency = needs["energy"].urgency()
	if energy_urgency > sleep_threshold and _is_above_water():
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

	# Re-assert sul body lo stato "sta mangiando/bevendo" ogni frame: serve
	# perché move.gd può ricevere transienti (un frame in aria, ecc.) che
	# spengono l'animazione, e _ensure_state non rifa nulla se siamo già
	# in EATING/DRINKING.
	if body and body.has_method("ai_set_eating"):
		var should_eat := current_state == State.EATING or current_state == State.DRINKING
		body.ai_set_eating(should_eat)

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
## Genera N cuccioli istanziando `offspring_scene` attorno alla madre.
## Emette comunque il segnale `reproduced` per chi vuole ascoltarlo (UI,
## EcosystemManager, statistiche…).
func _give_birth() -> void:
	var count := randi_range(offspring_count_min, offspring_count_max)

	# Verifica limite di popolazione (per specie, identificata via gruppo)
	var species_group: String = _species_group_name()
	if max_population > 0:
		var alive_count := get_tree().get_nodes_in_group(species_group).size()
		if alive_count >= max_population:
			print("[", body.name, "] non partorisce: popolazione %s al limite (%d/%d)"
				  % [species_group, alive_count, max_population])
			reproduced.emit({"parent": self, "count": 0,
							 "position": body.global_position,
							 "species": species_group, "skipped": true})
			return

	# Spawn dei cuccioli
	var spawned: Array[Node] = []
	if offspring_scene == null:
		push_warning("[%s] offspring_scene NON assegnato — nessun cucciolo spawnato. "
					 % body.name + "Trascina la .tscn della specie nell'Inspector "
					 + "del BehaviorController, gruppo 'Riproduzione'.")
	else:
		var spawn_parent := body.get_parent()  # stesso layer della madre nella scena
		for i in count:
			var baby = offspring_scene.instantiate()
			spawn_parent.add_child(baby)
			# Posiziona attorno alla madre con offset casuale
			var angle = randf_range(0.0, TAU)
			var r = randf_range(0.5, offspring_spawn_radius)
			var offset = Vector3(cos(angle) * r, 0.0, sin(angle) * r)
			if baby is Node3D:
				baby.global_position = body.global_position + offset
			# Marca per il conteggio popolazione
			baby.add_to_group(species_group)
			# Imposta la salute iniziale (chiamato dopo _ready del baby)
			# Usiamo call_deferred così _ready del baby ha già creato il
			# BehaviorController e i needs.
			_apply_baby_init.call_deferred(baby)
			spawned.append(baby)
		print("[", body.name, "] ha partorito ", spawned.size(),
			  " ", species_group, " (popolazione totale: ",
			  get_tree().get_nodes_in_group(species_group).size(), ")")

	# Emetti il segnale per eventuali listener esterni
	reproduced.emit({
		"parent": self,
		"count":  spawned.size(),
		"position": body.global_position,
		"species": species_group,
	})

## Setta HP iniziali del cucciolo. Chiamato deferred così il BehaviorController
## del baby ha già finito il proprio _ready.
func _apply_baby_init(baby: Node) -> void:
	if not is_instance_valid(baby): return
	var baby_ctrl := AnimalBase.find_animal_ctrl(baby)
	if baby_ctrl:
		baby_ctrl.health = baby_ctrl.max_health * offspring_starting_health_ratio

## Nome del gruppo che identifica la specie. Usa il path dello script così
## ogni sottoclasse ha automaticamente un gruppo proprio (Herbivore.gd → "herbivore_pop").
func _species_group_name() -> String:
	var script := get_script() as Script
	if script == null: return "animal_pop"
	var path := script.resource_path
	# es. "res://scripts/Behaviors/herbivore.gd" → "herbivore_pop"
	var base := path.get_file().get_basename()
	return base + "_pop"

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
		var who: String = body.name if body else name
		print("[DEATH 2] take_damage → health ≤ 0 (", who, ") chiamo _die()")
		_die()

func heal(amount: float) -> void:
	health = min(max_health, health + amount)

func _die() -> void:
	var who: String = body.name if body else name
	print("[DEATH 3] _die() ENTRATO — ", who, "  HP=", health)
	_ensure_state(State.DEAD)
	died.emit(self)
	print("[DEATH 5] _die() chiama _on_death() per ", who)
	_on_death()
	print("[DEATH 9] _die() COMPLETATO per ", who)

## Eseguito quando l'animale muore.
##  1) Disabilita la fisica di collisione (così gli altri non sbattono contro
##     il cadavere e i predatori possono raggiungerlo per mangiarlo).
##  2) Smarca il body dai gruppi "live" (es. "animal_behavior") così non
##     compare più nei tooltip/proximity scan dei vivi.
##  3) Lo aggiunge al gruppo "carrion" — in futuro i carnivori potranno
##     trattarlo come fonte di cibo (carcassa).
##  4) Programma il queue_free dopo `corpse_duration_sec` secondi.
## Le sottoclassi possono override per drop risorse extra, particelle, ecc.
func _on_death() -> void:
	if body == null:
		push_error("[DEATH 6 FAIL] _on_death: body è NULL")
		return

	# 1) ANIMAZIONE DI MORTE — chiamata esplicita.
	if body.has_method("ai_set_dead"):
		print("[DEATH 6] _on_death → chiamo body.ai_set_dead(true) su ", body.name,
			  " (2a volta, idempotente)")
		body.ai_set_dead(true)
	else:
		push_error("[DEATH 6 FAIL] body=", body.name, " NON ha ai_set_dead")

	# 2) Disabilita la collisione (cerca CollisionShape3D figlio del body)
	if disable_collision_on_death:
		for child in body.get_children():
			if child is CollisionShape3D:
				(child as CollisionShape3D).disabled = true

	# 3) NON rimuoviamo subito da "animal_behavior": altrimenti il tooltip
	# (che usa quel gruppo per la proximity scan) smette di mostrare l'animale
	# e l'utente non vede mai lo stato "Morto". Resta nel gruppo finché il
	# body non viene queue_free'd dal timer del cadavere.
	# (rimozione spostata in _on_corpse_expired, sotto)

	# 4) Marca come carcassa per i carnivori
	body.add_to_group("carrion")

	# 5) Auto-cleanup dopo N secondi (se >0)
	if corpse_duration_sec > 0.0:
		var t := body.get_tree().create_timer(corpse_duration_sec)
		t.timeout.connect(_on_corpse_expired)

func _on_corpse_expired() -> void:
	if body and is_instance_valid(body):
		body.queue_free()

# ─── MOVIMENTO ───────────────────────────────────────────────────────────────
## Muove il body verso `dir`.
## - Se il body espone l'API `ai_set_move_dir` (move.gd), la usa: move.gd farà
##   rotazione smooth, gravità, pendenze, animazioni e auto-jump.
## - Altrimenti applica direttamente velocity + rotazione (fallback per body
##   "semplici" senza move.gd).
func _move_in_direction(dir: Vector3, speed: float, delta: float) -> void:
	if not body or dir.length_squared() < 0.001: return

	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.001: return
	flat = flat.normalized()

	# DELEGA A move.gd se disponibile
	if body.has_method("ai_set_move_dir"):
		# Sprint = chiamante sta usando una velocità "sopra" la cruise.
		var sprint := speed >= move_speed * 1.2
		body.ai_set_move_dir(flat, sprint)
		return

	# FALLBACK: gestione locale per body senza move.gd

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
		# Body (StaticBody3D, CharacterBody3D, RigidBody3D, ecc.)
		area.body_entered.connect(_on_body_detected)
		area.body_exited.connect(_on_body_lost)
		# Aree (es. zone d'acqua o cibo modellate come Area3D)
		area.area_entered.connect(_on_area_detected)
		area.area_exited.connect(_on_area_lost)
	else:
		push_warning(name + ": nessun nodo 'DetectionArea' nel body — il rilevamento non funzionerà.")

## Quando un'Area3D entra nella DetectionArea, la trattiamo come se fosse un
## body (cibo, acqua, ecc.). Le sottoclassi possono override.
func _on_area_detected(other: Area3D) -> void:
	_on_body_detected(other)

func _on_area_lost(other: Area3D) -> void:
	_on_body_lost(other)

func _ensure_state(new_state: State) -> void:
	if new_state == current_state: return
	var old = current_state
	current_state = new_state
	state_changed.emit(old, new_state)

	# Log di transizione (utile per debugging future regressioni)
	var who: String = body.name if body else name
	print("[", who, "] ", State.keys()[old], " → ", State.keys()[new_state])

	# Notifica il body (se ha API move.gd) di stati "non-movimento" e morte
	if body:
		if body.has_method("ai_stop") and new_state in [
				State.IDLE, State.EATING, State.DRINKING,
				State.SLEEPING, State.MATING, State.GESTATING, State.DEAD]:
			body.ai_stop()
		# Animazione "eating" condivisa per mangiare e bere (testa giù).
		if body.has_method("ai_set_eating"):
			body.ai_set_eating(new_state == State.EATING or new_state == State.DRINKING)
		if new_state == State.DEAD:
			if body.has_method("ai_set_dead"):
				print("[DEATH 4] _ensure_state(DEAD) → chiamo body.ai_set_dead(true) su ", body.name)
				body.ai_set_dead(true)
			else:
				push_error("[DEATH 4 FAIL] body=", body.name, " NON ha ai_set_dead — animazione morte impossibile")

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

## Restituisce true se l'animale è femmina (settato a random in _ready).
func is_female() -> bool:
	return _is_female

## Quanti body fisici sono attualmente dentro la DetectionArea (tutti, senza
## filtri per tipo). Utile per il debug del rilevamento.
func get_detected_count() -> int:
	if not body: return 0
	var area := body.get_node_or_null("DetectionArea") as Area3D
	if not area: return 0
	# Esclude se stessi nel conteggio
	var bodies := area.get_overlapping_bodies()
	var count := 0
	for b in bodies:
		if b != body:
			count += 1
	return count

## Quanti animali sono attualmente nella lista delle minacce attive (fuga).
func get_threats_count() -> int:
	return _flee_targets.size()

## Trova il BehaviorController di un altro body, in modo ROBUSTO:
##  1) cerca il figlio chiamato "BehaviorController" (nome standard)
##  2) se non lo trova, cerca tra i figli quello che ha uno script che estende
##     AnimalBase (funziona qualunque sia il nome del nodo).
## Restituisce null se il body non è un animale.
static func find_animal_ctrl(b: Node) -> AnimalBase:
	if b == null: return null
	var ctrl := b.get_node_or_null("BehaviorController") as AnimalBase
	if ctrl: return ctrl
	for child in b.get_children():
		if child is AnimalBase:
			return child as AnimalBase
	return null

## Ruota lentamente il body per guardare verso `world_pos` (solo asse Y).
## Usato quando l'animale sta mangiando/bevendo: deve guardare il target,
## non mantenere l'orientamento di approccio.
func _face_target(world_pos: Vector3, delta: float) -> void:
	if body == null: return
	var to := world_pos - body.global_position
	to.y = 0.0
	if to.length_squared() < 0.01: return
	to = to.normalized()
	# I modelli del progetto hanno il forward su +Z → atan2(x, z)
	var target_yaw := atan2(to.x, to.z)
	var rot_t := 1.0 - exp(-turn_speed * delta)
	body.rotation.y = lerp_angle(body.rotation.y, target_yaw, rot_t)

## Stuck detection: chiamata dalle sottoclassi dentro _tick_seek_*.
## Restituisce true se l'animale è bloccato (velocità ~0 da troppo tempo);
## in tal caso la sottoclasse dovrebbe blacklistare il target e cambiare rotta.
func is_stuck(delta: float) -> bool:
	if body == null or not (body is CharacterBody3D):
		return false
	var cb := body as CharacterBody3D
	var sp := Vector2(cb.velocity.x, cb.velocity.z).length()
	if sp < stuck_speed_threshold:
		_stuck_timer += delta
	else:
		_stuck_timer = 0.0
	if _stuck_timer >= stuck_timeout_sec:
		_stuck_timer = 0.0
		return true
	return false

## Aggiunge un target alla blacklist (l'animale lo eviterà per un po').
func blacklist_target(target: Node3D) -> void:
	if target == null: return
	var expire_ms := Time.get_ticks_msec() + int(blacklist_duration_sec * 1000.0)
	_blacklisted[target] = expire_ms
	var who: String = body.name if body else name
	print("[", who, "] blacklisto target ", target.name, " per ", blacklist_duration_sec, "s")

## True se `target` è attualmente blacklistato.
func is_blacklisted(target: Node3D) -> bool:
	if target == null or not _blacklisted.has(target):
		return false
	return Time.get_ticks_msec() < _blacklisted[target]

## Rimuove dalla blacklist gli entries scaduti o invalidi.
func _cleanup_blacklist() -> void:
	var now := Time.get_ticks_msec()
	var to_remove := []
	for t in _blacklisted:
		if not is_instance_valid(t) or now >= _blacklisted[t]:
			to_remove.append(t)
	for t in to_remove:
		_blacklisted.erase(t)

## Quando un animale si blocca cercando un target, gli diamo una direzione
## di "scappa" opposta al target — così esce dalla zona impossibile.
func wander_away_from(point: Vector3) -> void:
	if body == null: return
	var dir := body.global_position - point
	dir.y = 0.0
	if dir.length_squared() < 0.001:
		var angle = randf_range(0.0, TAU)
		_wander_dir = Vector3(cos(angle), 0.0, sin(angle))
	else:
		_wander_dir = dir.normalized()
	_wander_timer = randf_range(wander_interval_min, wander_interval_max)

## Restituisce un'etichetta leggibile dello stato corrente (in italiano).
func get_state_label() -> String:
	match current_state:
		State.IDLE:          return "Riposa"
		State.WANDERING:     return "Vagando"
		State.SEEKING_FOOD:  return "Cerca cibo"
		State.EATING:        return "Mangia"
		State.SEEKING_WATER: return "Cerca acqua"
		State.DRINKING:      return "Beve"
		State.SLEEPING:      return "Dorme"
		State.FLEEING:       return "In fuga"
		State.SEEKING_MATE:  return "Cerca partner"
		State.MATING:        return "Accoppiamento"
		State.GESTATING:     return "Gestazione"
		State.DEAD:          return "Morto"
	return "?"
