extends MeshInstance3D

@export var size := 60.0          # dimensione isola
@export var resolution := 500     # più basso = più low poly
@export var height := 7    # altezza massima

@export var noise_scale := 0.04

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

		
		
		var height_percent = (v.y + 1.0) / (height + 1.0) 
		height_percent = clamp(height_percent, -1.0, 1.0)
		
		if(height_percent <= -0.01):
			
			colors[i]= Color(0.0, 0.221, 0.317, 1.0)
		elif (height_percent < 0.25):
			colors[i]= Color(0.319, 0.54, 0.25, 1.0)
		else:
			colors[i]= Color(1.0, 1.0, 1.0, 1.0)
		
		if(island_mask<0.2):
				colors[i]= Color(0.797, 0.608, 0.323, 1.0) #deep sea level
				v.y=-3
				vertices[i] = v
		
	
	arrays[ArrayMesh.ARRAY_VERTEX] = vertices
	arrays[ArrayMesh.ARRAY_COLOR] = colors

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	self.mesh = mesh
	
