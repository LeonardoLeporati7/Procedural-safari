extends CharacterBody3D

# --- CONFIGURAZIONE ---
@export_group("Movimento")
@export var WALK_SPEED = 5.0
@export var GALLOP_SPEED = 12.0
@export var ACCELERATION = 10.0
@export var FRICTION = 10.0
@export var JUMP_VELOCITY = 6.0

# CORREZIONE IMPORTANTE: Ora punta al modello 3D, non al CharacterBody!
@onready var visual_model: Node3D = $"."

@export_group("Rotazione")
const ROTATION_SPEED = 2.0 

@export_group("Stato Salute")
@export var is_low_health: bool = false
@export var is_dead: bool = false

# --- STATI AZIONE ---
var is_attacking: bool = false
var is_eating: bool = false

@onready var anim_tree: AnimationTree = $AnimationTree

func _ready():
	anim_tree.active = true

func _physics_process(delta: float) -> void:
	if is_dead:
		_update_anim_conditions(false, false)
		return

	# 1. GRAVITÀ
	if not is_on_floor():
		velocity += get_gravity() * delta
		is_eating = false

	# 2. INPUT: ATTACCO
	if Input.is_action_just_pressed("attack"):
		is_attacking = true
		is_eating = false 
		get_tree().create_timer(0.5).timeout.connect(func(): is_attacking = false)

	# 3. INPUT: MANGIARE
	if Input.is_action_just_pressed("eat") and is_on_floor():
		is_eating = not is_eating 

	# 4. INPUT: MOVIMENTO
	var input_dir = Input.get_vector("sinistra", "destra", "indietro", "avanti")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	# 5. INPUT: ROTAZIONE
	if not is_eating:
		var turn_input = Input.get_axis("turn_right", "turn_left")
		if turn_input:
			rotate_y(turn_input * ROTATION_SPEED * delta)

	# --- BLOCCHI LOGICI ---
	if input_dir.length() > 0 and is_eating:
		is_eating = false

	if is_attacking or is_eating:
		direction = Vector3.ZERO

	# 6. VELOCITÀ E SPRINT
	var is_sprinting = Input.is_action_pressed("sprint")
	var current_target_speed = GALLOP_SPEED if is_sprinting else WALK_SPEED
	
	if direction:
		velocity.x = move_toward(velocity.x, direction.x * current_target_speed, ACCELERATION * delta)
		velocity.z = move_toward(velocity.z, direction.z * current_target_speed, ACCELERATION * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, FRICTION * delta)
		velocity.z = move_toward(velocity.z, 0, FRICTION * delta)

	# 7. SALTO
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		if not is_attacking and not is_eating:
			velocity.y = JUMP_VELOCITY

	# 8. FISICA
	move_and_slide()
	
	# 9. AGGIORNAMENTO
	var horizontal_speed = Vector2(velocity.x, velocity.z).length()
	var is_moving = horizontal_speed > 0.1
	
	_update_anim_conditions(is_moving, is_sprinting)
	_align_to_slope(delta)

# --- GESTIONE ANIMATION TREE (Basato sul tuo nuovo grafico) ---
func _update_anim_conditions(is_moving: bool, is_sprinting: bool):
	var path = "parameters/conditions/"
	
	# RESET SOLO DEGLI STATI PRESENTI NEL TUO GRAFICO
	anim_tree[path + "idle"] = false
	anim_tree[path + "walk"] = false
	anim_tree[path + "gallop"] = false
	anim_tree[path + "gallop_jump"] = false
	anim_tree[path + "eating"] = false


	# --- PRIORITÀ DEGLI STATI ---
	if is_dead:
		return

	# Controllo Aria (Salto)
	if not is_on_floor():
		if is_sprinting:
			anim_tree[path + "gallop_jump"] = true
		else: 
			anim_tree[path + "jump"] = true
		return

	# Controllo Cibo
	if is_eating:
		anim_tree[path + "eating"] = true
		return

	# Controllo Movimento
	if is_moving:
		if is_sprinting:
			anim_tree[path + "gallop"] = true
		else:
			anim_tree[path + "walk"] = true
	else:
		anim_tree[path + "idle"] = true


func _align_to_slope(delta: float):
	var target_normal = Vector3.UP
	if is_on_floor():
		target_normal = get_floor_normal()

	var current_basis = visual_model.global_transform.basis
	var x_axis = target_normal.cross(current_basis.z).normalized()
	var y_axis = target_normal
	var z_axis = x_axis.cross(target_normal).normalized()
	
	if x_axis.length() > 0.01:
		var target_basis = Basis(x_axis, y_axis, z_axis)
		visual_model.global_transform.basis = current_basis.slerp(target_basis, 8.0 * delta)
