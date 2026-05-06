extends MeshInstance3D

@export var size            := 1200.0
@export var resolution      := 1000
@export var height          := 15
@export var noise_scale     := 0.02
@export var mountain_height : float = 90.0
@export var mountain_freq   : float = 0.01
@export var mountain_rarity : float = 4.5
@export var ridge_sharpness : float = 0.8
@export var macro_strength  : float = 18.0

var noise          := FastNoiseLite.new()
var noise_macro    := FastNoiseLite.new()
var noise_mask     := FastNoiseLite.new()
var noise_mountain := FastNoiseLite.new()
var noise_detail   := FastNoiseLite.new()


func _ready() -> void:
	noise.seed      = randi()
	noise.frequency = noise_scale

	var seed_value := randi()

	noise_macro.seed      = seed_value
	noise_macro.frequency = 0.007

	noise_mask.seed      = seed_value + 100
	noise_mask.frequency = 0.008

	noise_mountain.seed      = seed_value + 200
	noise_mountain.frequency = mountain_freq

	noise_detail.seed      = seed_value + 300
	noise_detail.frequency = 0.05

	generate_terrain()


func get_height(x: float, z: float) -> float:
	var macro    : float = noise_macro.get_noise_2d(x, z) * macro_strength
	var mask     : float = noise_mask.get_noise_2d(x, z)
	mask = pow((mask + 1.0) * 0.5, mountain_rarity)
	var mountain : float = pow(1.0 - abs(noise_mountain.get_noise_2d(x, z)), ridge_sharpness) * mountain_height
	var detail   : float = noise_detail.get_noise_2d(x, z) * 3.0
	return macro + (mask * mountain) + detail


func generate_terrain() -> void:
	var plane := PlaneMesh.new()
	plane.size             = Vector2(size, size)
	plane.subdivide_width  = resolution
	plane.subdivide_depth  = resolution

	var arrays   := plane.get_mesh_arrays()
	var vertices : PackedVector3Array = arrays[ArrayMesh.ARRAY_VERTEX]
	var colors   : PackedColorArray   = []
	colors.resize(vertices.size())

	var collision_shape = $"../CollisionShape3D"

	for i in vertices.size():
		var v    := vertices[i]
		var dist : float = Vector2(v.x, v.z).length() / (size * 0.5)

		v.y = get_height(v.x, v.z) * clamp(1.0 - dist, 0.0, 1.0)
		vertices[i] = v

		var hp : float = clamp((v.y + 1.0) / (height + 1.0), 0.0, 1.0)

		# ── COLORI ────────────────────────────────────────────────────────
		if hp < 0.10:
			colors[i] = Color(0.98, 0.91, 0.60)   # sabbia
		elif hp < 0.60:
			colors[i] = Color(0.35, randf_range(0.70, 0.76), 0.22)   # prato
		elif hp < 0.9:
			colors[i] = Color(0.52, 0.40, 0.22)   # roccia
		else:
			colors[i] = Color(1.00, 1.00, 1.00)   # neve

		# ── FASCIA COSTIERA ───────────────────────────────────────────────
		if dist > 0.65:
			var t : float = smoothstep(0.0, 1.0, inverse_lerp(0.65, 0.90, dist))
			colors[i] = Color(0.98, 0.91, 0.60)
			v.y -= t * 5.0
			vertices[i] = v

	arrays[ArrayMesh.ARRAY_VERTEX] = vertices
	arrays[ArrayMesh.ARRAY_COLOR]  = colors

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	collision_shape.shape = mesh.create_trimesh_shape()
	self.mesh = mesh

	# ── SCATTER ───────────────────────────────────────────────────────────────
	# Passa i vertici finali allo scatter per il posizionamento dei props.
	# Il nodo "Scatter" deve essere fratello di questo MeshInstance3D nella scena.
	var scatter = get_node_or_null("../Scatter")
	if scatter and scatter.has_method("apply_scatter"):
		
		scatter.apply_scatter(vertices, size, height)
	else:
		push_warning("Terrain: nodo 'Scatter' non trovato o manca il metodo apply_scatter().")
