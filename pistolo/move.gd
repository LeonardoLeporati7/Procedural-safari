## move.gd
## Controllore "fisico" dell'animale: gestisce velocity, pendenze, gravità,
## stamina, animazioni e salto automatico.
## NON legge più input da tastiera — la AI (animal_base.gd) lo pilota chiamando
## i metodi `ai_*` qui sotto.
##
## API per la AI (chiamabile da BehaviorController / AnimalBase):
##   ai_set_move_dir(dir, sprint) → dice "muoviti in direzione mondo `dir`,
##                                  sprint=true per galoppare". Vector3.ZERO ferma.
##   ai_stop()                    → ferma il movimento.
##   ai_request_attack()          → triggera un'animazione di attacco.
##   ai_set_eating(on)            → attiva/disattiva l'animazione di pasto.
extends CharacterBody3D

# ─── MOVIMENTO ───────────────────────────────────────────────────────────────
@export_group("Movimento")
@export var WALK_SPEED: float    = 5.0
@export var GALLOP_SPEED: float  = 12.0
@export var ACCELERATION: float  = 10.0
@export var FRICTION: float      = 10.0
@export var JUMP_VELOCITY: float = 6.0

# ─── ROTAZIONE ───────────────────────────────────────────────────────────────
@export_group("Rotazione")
## Velocità di rotazione automatica verso la direzione di movimento (rad/sec).
@export var TURN_SPEED: float    = 6.0
@export var visual_model: Node3D  # assegna "Fox" dall'Inspector

# ─── SALUTE ──────────────────────────────────────────────────────────────────
@export_group("Stato Salute")
@export var is_low_health: bool = false
@export var is_dead: bool       = false

# ─── STAMINA ─────────────────────────────────────────────────────────────────
@export_group("Stamina Sprint")
@export var STAMINA_MAX: float     = 5.0
@export var STAMINA_DRAIN: float   = 2.0
@export var STAMINA_RECOVER: float = 1.0

# ─── ATTACCO ─────────────────────────────────────────────────────────────────
@export_group("Attacco")
@export var ATTACK_COOLDOWN: float = 0.5

# ─── PENDENZA ────────────────────────────────────────────────────────────────
@export_group("Pendenza")
@export var MAX_SLOPE_ANGLE: float  = 45.0
@export var SLOPE_TILT_SPEED: float = 8.0
@export var SLOPE_BODY_MIN_ANGLE: float = 15.0  # sotto: solo IK, corpo dritto
@export var SLOPE_BODY_MAX_ANGLE: float = 35.0  # sopra: corpo al massimo influence
@export var SLOPE_BODY_MAX_INFLUENCE: float = 0.35  # mai oltre il 35% — il resto lo fa l'IK

@export var fr_rc: RayCast3D
@export var fl_rc: RayCast3D
@export var br_rc: RayCast3D
@export var bl_rc: RayCast3D

# ─── STATO INTERNO ───────────────────────────────────────────────────────────
var is_attacking: bool           = false
var is_eating: bool              = false
var stamina: float               = 0.0
var _sprint_locked: bool         = false
var attack_cooldown_timer: float = 0.0
var current_slope_angle: float   = 0.0
var slope_normal: Vector3        = Vector3.UP
var _smooth_normal: Vector3      = Vector3.UP
var _coyote_timer: float         = 0.0      # grazia prima di considerarsi "in aria"
var _auto_jump_cooldown: float   = 0.0      # cooldown per il salto automatico

# ─── COMANDI DA AI ───────────────────────────────────────────────────────────
var _ai_move_dir: Vector3        = Vector3.ZERO   # direzione XZ in spazio mondo
var _ai_sprint: bool             = false
var _ai_attack_requested: bool   = false

@export_group("Salto")
@export var COYOTE_TIME: float = 0.15       # secondi di tolleranza sui dislivelli

@export_group("Auto-Jump")
## Abilita il salto automatico quando in galoppo si incontra un ostacolo basso.
@export var AUTO_JUMP_ENABLED: bool        = true
## Anche al walk (non solo gallop). Default off — solo correndo.
@export var AUTO_JUMP_ON_WALK: bool        = false
## Distanza davanti all'animale alla quale "annusare" l'ostacolo.
@export var AUTO_JUMP_RAY_FORWARD: float   = 1.0
## Altezza dal suolo del raycast basso (piedi).
@export var AUTO_JUMP_LOW_Y: float         = 0.15
## Altezza massima ostacolo superabile con un salto.
@export var AUTO_JUMP_HIGH_Y: float        = 1.2
## Cooldown tra due salti automatici (sec) per evitare loop.
@export var AUTO_JUMP_COOLDOWN: float      = 0.5

