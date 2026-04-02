extends SkeletonIK3D

@export var raycast: RayCast3D
@export var bone_attachment: BoneAttachment3D
@export var foot_offset: float = 0.05
@export var ray_height: float  = 0.5
@export var min_ik: float      = 0.03
@export var max_ik: float      = 0.90

var _default_basis: Basis
var _target: Node3D

func _ready() -> void:
	start()

	_target = get_node(target_node) as Node3D
	if _target:
		_default_basis = _target.global_transform.basis
		print(name, " → target trovato: ", _target.name)
	else:
		push_error(name + " → TARGET NULL! Controlla il NodePath: " + str(target_node))

	# Escludi il CharacterBody3D dalle collisioni del raycast
	var body = get_parent()
	while body and not body is CharacterBody3D:
		body = body.get_parent()
	if body and raycast:
		raycast.add_exception(body)
		print(name, " → eccezione aggiunta per: ", body.name)

func _physics_process(_delta: float) -> void:
	if not raycast or not bone_attachment or not _target:
		push_warning(name + " → raycast/bone/target mancante")
		return
	_update_foot()

func _update_foot() -> void:
	var bone_pos = bone_attachment.global_transform.origin

	# 1. Sposta il raycast sopra il bone (segue l'animazione ogni frame)
	raycast.global_transform.origin = bone_pos + Vector3.UP * ray_height

	# 2. Resetta il target alla posizione del bone (evita drift)
	_target.global_transform.origin = bone_pos
	_target.global_transform.basis  = _default_basis

	# 3. Correggi solo se il raycast colpisce qualcosa
	if raycast.is_colliding():
		var hit_point  = raycast.get_collision_point()
		var hit_normal = raycast.get_collision_normal()

		_target.global_transform.origin.y = hit_point.y + foot_offset

		if hit_normal.dot(Vector3.UP) < 0.999:
			_target.global_transform.basis = _basis_from_normal(hit_normal)

		var correction = abs(hit_point.y - bone_pos.y)
		influence = clamp(remap(correction, 0.0, 0.3, min_ik, max_ik), min_ik, max_ik)

		# DEBUG — rimuovi dopo aver verificato
		print(name, " | correction: ", snapped(correction, 0.01),
			" | influence: ", snapped(influence, 0.01),
			" | bone_y: ", snapped(bone_pos.y, 0.01),
			" | hit_y: ", snapped(hit_point.y, 0.01))
	else:
		influence = min_ik

func _basis_from_normal(normal: Vector3) -> Basis:
	var skeleton = get_parent() as Skeleton3D
	if not skeleton:
		return _default_basis
	var fwd   = -skeleton.global_transform.basis.z
	var right = fwd.cross(normal).normalized()
	var front = normal.cross(right).normalized()
	return Basis(right, normal, -front).orthonormalized()
