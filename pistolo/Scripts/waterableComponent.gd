extends Node3D

class_name waterableComponent

var is_submerged = false
var padre 
@export var float_force_chBody = 11
@export var float_force_rgBody = 1
@export var water_drag = 0.01
var current_gravity = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready():
	padre = get_parent()
	

func inWater():
	print(padre.name, "è in acqua")
	is_submerged = true


func outWater():
	is_submerged=false
	print(padre.name, " è fuori dall'acqua")


func _physics_process(delta: float) -> void:
	
	
	
	if is_submerged and padre is CharacterBody3D:
		padre.velocity.y +=  float_force_chBody * delta
		padre.velocity.x = lerp(padre.velocity.x, 0.0, water_drag)
		padre.velocity.z = lerp(padre.velocity.z, 0.0, water_drag)
		padre.velocity.y = lerp(padre.velocity.y, 0.0, water_drag)

	if is_submerged and padre is RigidBody3D:
		padre.apply_central_force(Vector3.UP * float_force_rgBody)
		