@onready var anim_tree: AnimationTree = $AnimationTree

# Cache: alcune scene di animali NON hanno la condition "die" nell'AnimationTree
# (l'abbiamo aggiunta solo a fox/deer). Controlliamo una volta sola in _ready
# e usiamo questo flag per evitare errori a runtime.
var _has_die_condition: bool = false

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	anim_tree.active = true
	stamina = STAMINA_MAX

	# Mantieni il contatto col terreno su pendenze in giù (fix piedi in aria)
	floor_snap_length = 0.5
	# Allinea il rilevamento piano al MAX_SLOPE_ANGLE configurato
	floor_max_angle   = deg_to_rad(MAX_SLOPE_ANGLE)

	# Verifica una volta sola se l'AnimationTree espone "die"
	_has_die_condition = _anim_has_param("parameters/conditions/die")
	print("[DEATH 0] ", name, " _ready  _has_die_condition=", _has_die_condition,
		  "  anim_tree=", anim_tree)

## True se l'AnimationTree espone il parametro `path`.
func _anim_has_param(path: String) -> bool:
	if anim_tree == null: return false
	for prop in anim_tree.get_property_list():
		if prop.name == path:
			return true
	return false

# ─────────────────────────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if is_dead:
		_update_anim_conditions(false, false,false)
		return

	# 1. GRAVITÀ
	if not is_on_floor():
		velocity += get_gravity() * delta
		# NB: non azzerare is_eating qui — basta un singolo frame "in aria"
		# (terreno irregolare, jitter fisica) per spegnere l'animazione di
		# pasto e non viene più riaccesa perché _ensure_state non re-trigger.
		# Se l'animale deve smettere di mangiare, lo decide la AI via
		# ai_set_eating(false).

	# 2. RILEVAMENTO PENDENZA
	_check_slope()

	# 3. TIMERS
	attack_cooldown_timer = max(0.0, attack_cooldown_timer - delta)

	# 4. ATTACCO (richiesto dalla AI)
	if _ai_attack_requested and attack_cooldown_timer <= 0.0:
		is_attacking = true
		is_eating    = false
		attack_cooldown_timer = ATTACK_COOLDOWN
		get_tree().create_timer(0.5).timeout.connect(func(): is_attacking = false)
	_ai_attack_requested = false  # one-shot: consumato

	# 5. MANGIARE: gestito da ai_set_eating() — niente da fare qui

	# 6. DIREZIONE DI MOVIMENTO (dalla AI, in spazio MONDO)
	var direction := Vector3(_ai_move_dir.x, 0.0, _ai_move_dir.z)
	if direction.length() > 0.001:
		direction = direction.normalized()
	else:
		direction = Vector3.ZERO

	# 7. ROTAZIONE AUTOMATICA: ruota il body verso la direzione richiesta
	if direction.length() > 0.001 and not is_eating and not is_attacking:
		# I modelli hanno il forward su +Z, quindi atan2(x, z)
		var target_yaw := atan2(direction.x, direction.z)
		var rot_t := 1.0 - exp(-TURN_SPEED * delta)
		rotation.y = lerp_angle(rotation.y, target_yaw, rot_t)

	# 8. INTERRUZIONI LOGICHE
	if is_attacking or is_eating:
		direction = Vector3.ZERO

	# 9. SPRINT con isteresi (evita flickering walk/gallop a stamina 0)
	var is_sprinting = (
		_ai_sprint
		and is_on_floor()
		and direction.length() > 0.001
		and stamina > 0.0
		and not _sprint_locked
		and current_slope_angle <= MAX_SLOPE_ANGLE * 0.8
	)
	var current_speed = GALLOP_SPEED if is_sprinting else WALK_SPEED
	if current_slope_angle > 30.0:
		current_speed *= 0.7

	# 10. STAMINA
	if is_sprinting:
		stamina = max(0.0, stamina - STAMINA_DRAIN * delta)
		if stamina <= 0.0:
			_sprint_locked = true
	else:
		stamina = min(STAMINA_MAX, stamina + STAMINA_RECOVER * delta)
		if _sprint_locked and stamina >= STAMINA_MAX * 0.3:
			_sprint_locked = false

	# 11. PROIEZIONE DIREZIONE SULLA PENDENZA
	#     Usa Vector3.slide() per proiettare sul piano della pendenza in modo robusto.
	#     Funziona correttamente in qualsiasi direzione di movimento (salita, discesa, traverso).
	if direction.length() > 0.001 \
			and is_on_floor() \
			and current_slope_angle > 2.0 \
			and slope_normal.is_normalized():
		var projected = direction.slide(slope_normal)
		if projected.length() > 0.001:
			direction = projected.normalized()

	# 12. APPLICA VELOCITÀ
	if direction.length() > 0.001:
		velocity.x = move_toward(velocity.x, direction.x * current_speed, ACCELERATION * delta)
		velocity.z = move_toward(velocity.z, direction.z * current_speed, ACCELERATION * delta)
		# Componente Y: segue la direzione proiettata sulla pendenza.
		# Il clamp evita valori esplosivi su pendenze quasi verticali.
		if is_on_floor() and current_slope_angle > 2.0:
			var target_vy = direction.y * current_speed
			velocity.y = move_toward(velocity.y, target_vy, ACCELERATION * 2.0 * delta)
			velocity.y = clamp(velocity.y, -current_speed, current_speed)
	else:
		velocity.x = move_toward(velocity.x, 0, FRICTION * delta)
		velocity.z = move_toward(velocity.z, 0, FRICTION * delta)

	# 13. SALTO — scollegato dalla tastiera, ora è AUTOMATICO.
	# L'animale salta da solo quando, mentre corre (o cammina se attivato),
	# rileva davanti un ostacolo/dislivello superabile con un salto.
	var is_jumping := false
	_auto_jump_cooldown = max(0.0, _auto_jump_cooldown - delta)

	if AUTO_JUMP_ENABLED \
			and is_on_floor() \
			and not is_attacking and not is_eating \
			and _auto_jump_cooldown <= 0.0 \
			and direction.length() > 0.001 \
			and (is_sprinting or AUTO_JUMP_ON_WALK):
		if _detect_obstacle_ahead(direction):
			velocity.y = JUMP_VELOCITY
			is_jumping = true
			_auto_jump_cooldown = AUTO_JUMP_COOLDOWN

	# 14. FISICA
	move_and_slide()

	# 15. ANIMAZIONI + INCLINAZIONE VISIVA
	var h_speed   = Vector2(velocity.x, velocity.z).length()
	var is_moving = h_speed > 0.1
	_update_anim_conditions(is_moving, is_sprinting, is_jumping)

	if visual_model:
		_align_visual_to_slope(delta)


