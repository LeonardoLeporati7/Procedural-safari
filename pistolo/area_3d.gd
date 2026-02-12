extends Area3D


# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass


func _on_body_entered(body):
	if GeneralSingleton.hasComponent(body, waterableComponent):
		body.get_node("waterableComponent").inWater()
		


func _on_body_exited(body):
	if GeneralSingleton.hasComponent(body, waterableComponent):
		body.get_node("waterableComponent").outWater()
