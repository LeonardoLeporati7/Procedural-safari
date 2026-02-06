extends Node3D

@export_group("Settings Movimento")
@export var move_speed: float = 2.0
@export var turn_speed: float = 1.0
@export var dir = 0 

@export_group("Settings Salto")
@export var jump_force: float = 12.0   
@export var gravity: float = 20.0     

@export_group("Settings Attacco")
# Variabile di stato (letta dagli altri script)
@export var is_attacking: bool = false 
# Altezza normale da terra
@export var ground_offset_normal: float = 0
# Altezza quando attacca (si schiaccia a terra)
@export var ground_offset_attack: float = 0.2 

# Variabile interna per l'altezza attuale
var current_ground_offset: float = 0

var vertical_velocity: float = 0.0    
var is_jumping: bool = false          
signal stop_jumping

@onready var rc_fl = $StepTargetContainer/FrontLeftRay
@onready var rc_fr = $StepTargetContainer/FrontRightRay
@onready var rc_bl = $StepTargetContainer/BackLeftRay
@onready var rc_br = $StepTargetContainer/BackRightRay

func _process(delta):
	var p_bl = rc_bl.step_target.global_position
	var p_br = rc_br.step_target.global_position
	var p_fl = rc_fl.step_target.global_position
	var p_fr = rc_fr.step_target.global_position
	var amount = clamp(abs(vertical_velocity) * 0.15, 0.0, 1.5)
	
	
	# --- 1. GESTIONE INPUT ATTACCO (CORRETTA) ---
	# Usiamo un solo blocco per controllare tutti i tasti di attacco.
	# Usiamo "pressed" (premuto) invece di "just_pressed" così la volpe resta bassa finché tieni il tasto.
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		is_attacking = true
	else:
		is_attacking = false

	var target_offset=ground_offset_normal
	# --- 2. GESTIONE ALTEZZA DINAMICA ---
	# Se attacco, il target è basso (0.2), altrimenti è normale (0.5)
	if is_attacking :
		target_offset = ground_offset_attack
		var attack_offset = Vector3.ZERO
		attack_offset.y+=target_offset 
		print(attack_offset)
		var plane_attack1= Plane(p_bl-attack_offset*4, p_fl+attack_offset, p_fr+attack_offset)
		var plane_attack2 = Plane(p_fr+attack_offset, p_br-attack_offset*4, p_bl-attack_offset*4)
		var avg_normal_attack = ((plane_attack1.normal + plane_attack2.normal) / 2).normalized()
		var target_basis_attack = _basis_from_normal(avg_normal_attack)
		transform.basis = transform.basis.slerp(target_basis_attack, 12.0 * delta).orthonormalized()
	
	else :
		target_offset = ground_offset_normal
	
	# Lerp fluido: 5.0 * delta determina quanto velocemente si abbassa/alza
	current_ground_offset = lerp(current_ground_offset, target_offset, 5.0 * delta)

	# --- 3. CALCOLO TERRENO ---
	var avg_feet_y = (rc_fl.step_target.global_position.y + rc_fr.step_target.global_position.y + rc_bl.step_target.global_position.y + rc_br.step_target.global_position.y) / 4.0
	
	# Qui sommiamo l'offset dinamico calcolato sopra
	var target_ground_y = avg_feet_y + current_ground_offset
	print("target ground y :"+str(target_ground_y)+"avg feet y:"+str(avg_feet_y))
	# --- 4. GESTIONE SALTO ---
	if Input.is_action_just_pressed("ui_accept") and !is_jumping:
		is_jumping = true	
		vertical_velocity = jump_force
		print("jumpo")
	
	# Nota: Ho rimosso il secondo check su "Attack" qui perché è già gestito sopra nel punto 1.

	if is_jumping:
		# FASE VOLO
		vertical_velocity -= gravity * delta 
		position.y += vertical_velocity * delta 
		vertical_velocity = max(vertical_velocity, -50.0)
		
		# Rotazione Parabolica

		if vertical_velocity > 0:
			p_bl.y -= amount
			p_br.y -= amount
		else:
			p_bl.y += amount
			p_br.y += amount

		var plane_jump1 = Plane(p_bl, p_fl, p_fr)
		var plane_jump2 = Plane(p_fr, p_br, p_bl)
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
		# Allineamento al terreno
		var plane1 = Plane(rc_bl.step_target.global_position, rc_fl.step_target.global_position, rc_fr.step_target.global_position)
		var plane2 = Plane(rc_fr.step_target.global_position, rc_br.step_target.global_position, rc_bl.step_target.global_position)
		var avg_normal = ((plane1.normal + plane2.normal) / 2).normalized()
		
		# Fix: Protezione se la normale è zero
		if !avg_normal.is_normalized(): avg_normal = Vector3.UP
		
		var target_basis = _basis_from_normal(avg_normal)
		transform.basis = transform.basis.slerp(target_basis, 10.0 * delta).orthonormalized()
		
		# Posizionamento Y fluido (Questo applica l'abbassamento del busto)
		position.y = lerp(position.y, target_ground_y, 20.0 * delta)
		#non va fatta la prediction perche puoi con le colline si abbassa il busto 
	
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
