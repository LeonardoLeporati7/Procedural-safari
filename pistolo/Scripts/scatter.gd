extends Node3D

@export var tree_count  : int   = 2000
@export var hp_min      : float = 0.10
@export var hp_max      : float = 0.55
@export var dist_max    : float = 0.78   # non oltre questo raggio (0=centro, 1=bordo)
@export var min_dist    : float = 2.0    # distanza minima tra alberi — più alto = meno fitti


func apply_scatter(vertices: PackedVector3Array, terrain_size: float, terrain_height: float) -> void:
	# Raccoglie i vertici validi
	var candidates : PackedVector3Array = []
	for v in vertices:
		var dist := Vector2(v.x, v.z).length() / (terrain_size * 0.5)
		var hp   = clamp((v.y + 1.0) / (terrain_height + 1.0), 0.0, 1.0)
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

	# Piazza alberi rispettando la distanza minima
	var tempArr := Array(candidates)
	tempArr.shuffle()
	candidates = PackedVector3Array(tempArr)

	var placed    : PackedVector3Array = []
	var min_dist2 := min_dist * min_dist

	for v in candidates:
		if placed.size() >= tree_count:
			break
		var too_close := false
		for p in placed:
			if Vector2(v.x, v.z).distance_squared_to(Vector2(p.x, p.z)) < min_dist2:
				too_close = true
				break
		if not too_close:
			placed.append(v)

	# MultiMesh
	var mm := MultiMesh.new()
	mm.mesh             = geo
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count   = placed.size()

	for i in placed.size():
		var t := Transform3D()
		t.origin = placed[i] + Vector3(0, 1.5, 0)
		mm.set_instance_transform(i, t)

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
