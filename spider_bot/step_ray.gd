extends RayCast3D

@export var step_target: Node3D
@export var IK_target: Marker3D
@onready var object: Node3D = $"../.."
@onready var default_local_pos: Vector3 = position# Memorizziamo la posizione originale locale (rispetto al contenitore)

func _physics_process(delta):
	# 1. GESTIONE OFFSET (PREVISIONE)

	# Leggiamo la direzione dallo script del padre
	var move_dir = object.dir
	
	# Calcoliamo il nuovo offset locale
	# Se move_dir è 1 (avanti), offset è -2 (perché forward è -Z in Godot)
	# Se move_dir è -1 (indietro), offset è +2
	var offset_z = 0.0
	
	if move_dir != 0:
		# Moltiplichiamo per -1 perché in Godot "avanti" è Z negativo
		offset_z = -move_dir
	
	# Reimpostiamo la posizione: Posizione Originale + Offset
	# Usiamo 'position' (locale), NON global_position, per restare attaccati al contenitore
	position.z = default_local_pos.z + offset_z

	# 2. AGGIORNAMENTO TARGET
	var hit_point = get_collision_point()
	if is_colliding():
		step_target.global_position = hit_point
		#print(str(step_target)+"step target globall position"+str(step_target.global_position))

	else:
		#manca il hanging system
		print("non sto toccando")
		var reset_pos= default_local_pos
		
		step_target.global_position = to_global(reset_pos)
