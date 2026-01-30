extends Marker3D

# Riferimento ESPLICITO al padre (Trascina il nodo SpiderBot qui nell'Inspector!)
@export var movement_controller: Node3D 

@onready var root = $".."

@export var step_target: Node3D 
@export var step_distance: float = 2.0
@export var animation_duration: float = 0.2
@export var air_smoothness: float = 10.0

@export var adjacent_target: Node3D 
@export var opposite_target: Node3D 
@export var piega_target:Marker3D
@export var estendi_target:Marker3D
@export var rayCast_target:RayCast3D
@export var isFront = false

var is_stepping := false

func _process(delta):
	# Sicurezza
	if not movement_controller: return

	# --- 1. GESTIONE SALTO ---
	if "is_jumping" in movement_controller and movement_controller.is_jumping:
		_handle_jump_pose(delta)
		return 

	# --- 2. GESTIONE CAMMINATA ---
	step_distance = 3.0 
	animation_duration = 0.2 
	
	if movement_controller.dir != 0: 
		# Calcolo camminata dinamica
		animation_duration = clamp(0.25 / (movement_controller.move_speed / 2.0), 0.1, 0.3)
		step_distance = 3.0 + (movement_controller.move_speed * 0.1)	
	
		if movement_controller.move_speed > 5: # CORSA
			if !is_stepping && !opposite_target.is_stepping && abs(global_position.distance_to(step_target.global_position)) > step_distance:
				step()
		else: # CAMMINATA
			if !is_stepping && !adjacent_target.is_stepping && abs(global_position.distance_to(step_target.global_position)) > step_distance:
				step()
	else:
		# IDLE
		step_distance = 0.5 
		if !is_stepping and abs(global_position.distance_to(step_target.global_position)) > step_distance:
			step()

func _handle_jump_pose(delta):
	print("jumpo ")
	var v_vel = 0.0
	if "vertical_velocity" in movement_controller: 
		v_vel = movement_controller.vertical_velocity
	if isFront:#zampe anteriori
		if(v_vel>0):
			global_position = global_position.slerp(piega_target.global_position, air_smoothness * delta)
		else :
			global_position = global_position.slerp(estendi_target.global_position, air_smoothness * delta)
	
	else :#zampe posteriori	
		if(v_vel>0):
			global_position = global_position.slerp(estendi_target.global_position, air_smoothness * delta)
		else :
			global_position = global_position.slerp(piega_target.global_position, air_smoothness * delta)
	
	is_stepping = false 

func step():
	is_stepping = true
	var target_pos = step_target.global_position
	var half_way = (global_position + target_pos) / 2
	var lift = owner.basis.y * (0.5 + movement_controller.move_speed * 0.1)
	
	var t = get_tree().create_tween()
	t.set_trans(Tween.TRANS_SINE) 
	t.tween_property(self, "global_position", half_way + lift, animation_duration * 0.5)
	t.tween_property(self, "global_position", target_pos, animation_duration * 0.5)
	t.tween_callback(func(): is_stepping = false)
