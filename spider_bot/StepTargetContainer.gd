extends Node3D

@export var offset: float =1


@onready var parent = get_parent_node_3d()#fa il get del nodo root 
@onready var previous_position = parent.global_position

func _process(delta):
	var velocity = parent.global_position - previous_position
	global_position = parent.global_position + velocity * offset
	
	previous_position = parent.global_position