# ─── ALLINEAMENTO VISIVO ALLA PENDENZA ───────────────────────────────────────
# Il corpo segue la pendenza SOLO parzialmente (biologicamente corretto).
# Sotto SLOPE_BODY_MIN_ANGLE → corpo dritto, fa tutto l'IK.
# Tra MIN e MAX → influence cresce gradualmente fino a SLOPE_BODY_MAX_INFLUENCE.
# Sopra MAX → influence fissa al massimo.
func _align_visual_to_slope(delta: float) -> void:
	var target_normal := get_floor_normal() if is_on_floor() else Vector3.UP
	if target_normal.length_squared() < 0.01:
		target_normal = Vector3.UP

	# Calcola quanto il corpo deve seguire la pendenza in base all'angolo attuale
	# 0.0 = corpo sempre verticale  |  1.0 = corpo segue tutta la pendenza
	var body_influence := 0.0
	if current_slope_angle > SLOPE_BODY_MIN_ANGLE:
		body_influence = remap(
			current_slope_angle,
			SLOPE_BODY_MIN_ANGLE, SLOPE_BODY_MAX_ANGLE,
			0.0, SLOPE_BODY_MAX_INFLUENCE
		)
		body_influence = clamp(body_influence, 0.0, SLOPE_BODY_MAX_INFLUENCE)

	# Normale attenuata: mescola tra UP (corpo dritto) e la normale reale
	var attenuated_normal := Vector3.UP.lerp(target_normal, body_influence).normalized()

	# Smooth solo sulla normale attenuata — niente drift sulla basis
	_smooth_normal = _smooth_normal.lerp(attenuated_normal, SLOPE_TILT_SPEED * delta).normalized()

	# Forward sempre dal CharacterBody3D (si aggiorna con rotate_y)
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.001:
		fwd = Vector3(0, 0, -1)
	fwd = fwd.normalized()

	# Ricostruisce la basis da zero ogni frame — nessun drift
	var right := fwd.cross(_smooth_normal).normalized()
	var up    := _smooth_normal
	var front := up.cross(right).normalized()

	visual_model.global_transform.basis = Basis(right, up, -front).orthonormalized()


