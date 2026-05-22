extends Node3D

@export var tree_count  : int   = 2000
@export var hp_min      : float = 0.10
@export var hp_max      : float = 0.55
@export var dist_max    : float = 0.78   # non oltre questo raggio (0=centro, 1=bordo)
@export var min_dist    : float = 2.0

@export_group("Food markers (gruppo 'food')")
## Se true, oltre al MultiMesh visivo spawna anche dei Marker3D nel gruppo
## "food" così che gli erbivori possano trovarli con la scansione globale.
@export var spawn_food_markers: bool = true
## Frazione degli alberi che diventa "cibo" per gli animali (0..1).
## 1.0 = tutti gli alberi sono cibo (2000 marker, ok ma non bellissimo);
## 0.3 = un terzo degli alberi è cibo (600 marker, più leggero).
@export_range(0.0, 1.0) var food_marker_ratio: float = 1
## Quando un erbivoro "mangia" il marker, anche l'instance visiva del MultiMesh
## viene nascosta (scala 0). Lascia ON per coerenza visiva.
@export var hide_multimesh_on_eat: bool = true

# Reference al MultiMesh per poter nascondere istanze "mangiate"
var _multimesh: MultiMesh = null
# Mappa marker → indice nel multimesh
var _marker_to_index: Dictionary = {}

func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for c in node.get_children():
		var r := _find_mesh(c)
		if r: return r
	return null


func apply_scatter(vertices: PackedVector3Array, terrain_size: float, terrain_height: float) -> void:
	
	var candidates : PackedVector3Array = []
	for v in vertices:
		var dist := Vector2(v.x, v.z).length() / (terrain_size * 0.5)
		var hp   = clamp((v.y + 1.0) / (terrain_height + 1.0), 0.0, 1.0)
		if hp >= hp_min and hp <= hp_max and dist <= dist_max:
			candidates.append(v)

	# Mesh alber
	var scene : PackedScene = preload("res://assets/tree1/Untitled.gltf")
	var temp  : Node3D      = scene.instantiate()
	
	add_child(temp)
	var mi  := _find_mesh(temp)
	var geo := mi.mesh
	#fare modifiche qui 
	remove_child(temp)
	temp.queue_free()


	var tempArr := Array(candidates)
	tempArr.shuffle()
	candidates = PackedVector3Array(tempArr)

	var placed    : PackedVector3Array = []
	var min_dist2 := min_dist * min_dist

	for v in candidates:
		if placed.size() >= tree_count:
			break
		var too_close := false
		for p in placed:
			if Vector2(v.x, v.z).distance_squared_to(Vector2(p.x, p.z)) < min_dist2:
				too_close = true
				break
		if not too_close:
			placed.append(v)

	# MultiMesh
	var mm := MultiMesh.new()
	mm.mesh             = geo
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count   = placed.size()

	for i in placed.size():
		var t := Transform3D()
		t = t.scaled(Vector3(randi_range(5.0, 8), randi_range(5.0, 8), randi_range(5.0, 8)))
		t.origin = placed[i]
		t = t.translated(Vector3(0.0, 3, 0.0))
		mm.set_instance_transform(i, t)

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
	_multimesh = mm

	# ─── FOOD MARKERS ────────────────────────────────────────────────────────
	# Spawn di Marker3D nel gruppo "food" così gli erbivori possono trovarli.
	if spawn_food_markers:
		_spawn_food_markers(placed)


## Crea Marker3D nel gruppo "food" su un campione delle posizioni degli alberi.
func _spawn_food_markers(placed: PackedVector3Array) -> void:
	var step: int = 1
	if food_marker_ratio > 0.0:
		step = max(1, int(round(1.0 / food_marker_ratio)))
	else:
		return

	var count := 0
	for i in placed.size():
		if i % step != 0:
			continue
		var m := Marker3D.new()
		m.position = placed[i]
		add_child(m)
		m.add_to_group("food")
		m.set_meta("multimesh_index", i)
		# Quando un altro script lo distrugge (es. l'erbivoro che lo mangia),
		# nascondiamo anche l'instance corrispondente nel MultiMesh.
		m.tree_exiting.connect(_on_food_marker_eaten.bind(m))
		_marker_to_index[m] = i
		count += 1

	print("[scatter] spawnati %d food marker (su %d alberi totali)"
		  % [count, placed.size()])


## Quando un marker viene rimosso (es. via queue_free()), nasconde la pianta
## visiva corrispondente nel MultiMesh.
func _on_food_marker_eaten(marker: Marker3D) -> void:
	if not hide_multimesh_on_eat or _multimesh == null:
		return
	var idx: int = marker.get_meta("multimesh_index", -1)
	if idx < 0 or idx >= _multimesh.instance_count:
		return
	# Imposta scala 0 per "nascondere" l'instance (Godot non ha API per
	# rimuoverla, ma scalata a zero non si vede).
	var t := Transform3D()
	t = t.scaled(Vector3.ZERO)
	t.origin = Vector3.ZERO
	_multimesh.set_instance_transform(idx, t)
