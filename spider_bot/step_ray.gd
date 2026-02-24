extends RayCast3D

@export var step_target: Node3D
@export var IK_target: Marker3D
@onready var object: CharacterBody3D = $"../.."
@onready var default_local_pos: Vector3 = position# Memorizziamo la posizione originale locale (rispetto al contenitore)

func _physics_process(delta):

	# 2. AGGIORNAMENTO TARGET
	var hit_point = get_collision_point()
	if is_colliding():
		step_target.global_position.y = hit_point.y
		#print(str(step_target)+"step target globall position"+str(step_target.global_position))

	else:
		#manca il hanging system
		print("non sto toccando")
		