# ─── SLOPE CHECK ─────────────────────────────────────────────────────────────
func _check_slope() -> void:
	if not is_on_floor():
		current_slope_angle = 0.0
		slope_normal        = Vector3.UP
		return
	var n: Vector3 = get_floor_normal()
	# get_floor_normal() può ritornare Vector3.ZERO in casi edge (es. primo
	# frame di contatto): fallback a UP per evitare di passare un vettore
	# non normalizzato a slide() più avanti.
	if n.length_squared() < 0.0001:
		slope_normal        = Vector3.UP
		current_slope_angle = 0.0
		return
	slope_normal        = n.normalized()
	current_slope_angle = rad_to_deg(acos(clamp(slope_normal.dot(Vector3.UP), -1.0, 1.0)))


# ─── ANIMATION TREE ───────────────────────────────────────────────────────────
func _update_anim_conditions(is_moving: bool, is_sprinting: bool, is_jumping: bool) -> void:
	var p = "parameters/conditions/"
	anim_tree[p + "idle"]        = false
	anim_tree[p + "walk"]        = false
	anim_tree[p + "gallop"]      = false
	anim_tree[p + "gallop_jump"] = false
	anim_tree[p + "eating"]      = false
	anim_tree[p + "jump"]        = false
	anim_tree[p + "attack"]      = false
	# `die` settato SOLO se la scena ha la condition nell'AnimationTree.
	if _has_die_condition:
		anim_tree[p + "die"] = false
	if is_dead:
		if _has_die_condition:
			anim_tree[p + "die"] = true
			# [DEATH 8] log throttled ogni 60 frame fisici (~1s a 60fps)
			if Engine.get_physics_frames() % 60 == 0:
				var sm: AnimationNodeStateMachinePlayback = anim_tree.get("parameters/playback")
				print("[DEATH 8] _update_anim_conditions (is_dead) — ", name,
					  "  die=true  SM_current=", sm.get_current_node() if sm else "?")
		else:
			if Engine.get_physics_frames() % 60 == 0:
				push_warning("[DEATH 8] _update_anim_conditions: is_dead ma _has_die_condition=false su ",
							 name, " — animazione non parte. Aggiungi `die` nell'AnimationTree.")
		return

	if is_attacking:
		anim_tree[p + "attack"] = true
		return

	if is_jumping:
		if is_sprinting:
			anim_tree[p + "gallop_jump"] = true
		else:
			anim_tree[p + "jump"] = true
		return

	if is_eating:
		anim_tree[p + "eating"] = true
		return

	if is_moving:
		if is_sprinting:
			anim_tree[p + "gallop"] = true
		else:
			anim_tree[p + "walk"] = true
	else:
		anim_tree[p + "idle"] = true


# ─── API PUBBLICA PER LA AI ──────────────────────────────────────────────────
## Imposta la direzione di movimento in spazio MONDO (XZ; la Y è ignorata).
## La rotazione del body verso `world_dir` è automatica.
## Passa Vector3.ZERO per fermare, oppure chiama ai_stop().
func ai_set_move_dir(world_dir: Vector3, sprint: bool = false) -> void:
	_ai_move_dir = Vector3(world_dir.x, 0.0, world_dir.z)
	_ai_sprint   = sprint

## Ferma immediatamente il movimento (la velocità si scaricherà con FRICTION).
func ai_stop() -> void:
	_ai_move_dir = Vector3.ZERO
	_ai_sprint   = false

## Triggera un attacco al prossimo frame (one-shot, va richiamato per ogni attacco).
## L'animazione vera parte dentro _physics_process quando il cooldown è pronto.
func ai_request_attack() -> void:
	_ai_attack_requested = true

## Attiva/disattiva lo stato "sta mangiando o bevendo" (blocca movimento ed
## esegue l'animazione `eating` dell'AnimationTree).
func ai_set_eating(on: bool) -> void:
	is_eating = on
	if on:
		ai_stop()
	_apply_anim_eating(on)

