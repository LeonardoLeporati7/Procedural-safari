extends MeshInstance3D

@export var size := 70.0          # dimensione isola
@export var resolution := 64     # più basso = più low poly
@export var height := 7.0         # altezza massima

@export var noise_scale := 0.1

var noise := FastNoiseLite.new()

func _ready():
	noise.seed = randi()
	noise.frequency = noise_scale
	generate_terrain()

func generate_terrain():
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	plane.subdivide_width = resolution
	plane.subdivide_depth = resolution
	var arrays := plane.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[ArrayMesh.ARRAY_VERTEX]

	for i in vertices.size():
		var v := vertices[i]

		# noise base
		var h := noise.get_noise_2d(v.x, v.z)

		# maschera per creare l'isola (abbassa i bordi)
		var dist := Vector2(v.x, v.z).length() / (size * 0.5)
		var island_mask :float = clamp(1.0 - dist, 0.0, 1.0)

		v.y = h * height * island_mask
		vertices[i] = v

	arrays[ArrayMesh.ARRAY_VERTEX] = vertices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	self.mesh = mesh
