extends Node


# Called when the node enters the scene tree for the first time.
func hasComponent(targetNode, targetComponent) -> Node:
	var children = targetNode.get_children()
	for child in children:
		if is_instance_of(child, targetComponent):
			return child
	return null

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
