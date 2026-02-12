extends CharacterBody3D 

class_name waterable

var is_submerged

var current_gravity = ProjectSettings.get_setting("physics/3d/default_gravity")


func ready():
	pass
	
	
func inWater():
	print(self.name, "è in acqua")
	is_submerged = true


func outWater():
	is_submerged=false
	print(self.name, " è fuori dall'acqua")


func _physics_process(delta: float) -> void:
	if is_submerged:
		#velocity.y = current_gravity * 0.03 * delta
		print("pollo")
	else:
		#velocity.y = current_gravity * delta 
		print("coglio")
