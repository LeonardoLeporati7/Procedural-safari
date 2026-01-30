extends Node3D

@export var move_speed: float = 2.0
@export var turn_speed: float = 1.0
@export var ground_offset: float = 0

@export var dir = 0 

@export var jump_force: float = 20.0   
@export var gravity: float = 20.0     

@export var is_attacking = false

var vertical_velocity: float = 0.0    
var is_jumping: bool = false          
signal stop_jumping
@onready var fl_leg = $FrontLeftIKTarget
@onready var fr_leg = $FrontRightIKTarget
@onready var bl_leg = $BackLeftIKTarget
@onready var br_leg = $BackRightIKTarget

@onready var rc_fl = $StepTargetContainer/FrontLeftRay
@onready var rc_fr = $StepTargetContainer/FrontRightRay
@onready var rc_bl = $StepTargetContainer/BackLeftRay
@onready var rc_br = $StepTargetContainer/BackRightRay


func _process(delta):

	# Calcoliamo SEMPRE l'altezza del terreno, ci serve per atterrare
	var avg_feet_y = (rc_fl.step_target.global_position.y + rc_fr.step_target.global_position.y + rc_bl.step_target.global_position.y + rc_br.step_target.global_position.y) / 4.0
	var target_ground_y = avg_feet_y + ground_offset

	# INPUT SALTO
	if Input.is_action_just_pressed("ui_accept") and !is_jumping:
		is_jumping = true	
		vertical_velocity = jump_force
		print("jumpo")

	if is_jumping:
		vertical_velocity -= gravity * delta 
		position.y += vertical_velocity * delta 
		vertical_velocity = max(vertical_velocity, -50.0) # <--- AGGIUNGI QUESTO!
		# --- ROTAZIONE PARABOLICA (CON LIMITE) ---
		var p_bl = rc_bl.step_target.global_position
		var p_br = rc_br.step_target.global_position
		var p_fl = rc_fl.step_target.global_position
		var p_fr = rc_fr.step_target.global_position
		
		# Calcoliamo quanto inclinare, MA mettiamo un limite (clamp)
		# clamp(valore, min, max) impedisce che il valore superi 1.5 metri di sbilanciamento
		var amount = clamp(abs(vertical_velocity) * 0.15, 0.0, 1.5)

		if vertical_velocity > 0:
			# SALITA: Impennata (Abbassa i piedi dietro finti)
			p_bl.y -= amount
			p_br.y -= amount
		else:
			# DISCESA: Picchiata (Alza i piedi dietro finti)
			p_bl.y += amount
			p_br.y += amount

		# Calcolo Fake Plane
		var plane_jump1 = Plane(p_bl, p_fl, p_fr)
		var plane_jump2 = Plane(p_fr, p_br, p_bl)
		var avg_normal_jump = ((plane_jump1.normal + plane_jump2.normal) / 2).normalized()
	
		var target_basis_jump = _basis_from_normal(avg_normal_jump)
		transform.basis = transform.basis.slerp(target_basis_jump, 12.0 * delta).orthonormalized()
	
		# --- ATTERRAGGIO (FIX) ---
		# Se stiamo cadendo e siamo sotto o vicini all'altezza del terreno
		if vertical_velocity < 0 and position.y <= target_ground_y:
			is_jumping = false
			vertical_velocity = 0.0
			position.y = target_ground_y # Incolla a terra
			emit_signal("stop_jumping")
			
	else:
		var plane1 = Plane(rc_bl.step_target.global_position, rc_fl.step_target.global_position, rc_fr.step_target.global_position)
		var plane2 = Plane(rc_fr.step_target.global_position, rc_br.step_target.global_position, rc_bl.step_target.global_position)
		var avg_normal = ((plane1.normal + plane2.normal) / 2).normalized()
		
		var target_basis = _basis_from_normal(avg_normal)
		transform.basis = lerp(transform.basis, target_basis, move_speed * delta).orthonormalized()
		
		var avg = (fl_leg.position + fr_leg.position + bl_leg.position + br_leg.position) / 4
		var target_pos = avg + transform.basis.y * ground_offset
		var distance = transform.basis.y.dot(target_pos - position)
		position = lerp(position, position + transform.basis.y * distance, move_speed * delta)
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


func _on_stop_jumping() -> void:
	pass # Replace with function body.
