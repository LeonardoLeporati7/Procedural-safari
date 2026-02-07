extends PhysicsBody3D 

class_name waterable

signal enter_water(event)
signal exit_water(event)

func ready():
	enter_water.connect(inWater)
	exit_water.connect(outWater)
	
	
	
func inWater():
	print(self.name, " è in acqua")
	pass
	
func outWater():
	pass
