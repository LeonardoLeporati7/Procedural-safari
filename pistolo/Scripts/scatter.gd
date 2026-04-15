extends Node3D

@export var tree_count  : int   = 500
@export var hp_min      : float = 0.10
@export var hp_max      : float = 0.55
@export var dist_max    : float = 0.78   # non oltre questo raggio (0=centro, 1=bordo)


func apply_scatter(vertices: PackedVector3Array, terrain_size: float, terrain_height: float) -> void:
	# Raccoglie i vertici validi
	var candidates : PackedVector3Array = []
	for v in vertices:
		var dist := Vector2(v.x, v.z).length() / (terrain_size * 0.5)
		var hp  = clamp((v.y + 1.0) / (terrain_height + 1.0), 0.0, 1.0)
		if hp >= hp_min and hp <= hp_max and dist <= dist_max:
			candidates.append(v)

	# Mesh albero: cilindro verde
	var geo := CylinderMesh.new()
	geo.top_radius    = 0.5
	geo.bottom_radius = 0.5
	geo.height        = 3.0

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.648, 0.394, 0.143, 1.0)
	geo.surface_set_material(0, mat)

	# MultiMesh
	var count := mini(tree_count, candidates.size())
	var mm    := MultiMesh.new()
	mm.mesh             = geo
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count   = count

	var rng := RandomNumberGenerator.new()
	rng.randomize()

	for i in count:
		# Seleziona un vertice casuale da candidates: rng.randi() genera un numero casuale, 
		# % candidates.size() lo limita all'intervallo valido, quindi accede all'elemento
		var v := candidates[rng.randi() % candidates.size()]
		var t := Transform3D()
		t.origin = v + Vector3(0, 1.5, 0)   # centro del cilindro sopra il terreno
		mm.set_instance_transform(i, t)

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
