extends MeshInstance3D


@export var size := 400.0          # dimensione isola
@export var resolution := 500     # più basso = più low poly
@export var height := 10    # altezza massima

@export var noise_scale := 0.02

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
	var colors : PackedColorArray = []
	var collision_shape = $"../CollisionShape3D"

	colors.resize(vertices.size())
	
	var del = 0

	
	for i in vertices.size():
		var v := vertices[i]
		
		# noise base
		var h := noise.get_noise_2d(v.x, v.z)

		# maschera per creare l'isola (abbassa i bordi)
		var dist := Vector2(v.x, v.z).length() / (size * 0.5)
		var island_mask :float = clamp(1.0 - dist, 0.0, 1.0)
		
		
		v.y = h * height * island_mask
		vertices[i] = v

		
		
		var height_percent = (v.y + 1.0) / (height + 1.0) 
		height_percent = clamp(height_percent, -1.0, 1.0)
		
		if(height_percent <= -0.01):
			
			colors[i]= Color(0.797, 0.608, 0.323, 1.0)
		elif (height_percent < 0.25):
			colors[i]= Color(randf_range(0.300, 0.325), randf_range(0.5, 0.55), randf_range(0.20, 0.25), 1.0)
		else:
			colors[i]= Color(1.0, 1.0, 1.0, 1.0)
			
		
		
		
		var beach_start := 0.75
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
	
