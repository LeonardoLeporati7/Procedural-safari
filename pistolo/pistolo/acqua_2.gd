extends MeshInstance3D

@onready var terr := $"../../terrain_scene_instance/Terrain"
# Called when the node enters the scene tree for the first time.


func _ready():
	var waterSize = terr.size 
	var altezza = terr.position.y
	var altezzaRel = (terr.height*(1.4))/8
	self.mesh.size = Vector2(waterSize, waterSize)
	
	print("mia altezza: " , position.y , ", altozza della capo: " , terr.height)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
