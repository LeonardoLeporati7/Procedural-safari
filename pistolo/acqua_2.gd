extends MeshInstance3D

@onready var terr := $"../StaticBody3D/Terrain"
# Called when the node enters the scene tree for the first time.

func _ready():
	position.y=-1.8


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
