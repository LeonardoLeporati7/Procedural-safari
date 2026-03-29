extends MeshInstance3D

@export var size             := 700.0
@export var resolution       := 1000
@export var height           := 15
@export var noise_scale      := 0.02
@export var mountain_height  : float = 90.0
@export var mountain_freq    : float = 0.003
@export var mountain_rarity  : float = 3.0
@export var ridge_sharpness  : float = 1.0
@export var macro_strength   : float = 20.0

var noise          := FastNoiseLite.new()
var noise_macro    := FastNoiseLite.new()
var noise_mask     := FastNoiseLite.new()
var noise_mountain := FastNoiseLite.new()
var noise_detail   := FastNoiseLite.new()
var noise_texture  := FastNoiseLite.new()

const COLOR_STOPS := [
	[0.00, Color(0.96, 0.85, 0.52)],
	[0.09, Color(0.98, 0.91, 0.60)],
	[0.22, Color(0.42, 0.76, 0.28)],
	[0.45, Color(0.22, 0.62, 0.18)],
	[0.65, Color(0.55, 0.42, 0.22)],
	[0.82, Color(0.68, 0.62, 0.54)],
	[0.92, Color(0.94, 0.97, 1.00)],
	[1.00, Color(1.00, 1.00, 1.00)],
]


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

	noise_texture.seed      = seed_value + 400
	noise_texture.frequency = 0.06

	generate_terrain()


func get_height(x: float, z: float) -> float:
	var macro : float = noise_macro.get_noise_2d(x, z) * macro_strength

	var mask : float = noise_mask.get_noise_2d(x, z)
	mask = (mask + 1.0) * 0.5
	mask = pow(mask, mountain_rarity)

	var mountain : float = noise_mountain.get_noise_2d(x, z)
	mountain = pow(1.0 - abs(mountain), ridge_sharpness)
	mountain *= mountain_height

	var detail : float = noise_detail.get_noise_2d(x, z) * 3.0

	return macro + (mask * mountain) + detail


func generate_terrain() -> void:
	var plane := PlaneMesh.new()
	plane.size            = Vector2(size, size)
	plane.subdivide_width  = resolution
	plane.subdivide_depth  = resolution

	var arrays   := plane.get_mesh_arrays()
	var vertices : PackedVector3Array = arrays[ArrayMesh.ARRAY_VERTEX]
	var colors   : PackedColorArray   = []
	colors.resize(vertices.size())

	var collision_shape = $"../CollisionShape3D"

	for i in vertices.size():
		var v    := vertices[i]
		var h    := get_height(v.x, v.z)
		var dist : float = Vector2(v.x, v.z).length() / (size * 0.5)

		var island_mask : float = clamp(1.0 - dist, 0.0, 1.0)
		v.y = h * island_mask
		vertices[i] = v

		var height_percent : float = clamp((v.y + 1.0) / (height + 1.0), 0.0, 1.0)

		# ── 1. COLORE SFUMATO ─────────────────────────────────────────────
		var base_color := Color(COLOR_STOPS[COLOR_STOPS.size() - 1][1])
		for s in range(COLOR_STOPS.size() - 1):
			var t0 : float = COLOR_STOPS[s][0]
			var t1 : float = COLOR_STOPS[s + 1][0]
			var c0 : Color = COLOR_STOPS[s][1]
			var c1 : Color = COLOR_STOPS[s + 1][1]
			if height_percent <= t1:
				var t : float = (height_percent - t0) / (t1 - t0)
				t = t * t * (3.0 - 2.0 * t)
				base_color = c0.lerp(c1, t)
				break

		# ── 2. TEXTURE ────────────────────────────────────────────────────
		var tex : float = noise_texture.get_noise_2d(v.x, v.z) * 0.04
		colors[i] = Color(
			clamp(base_color.r + tex,       0.0, 1.0),
			clamp(base_color.g + tex * 0.6, 0.0, 1.0),
			clamp(base_color.b + tex * 0.4, 0.0, 1.0),
			1.0
		)

		# ── 3. FASCIA COSTIERA ────────────────────────────────────────────
		var beach_start : float = 0.65
		var beach_end   : float = 0.90
		if dist > beach_start:
			var t : float = smoothstep(0.0, 1.0, inverse_lerp(beach_start, beach_end, dist))
			colors[i] = Color(0.98, 0.91, 0.60, 1.0)
			v.y -= t * 5.0
			vertices[i] = v

	arrays[ArrayMesh.ARRAY_VERTEX] = vertices
	arrays[ArrayMesh.ARRAY_COLOR]  = colors

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	collision_shape.shape = mesh.create_trimesh_shape()
	self.mesh = mesh
