extends Node3D

@export_group("Settings Movimento")
@export var move_speed: float = 2.0
@export var turn_speed: float = 1.0
@export var dir = 0 

@export_group("Settings Salto")
@export var jump_force: float = 12.0   
@export var gravity: float = 20.0     

@export_group("Settings Attacco")
@export var is_attacking: bool = false 
@export var ground_offset_normal: float = 0
@export var ground_offset_attack: float = 0.2 

var current_ground_offset: float = 0

var vertical_velocity: float = 0.0    
var is_jumping: bool = false          
signal stop_jumping

@onready var rc_fl = $StepTargetContainer/FrontLeftRay
@onready var rc_fr = $StepTargetContainer/FrontRightRay
@onready var rc_bl = $StepTargetContainer/BackLeftRay
@onready var rc_br = $StepTargetContainer/BackRightRay

# --- NUOVE VARIABILI PER "CONGELARE" IL PIANO ---
var jump_p_fl: Vector3
var jump_p_fr: Vector3
var jump_p_bl: Vector3
var jump_p_br: Vector3

func _process(delta):
	# 1. RECUPERO POSIZIONI PIEDI (LOGICA SNAPSHOT)
	var p_fl: Vector3
	var p_fr: Vector3
	var p_bl: Vector3
	var p_br: Vector3

	if !is_jumping:
		# SE SIAMO A TERRA: Leggiamo i Raycast in tempo reale
		p_fl = rc_fl.step_target.global_position
		p_fr = rc_fr.step_target.global_position
		p_bl = rc_bl.step_target.global_position
		p_br = rc_br.step_target.global_position
		
		# E salviamo continuamente queste posizioni come "ultimo punto valido"
		jump_p_fl = p_fl
		jump_p_fr = p_fr
		jump_p_bl = p_bl
		jump_p_br = p_br
	else:
		# SE STIAMO SALTANDO: Ignoriamo i Raycast!
		# Usiamo le posizioni salvate all'istante del salto.
		# Così il piano rotazionale rimane fisso come al decollo.
		p_fl = jump_p_fl
		p_fr = jump_p_fr
		p_bl = jump_p_bl
		p_br = jump_p_br

	# 2. GESTIONE PARABOLA (Calcolata sui punti congelati se in aria)
	var amount = clamp(abs(vertical_velocity) * 0.15, 0.0, 1.5)
	
	# --- GESTIONE INPUT ATTACCO ---
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		is_attacking = true
	else:
		is_attacking = false

	var target_offset = ground_offset_normal
	
	# --- GESTIONE ROTAZIONE ATTACCO ---
	if is_attacking:
		target_offset = ground_offset_attack
		var attack_offset = Vector3.ZERO
		attack_offset.y += target_offset 
		
		# Qui usiamo i punti p_bl, p_fl ecc. (che sono live se a terra)
		var plane_attack1 = Plane(p_bl - attack_offset * 4, p_fl + attack_offset, p_fr + attack_offset)
		var plane_attack2 = Plane(p_fr + attack_offset, p_br - attack_offset * 4, p_bl - attack_offset * 4)
		var avg_normal_attack = ((plane_attack1.normal + plane_attack2.normal) / 2).normalized()
		var target_basis_attack = _basis_from_normal(avg_normal_attack)
		transform.basis = transform.basis.slerp(target_basis_attack, 12.0 * delta).orthonormalized()
	else:
		target_offset = ground_offset_normal
	
	current_ground_offset = lerp(current_ground_offset, target_offset, 5.0 * delta)

	# --- CALCOLO ATTERRAGGIO (Raycast sempre attivi per questo!) ---
	# Nota: Continuiamo a leggere i raycast QUI solo per sapere l'altezza del terreno sotto di noi
	var avg_feet_y = (rc_fl.step_target.global_position.y + rc_fr.step_target.global_position.y + rc_bl.step_target.global_position.y + rc_br.step_target.global_position.y) / 4.0
	var target_ground_y = avg_feet_y + current_ground_offset

	# --- GESTIONE SALTO ---
	if Input.is_action_just_pressed("ui_accept") and !is_jumping:
		is_jumping = true	
		vertical_velocity = jump_force
		print("jumpo")
	
	if is_jumping:
		# FASE VOLO
		vertical_velocity -= gravity * delta 
		position.y += vertical_velocity * delta 
		vertical_velocity = max(vertical_velocity, -50.0)
		
		# Rotazione Parabolica
		# Modifichiamo copie locali dei punti congelati
		var jump_mod_bl = p_bl
		var jump_mod_br = p_br

		if vertical_velocity > 0:
			jump_mod_bl.y -= amount
			jump_mod_br.y -= amount
		else:
			jump_mod_bl.y += amount
			jump_mod_br.y += amount

		# Calcolo Plane basato sullo "Snapshot" del decollo + Parabola
		var plane_jump1 = Plane(jump_mod_bl, p_fl, p_fr)
		var plane_jump2 = Plane(p_fr, jump_mod_br, jump_mod_bl)
		var avg_normal_jump = ((plane_jump1.normal + plane_jump2.normal) / 2).normalized()
		var target_basis_jump = _basis_from_normal(avg_normal_jump)
		transform.basis = transform.basis.slerp(target_basis_jump, 12.0 * delta).orthonormalized()
	
		# ATTERRAGGIO
		if vertical_velocity < 0 and position.y <= target_ground_y:
			is_jumping = false
			vertical_velocity = 0.0
			position.y = target_ground_y 
			emit_signal("stop_jumping")
			
	else:
		# --- FASE A TERRA ---
		var plane1 = Plane(p_bl, p_fl, p_fr)
		var plane2 = Plane(p_fr, p_br, p_bl)
		var avg_normal = ((plane1.normal + plane2.normal) / 2).normalized()
		
		if !avg_normal.is_normalized(): avg_normal = Vector3.UP
		
		var target_basis = _basis_from_normal(avg_normal)
		transform.basis = transform.basis.slerp(target_basis, 10.0 * delta).orthonormalized()
		
		position.y = lerp(position.y, target_ground_y, 20.0 * delta)
	
	_handle_movement(delta)

func _handle_movement(delta):
	dir = Input.get_axis('ui_down', 'ui_up')
	translate(Vector3(0, 0, -dir) * move_speed * delta)
	
	var a_dir = Input.get_axis('ui_right', 'ui_left')
	rotate_object_local(Vector3.UP, a_dir * turn_speed * delta)

func _basis_from_normal(normal: Vector3) -> Basis:
	var result = Basis()
	result.x = normal.cross(transform.basis.z)
	result.y = normal
	result.z = transform.basis.x.cross(normal)
	result = result.orthonormalized()
	result.x *= scale.x 
	result.y *= scale.y 
	result.z *= scale.z 
	return result
