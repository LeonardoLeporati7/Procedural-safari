extends MeshInstance3D

@onready var terr := $"../StaticBody3D/Terrain"
# Called when the node enters the scene tree for the first time.


func _ready():
	var waterSize = terr.size 
	self.mesh.size = Vector2(waterSize, waterSize)
	
	print("ho trovato: " , waterSize)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
