extends MeshInstance3D

@export var size := 70.0          # dimensione isola
@export var resolution := 324     # più basso = più low poly
@export var height := 6         # altezza massima

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
	var colors : PackedColorArray = []
	colors.resize(vertices.size())
	
	var cosaaa = 0
	
	for i in vertices.size():
		var v := vertices[i]
		
		# noise base
		var h := noise.get_noise_2d(v.x, v.z)

		# maschera per creare l'isola (abbassa i bordi)
		var dist := Vector2(v.x, v.z).length() / (size * 0.5)
		var island_mask :float = clamp(1.0 - dist, 0.0, 1.0)
		
		v.y = h * height * island_mask
		vertices[i] = v
		
		if cosaaa < 20:
			print("v che cazzo ne so: ", island_mask )
			cosaaa+=1
		
		if(v.y < -0.8):
			print(v)
			colors[i]= Color(0.0, 0.72, 0.989, 8.0)
		elif (v.y < 0.6):
			colors[i]= Color(0.417, 0.692, 0.331, 1.0)
		else:
			colors[i]= Color(0.737, 0.737, 0.737, 1.0)
		
		
		
	
	arrays[ArrayMesh.ARRAY_VERTEX] = vertices
	arrays[ArrayMesh.ARRAY_COLOR] = colors

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	self.mesh = mesh
	
