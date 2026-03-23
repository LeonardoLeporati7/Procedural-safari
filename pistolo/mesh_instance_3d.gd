extends MeshInstance3D

@export var size := 700.0          # dimensione isola
@export var resolution := 800     # più basso = più low poly
@export var height := 15    # altezza massima

@export var noise_scale := 0.02

var noise := FastNoiseLite.new()

var noise_macro := FastNoiseLite.new()
var noise_mask := FastNoiseLite.new()
var noise_mountain := FastNoiseLite.new()
var noise_detail := FastNoiseLite.new()


func _ready():
	noise.seed = randi()
	noise.frequency = noise_scale
	
	var seed_value = randi()

	# Macro forma
	noise_macro.seed = seed_value
	noise_macro.frequency = 0.007

	# Maschera montagne
	noise_mask.seed = seed_value + 100
	noise_mask.frequency = 0.008

	# Forma montagne
	noise_mountain.seed = seed_value + 200
	noise_mountain.frequency = 0.04

	# Dettaglio fine
	noise_detail.seed = seed_value + 300
	noise_detail.frequency = 0.005

	generate_terrain()


func get_height(x: float, z: float) -> float:
	
	# 1️⃣ Macro forma (colline generali)
	var macro = noise_macro.get_noise_2d(x, z) * 20.0
	
	# 2️⃣ Maschera montagne (0-1)
	var mask = noise_mask.get_noise_2d(x, z)
	mask = (mask + 1.0) * 0.5  # convertiamo da [-1,1] a [0,1]
	mask = pow(mask, 3.0)      # rende le montagne più rare
	
	# 3️⃣ Forma montagne (ridged)
	var mountain = noise_mountain.get_noise_2d(x, z)
	mountain = 1.0 - abs(mountain)
	mountain *= 60.0
	
	# 4️⃣ Dettaglio piccolo
	var detail = noise_detail.get_noise_2d(x, z) * 3.0
	
	# 5️⃣ Combinazione
	var height_value = macro + (mask * mountain) + detail
	
	return height_value

func generate_terrain():
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	plane.subdivide_width = resolution
	plane.subdivide_depth = resolution
	var arrays := plane.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[ArrayMesh.ARRAY_VERTEX]
	var colors : PackedColorArray = []
	var collision_shape = $"../CollisionShape3D"

	colors.resize(vertices.size())
	
	var del = 0
	
	for i in vertices.size():
		var v := vertices[i]
		
		# noise base -> var h := noise.get_noise_2d(v.x, v.z)
		var h := get_height(v.x, v.z)

		# maschera per creare l'isola (abbassa i bordi)
		var dist := Vector2(v.x, v.z).length() / (size * 0.5)
		var island_mask :float = clamp(1.0 - dist, 0.0, 1.0)
		
		
		v.y = h * island_mask #* height
		vertices[i] = v

		
		
		var height_percent = (v.y + 1.0) / (height + 1.0) 
		height_percent = clamp(height_percent, -1.0, 1.0)
		
		if(height_percent <= 0.1):
			
			colors[i]= Color(0.797, 0.608, 0.323, 1.0)
		elif (height_percent < randf_range(0.60, 0.80)):
			colors[i]= Color(randf_range(0.300, 0.325), randf_range(0.5, 0.55), randf_range(0.20, 0.25), 1.0)
		else:
			colors[i]= Color(1.0, 1.0, 1.0, 1.0)
		
		
		var beach_start := 0.65
		var beach_end := 0.9

		if dist > beach_start:
			var t := inverse_lerp(beach_start, beach_end, dist)
			t = smoothstep(0.0, 1.0, t)
			colors[i]= Color(0.797, 0.608, 0.323, 1.0) #deep sea level
			v.y -= t * 5.0
			vertices[i] = v

	arrays[ArrayMesh.ARRAY_VERTEX] = vertices
	arrays[ArrayMesh.ARRAY_COLOR] = colors

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	collision_shape.shape = mesh.create_trimesh_shape()
	
	self.mesh = mesh

	
