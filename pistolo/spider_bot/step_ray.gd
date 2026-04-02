extends RayCast3D

@export var step_target: Node3D

@onready var default_local_pos: Vector3 = position# Memorizziamo la posizione originale locale (rispetto al contenitore)
var hit_point:Vector3
func _physics_process(delta):

	# 2. AGGIORNAMENTO TARGET
	hit_point = get_collision_point()
	if is_colliding():
		step_target.global_position = hit_point
		
		#print(str(step_target)+"step target globall position"+str(step_target.global_position))

	else:
		#manca il hanging system
		print("non sto toccando")
		
