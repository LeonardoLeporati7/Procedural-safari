extends RayCast3D

@export var step_target: Node3D
# Velocità con cui il piede torna alla posizione di default quando non tocca (hanging)
@export var hang_return_speed: float = 8.0

@onready var default_local_pos: Vector3 = position  # posizione locale originale (rispetto al contenitore)
var hit_point: Vector3
var _last_valid_hit: Vector3 = Vector3.ZERO
var _has_hit: bool = false

func _physics_process(delta: float) -> void:
	hit_point = get_collision_point()

	if is_colliding():
		# Terreno raggiunto → muovi il target al punto di collisione
		hit_point = get_collision_point()
		step_target.global_position = hit_point
		_last_valid_hit = hit_point
		_has_hit = true
	else:
		# ── HANGING SYSTEM ────────────────────────────────────────────────────
		# Calcola la posizione "naturale" del piede nel vuoto:
		# è la fine del raycast (default_local_pos del contenitore in world space)
		var container = get_parent()
		var natural_pos: Vector3
		if container:
			natural_pos = container.global_transform * default_local_pos
		else:
			natural_pos = global_position + target_position

		if _has_hit:
			# Interpola dal punto valido verso la posizione naturale (piede si abbassa dolcemente)
			step_target.global_position = step_target.global_position.lerp(
				natural_pos, hang_return_speed * delta
			)
			# Se siamo abbastanza vicini alla posizione naturale, rilascia il lock
			if step_target.global_position.distance_to(natural_pos) < 0.05:
				_has_hit = false
		else:
			# Nessun terreno e nessun hit recente → piede alla posizione naturale
			step_target.global_position = step_target.global_position.lerp(
				natural_pos, hang_return_speed * delta
			)

