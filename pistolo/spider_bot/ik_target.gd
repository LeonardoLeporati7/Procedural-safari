extends Marker3D

# Riferimento ESPLICITO al padre (Trascina il nodo SpiderBot qui nell'Inspector!)
@export var movement_controller: Node3D 

@onready var root = $".."

@export var step_target: Node3D 
@export var step_distance: float = 2.0
@export var animation_duration: float = 0.2
@export var air_smoothness: float = 8.0
@export var prediction_amount: float = 0


@export var adjacent_target: Node3D
@export var opposite_target: Node3D
@export var piega_target:Marker3D
@export var estendi_target:Marker3D
@export var rayCast_target:RayCast3D
@export var isFront = false

# Soglia di dislivello oltre la quale forza il passo (fix pendenza in giù/su)
@export var height_step_threshold: float = 0.25

var is_stepping := false

func _process(delta):
	prediction_amount = 0
	if not movement_controller: return
	if not step_target: return

	# --- 1. GESTIONE SALTO ---
	if "is_jumping" in movement_controller and movement_controller.is_jumping:
		_handle_jump_pose(delta)
		return

	# Distanza 3D e dislivello puro tra la posizione attuale del piede e il target a terra
	var dist_3d     = global_position.distance_to(step_target.global_position)
	var height_diff = global_position.y - step_target.global_position.y  # positivo = piede in aria

	# Forza il passo se il piede è troppo in aria (pendenza in giù) o sotto terra (pendenza su)
	var height_force_step = abs(height_diff) > height_step_threshold

	# --- 2. GESTIONE CAMMINATA ---
	if movement_controller.dir != 0:
		animation_duration = clamp(0.25 / (movement_controller.move_speed / 6), 0.1, 0.3)
		step_distance = 3.0 + (movement_controller.move_speed * 0.1)

		# CORSA
		if movement_controller.move_speed > 5:
			prediction_amount += 2
			if !is_stepping && !opposite_target.is_stepping \
					&& (dist_3d > step_distance - prediction_amount or height_force_step):
				step()
		# CAMMINATA
		else:
			if !is_stepping && !adjacent_target.is_stepping \
					&& (dist_3d > step_distance - prediction_amount or height_force_step):
				step()
	else:
		# IDLE — il passo si attiva sia per distanza orizzontale che per dislivello
		step_distance = 0.5
		if !is_stepping and (dist_3d > step_distance or height_force_step):
			step()

func _handle_jump_pose(delta):
	print("jumpo ")
	var v_vel = 0.0
	if "vertical_velocity" in movement_controller: 
		v_vel = movement_controller.vertical_velocity
	if isFront:#zampe anteriori
		if(v_vel>0):
			global_position = global_position.lerp(piega_target.global_position, air_smoothness * delta)
		else :
			global_position = global_position.lerp(estendi_target.global_position, air_smoothness * delta)
	
	else :#zampe posteriori	
		if(v_vel>0):
			global_position = global_position.lerp(estendi_target.global_position, air_smoothness * delta)
		else :
			global_position = global_position.lerp(piega_target.global_position, air_smoothness*2 * delta)
	
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
