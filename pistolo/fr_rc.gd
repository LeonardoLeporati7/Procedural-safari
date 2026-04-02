extends RayCast3D

var _sphere: MeshInstance3D = null

func _ready() -> void:
	# Crea la sfera una volta sola
	_sphere = MeshInstance3D.new()
	var mesh = SphereMesh.new()
	mesh.radius = 0.08
	mesh.height = 0.16
	_sphere.mesh = mesh

	# Materiale colorato per vederla bene
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color.RED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # sempre visibile
	_sphere.material_override = mat

	# La aggiungiamo alla root della scena così non eredita le trasformazioni del raycast
	get_tree().root.add_child.call_deferred(_sphere)
	_sphere.visible = false

func _process(_delta: float) -> void:
	if is_colliding():
		_sphere.visible = true
		_sphere.global_position = get_collision_point()
	else:
		_sphere.visible = false

func _exit_tree() -> void:
	# Pulizia quando il nodo viene rimosso
	if _sphere:
		_sphere.queue_free()