## Mette/toglie l'animale dallo stato "morto". Blocca tutto e attiva la
## condition `die` dell'AnimationTree (transizioni Idle/Walk/Gallop/Attack →
## Death gestite nel .tscn).
func ai_set_dead(on: bool) -> void:
	# [DEATH 7] sempre, anche se changed=false, per debug
	print("[DEATH 7 ROOT] ai_set_dead(", on, ") su body=", name,
		  "  is_dead_prev=", is_dead,
		  "  anim_tree=", anim_tree,
		  "  _has_die_condition=", _has_die_condition)
	is_dead = on

	if anim_tree and _has_die_condition:
		anim_tree["parameters/conditions/die"] = on
		if on:
			var verify = anim_tree["parameters/conditions/die"]
			print("[DEATH 7b ROOT] anim_tree.die = ", verify)
			var sm: AnimationNodeStateMachinePlayback = anim_tree.get("parameters/playback")
			if sm:
				print("[DEATH 7c ROOT] StateMachine current=", sm.get_current_node())
			else:
				push_error("[DEATH 7c FAIL ROOT] parameters/playback non disponibile")
	elif on:
		push_error("[DEATH 7 FAIL ROOT] anim_tree=", anim_tree,
				   "  _has_die_condition=", _has_die_condition,
				   "  → la scena NON ha la condition 'die'.")

	if on:
		ai_stop()
		# Spegne le altre condizioni così non competono con la transizione → Death
		if anim_tree:
			var p := "parameters/conditions/"
			anim_tree[p + "idle"]        = false
			anim_tree[p + "walk"]        = false
			anim_tree[p + "gallop"]      = false
			anim_tree[p + "gallop_jump"] = false
			anim_tree[p + "eating"]      = false
			anim_tree[p + "jump"]        = false
			anim_tree[p + "attack"]      = false


# ─── HELPER ANIMAZIONI ───────────────────────────────────────────────────────
## Setta la condition "eating" subito (senza aspettare il prossimo
## _physics_process). Se on=true, mette anche idle/walk/gallop a false così
## l'AnimationTree fa transizione pulita.
func _apply_anim_eating(on: bool) -> void:
	if anim_tree == null: return
	var p := "parameters/conditions/"
	if on:
		anim_tree[p + "idle"]        = false
		anim_tree[p + "walk"]        = false
		anim_tree[p + "gallop"]      = false
		anim_tree[p + "gallop_jump"] = false
		anim_tree[p + "jump"]        = false
		anim_tree[p + "attack"]      = false
		anim_tree[p + "eating"]      = true
		# Forza esplicitamente la transizione verso lo stato Eating della
		# StateMachine (il solo parametro di condition non basta in tutti i casi).
		var sm: AnimationNodeStateMachinePlayback = anim_tree.get("parameters/playback")
		if sm: sm.travel("Eating")
	else:
		anim_tree[p + "eating"] = false
		# Il prossimo _physics_process deciderà se andare in walk/gallop/idle

## Spegne tutte le condition dell'AnimationTree (usato in caso di morte).
func _clear_all_anim_conditions() -> void:
	if anim_tree == null: return
	var p := "parameters/conditions/"
	anim_tree[p + "idle"]        = false
	anim_tree[p + "walk"]        = false
	anim_tree[p + "gallop"]      = false
	anim_tree[p + "gallop_jump"] = false
	anim_tree[p + "eating"]      = false
	anim_tree[p + "jump"]        = false
	anim_tree[p + "attack"]      = false
	anim_tree[p + "die"]     = false


# ─── AUTO-JUMP: RILEVAMENTO OSTACOLO ─────────────────────────────────────────
## Lancia due raycast davanti all'animale lungo la direzione di movimento:
##   - uno basso (all'altezza dei piedi)
##   - uno alto (all'altezza spalle/testa)
## Se quello basso COLPISCE qualcosa ma quello alto NON colpisce → l'ostacolo
## è abbastanza basso da poter essere superato con un salto → return true.
## Se anche quello alto colpisce, è un muro: non saltare.
func _detect_obstacle_ahead(move_dir: Vector3) -> bool:
	var dir := Vector3(move_dir.x, 0.0, move_dir.z)
	if dir.length_squared() < 0.001:
		return false
	dir = dir.normalized()

	var space := get_world_3d().direct_space_state
	var base  := global_position

	var low_origin := base + Vector3(0, AUTO_JUMP_LOW_Y, 0)
	var low_target := low_origin + dir * AUTO_JUMP_RAY_FORWARD
	var low_query  := PhysicsRayQueryParameters3D.create(low_origin, low_target)
	low_query.exclude = [self]
	var low_hit := space.intersect_ray(low_query)
	if low_hit.is_empty():
		return false

	var high_origin := base + Vector3(0, AUTO_JUMP_HIGH_Y, 0)
	var high_target := high_origin + dir * AUTO_JUMP_RAY_FORWARD
	var high_query  := PhysicsRayQueryParameters3D.create(high_origin, high_target)
	high_query.exclude = [self]
	var high_hit := space.intersect_ray(high_query)
	return high_hit.is_empty()
