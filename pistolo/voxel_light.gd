extends VoxelGI


@onready var terr = $"../terrain_scene_instance/Terrain"

# Called when the node enters the scene tree for the first time.
func _ready():
	terr.ready.connect(on_terr_ready)
# Called every frame. 'delta' is the elapsed time since the previous frame.

func on_terr_ready():
	size.x=terr.size.x
	size.z=terr.size.z
	
func _process(delta):
	pass
