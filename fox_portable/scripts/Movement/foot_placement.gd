extends Marker3D

@export var rayCast : RayCast3D

func _ready() -> void:
	position=rayCast.target_position	


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
