extends SkeletonIK3D

@export var raycast: RayCast3D
@export var bone_attachment: BoneAttachment3D
@export var foot_offset: float     = 0.05
@export var ray_height: float      = 0.8   # altezza sopra il bone da cui parte il raggio
@export var ray_extra_down: float  = 0.6   # quanto scendere SOTTO il bone (fix pendenza in giù)
@export var min_ik: float          = 0.03
@export var max_ik: float          = 0.90
@export var smooth_speed: float    = 18.0  # velocità interpolazione target Y
@export var miss_falloff_time: float = 0.25 # secondi prima di abbandonare l'ultimo hit valido

var _default_basis: Basis
var _target: Node3D

# ── Stato per fallback e smoothing ──────────────────────────────────────────
var _last_hit_point:  Vector3 = Vector3.ZERO
var _last_hit_normal: Vector3 = Vector3.UP
var _has_valid_hit:   bool    = false
var _miss_timer:      float   = 0.0
var _smooth_y:        float   = 0.0
var _initialized:     bool    = false

func _ready() -> void:
	start()

	_target = get_node(target_node) as Node3D
	if _target:
		_default_basis = _target.global_transform.basis
	else:
		push_error(name + " → TARGET NULL! Controlla il NodePath: " + str(target_node))

	# Escludi il CharacterBody3D dalle collisioni del raycast
	var body = get_parent()
	while body and not body is CharacterBody3D:
		body = body.get_parent()
	if body and raycast:
		raycast.add_exception(body)

func _physics_process(delta: float) -> void:
	if not raycast or not bone_attachment or not _target:
		push_warning(name + " → raycast/bone/target mancante")
		return
	_update_foot(delta)

func _update_foot(delta: float) -> void:
	var bone_pos = bone_attachment.global_transform.origin

	# 1. Posiziona il raycast sopra il bone e forza la direzione sempre verso il basso
	#    Il CharacterBody3D non ruota su X/Z, quindi local Y = world Y.
	#    Copriamo: ray_height sopra il bone + ray_extra_down sotto il bone.
	var total_ray_len = ray_height + ray_extra_down
	raycast.global_position   = bone_pos + Vector3.UP * ray_height
	raycast.target_position   = Vector3(0.0, -total_ray_len, 0.0)

	# 2. Default: target al bone (base prima di qualsiasi correzione)
	_target.global_transform.origin = bone_pos
	_target.global_transform.basis  = _default_basis

	if not _initialized:
		_smooth_y    = bone_pos.y
		_initialized = true

	# 3a. RAGGIUNGE IL TERRENO → aggiorna hit, smooth Y
	if raycast.is_colliding():
		var hit_point  = raycast.get_collision_point()
		var hit_normal = raycast.get_collision_normal()

		_last_hit_point  = hit_point
		_last_hit_normal = hit_normal
		_has_valid_hit   = true
		_miss_timer      = 0.0

		_smooth_y = lerp(_smooth_y, hit_point.y + foot_offset, smooth_speed * delta)
		_target.global_transform.origin.y = _smooth_y

		if hit_normal.dot(Vector3.UP) < 0.999:
			_target.global_transform.basis = _basis_from_normal(hit_normal)

		# Remap su range più ampio (0.5 invece di 0.3) per pendenze ripide
		var correction = abs(_smooth_y - bone_pos.y)
		influence = clamp(remap(correction, 0.0, 0.5, min_ik, max_ik), min_ik, max_ik)

	# 3b. MANCA IL TERRENO ma abbiamo un hit recente → mantieni posizione con falloff
	elif _has_valid_hit:
		_miss_timer += delta
		var falloff = 1.0 - clamp(_miss_timer / miss_falloff_time, 0.0, 1.0)

		# Interpola lentamente verso l'ultimo punto valido (evita schiocco)
		_smooth_y = lerp(_smooth_y, _last_hit_point.y + foot_offset, smooth_speed * 0.4 * delta)
		_target.global_transform.origin.y = _smooth_y

		if _last_hit_normal.dot(Vector3.UP) < 0.999:
			_target.global_transform.basis = _basis_from_normal(_last_hit_normal)

		var correction = abs(_smooth_y - bone_pos.y)
		influence = clamp(remap(correction, 0.0, 0.5, min_ik, max_ik), min_ik, max_ik) * falloff

		if _miss_timer >= miss_falloff_time:
			_has_valid_hit = false

	# 3c. NESSUN DATO → piede torna gradualmente all'animazione
	else:
		_smooth_y = lerp(_smooth_y, bone_pos.y, smooth_speed * delta)
		influence = min_ik

func _basis_from_normal(normal: Vector3) -> Basis:
	var skeleton = get_parent() as Skeleton3D
	if not skeleton:
		return _default_basis
	var fwd   = -skeleton.global_transform.basis.z
	var right = fwd.cross(normal).normalized()
	var front = normal.cross(right).normalized()
	return Basis(right, normal, -front).orthonormalized()
