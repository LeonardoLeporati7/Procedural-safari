extends CharacterBody3D

# --- CONFIGURAZIONE ---
@export_group("Movimento")
@export var WALK_SPEED = 5.0
@export var GALLOP_SPEED = 12.0
@export var ACCELERATION = 10.0
@export var FRICTION = 10.0
@export var JUMP_VELOCITY = 6.0

@export_group("Rotazione")
const ROTATION_SPEED = 2.0 # Velocità rotazione manuale (Frecce)

@export_group("Stato Salute")
@export var is_low_health: bool = false
@export var is_dead: bool = false

# --- STATI AZIONE ---
var is_attacking: bool = false
var is_eating: bool = false

# Timer e Riferimenti
var idle_timer: float = 0.0
@onready var anim_tree: AnimationTree = $AnimationTree

func _ready():
	anim_tree.active = true

func _physics_process(delta: float) -> void:
	# 0. MORTE: Se morto, ferma tutto e aggiorna solo animazione
	if is_dead:
		_update_anim_conditions(false, false, 0.0)
		return

	# 1. GRAVITÀ
	if not is_on_floor():
		velocity += get_gravity() * delta
		# Se cadiamo (es. burrone), smettiamo di mangiare
		is_eating = false

	# 2. INPUT: ATTACCO (Click Sinistro)
	if Input.is_action_just_pressed("Attack"):
		is_attacking = true
		is_eating = false # L'attacco interrompe il cibo
		# Timer per resettare l'attacco (regola 0.5 in base alla durata animazione)
		get_tree().create_timer(0.5).timeout.connect(func(): is_attacking = false)

	# 3. INPUT: MANGIARE (Tasto E)
	if Input.is_action_just_pressed("eat") and is_on_floor():
		is_eating = not is_eating # Accendi/Spegni

	# 4. INPUT: MOVIMENTO (WASD)
	# Assicurati che i nomi nell'Input Map siano corretti!
	var input_dir = Input.get_vector("sinistra", "destra", "indietro", "avanti")
	
	# Calcola direzione rispetto a dove guarda la volpe (Transform Basis)
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	# 5. INPUT: ROTAZIONE (Frecce)
	# Ruotiamo solo se non stiamo mangiando (opzionale, per realismo)
	if not is_eating:
		var turn_input = Input.get_axis("turn_right", "turn_left")
		if turn_input:
			rotate_y(turn_input * ROTATION_SPEED * delta)

	# --- BLOCCHI LOGICI ---
	
	# Se ci muoviamo (WASD), smettiamo di mangiare
	if input_dir.length() > 0 and is_eating:
		is_eating = false

	# Se attacchiamo o mangiamo, FORZIAMO il movimento a zero
	if is_attacking or is_eating:
		direction = Vector3.ZERO

	# 6. GESTIONE VELOCITÀ E SPRINT (Shift)
	var is_sprinting = Input.is_action_pressed("sprint")
	var current_target_speed = GALLOP_SPEED if is_sprinting else WALK_SPEED
	
	if direction:
		# Accelerazione
		velocity.x = move_toward(velocity.x, direction.x * current_target_speed, ACCELERATION * delta)
		velocity.z = move_toward(velocity.z, direction.z * current_target_speed, ACCELERATION * delta)
		idle_timer = 0.0
	else:
		# Frenata (Friction)
		velocity.x = move_toward(velocity.x, 0, FRICTION * delta)
		velocity.z = move_toward(velocity.z, 0, FRICTION * delta)
		idle_timer += delta

	# 7. SALTO (Spazio)
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		# Non saltare se sei impegnato in azioni
		if not is_attacking and not is_eating:
			velocity.y = JUMP_VELOCITY

	# 8. FISICA
	move_and_slide()
	
	# 9. ANIMAZIONE
	# Calcoliamo velocità orizzontale reale
	var horizontal_speed = Vector2(velocity.x, velocity.z).length()
	var is_moving = horizontal_speed > 0.1
	
	_update_anim_conditions(is_moving, is_sprinting, horizontal_speed)


# --- GESTIONE ANIMATION TREE ---
func _update_anim_conditions(is_moving: bool, is_sprinting: bool, speed: float):
	var path = "parameters/conditions/"
	
	# RESET COMPLETO (Per evitare stati incastrati)
	anim_tree[path + "Idle"] = false
	anim_tree[path + "IdleLow"] = false
	anim_tree[path + "Idle2"] = false
	anim_tree[path + "Walk"] = false
	anim_tree[path + "Gallop"] = false
	anim_tree[path + "Jump"] = false
	anim_tree[path + "G_Jump"] = false
	anim_tree[path + "Attack"] = false
	anim_tree[path + "Eating"] = false
	anim_tree[path + "Death"] = false

	# --- PRIORITÀ DEGLI STATI ---
	# L'ordine è importante: chi sta sopra vince.

	# 1. Morte
	if is_dead:
		anim_tree[path + "Death"] = true
		return

	# 2. Attacco
	if is_attacking:
		anim_tree[path + "Attack"] = true
		return

	# 3. Salto (Se non tocca terra)
	if not is_on_floor():
		# Se andavamo veloci -> Salto in corsa, altrimenti Salto normale
		if speed > WALK_SPEED + 1.0: 
			anim_tree[path + "G_Jump"] = true
		else:
			anim_tree[path + "Jump"] = true
		return

	# 4. Mangiare
	if is_eating:
		anim_tree[path + "Eating"] = true
		return
		# Nota: Quando is_eating diventa false, il codice prosegue sotto e attiva "Idle"
		# facendo scattare la transizione Eating -> Idle.

	# 5. Movimento a Terra
	if is_moving:
		if is_sprinting:
			anim_tree[path + "Gallop"] = true
		else:
			anim_tree[path + "Walk"] = true
	else:
		# 6. Idle (Fermo)
		if is_low_health:
			anim_tree[path + "IdleLow"] = true
		elif idle_timer > 5.0:
			# Idle speciale dopo 5 secondi
			anim_tree[path + "Idle2"] = true
			# Reset dopo 2 secondi di animazione speciale
			if idle_timer > 7.0: idle_timer = 0.0 
		else:
			anim_tree[path + "Idle"] = true
