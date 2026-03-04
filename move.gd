extends CharacterBody3D

# ─── MOVIMENTO ───────────────────────────────────────────────────────────────
@export_group("Movimento")
@export var WALK_SPEED: float    = 5.0
@export var GALLOP_SPEED: float  = 12.0
@export var ACCELERATION: float  = 10.0
@export var FRICTION: float      = 10.0
@export var JUMP_VELOCITY: float = 6.0

# ─── ROTAZIONE ───────────────────────────────────────────────────────────────
@export_group("Rotazione")
@export var ROTATION_SPEED: float = 2.0
@export var visual_model: Node3D  # assegna "Fox" dall'Inspector

# ─── SALUTE ──────────────────────────────────────────────────────────────────
@export_group("Stato Salute")
@export var is_low_health: bool = false
@export var is_dead: bool       = false

# ─── STAMINA ─────────────────────────────────────────────────────────────────
@export_group("Stamina Sprint")
@export var STAMINA_MAX: float     = 5.0
@export var STAMINA_DRAIN: float   = 2.0
@export var STAMINA_RECOVER: float = 1.0

# ─── ATTACCO ─────────────────────────────────────────────────────────────────
@export_group("Attacco")
@export var ATTACK_COOLDOWN: float = 0.5

# ─── PENDENZA ────────────────────────────────────────────────────────────────
@export_group("Pendenza")
@export var MAX_SLOPE_ANGLE: float  = 45.0
@export var SLOPE_TILT_SPEED: float = 8.0

@export var fr_rc: RayCast3D
@export var fl_rc: RayCast3D
@export var br_rc: RayCast3D
@export var bl_rc: RayCast3D

# ─── STATO INTERNO ───────────────────────────────────────────────────────────
var is_attacking: bool           = false
var is_eating: bool              = false
var stamina: float               = 0.0
var _sprint_locked: bool         = false
var attack_cooldown_timer: float = 0.0
var current_slope_angle: float   = 0.0
var slope_normal: Vector3        = Vector3.UP
var _smooth_normal: Vector3      = Vector3.UP

@onready var anim_tree: AnimationTree = $AnimationTree

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	anim_tree.active = true
	stamina = STAMINA_MAX

# ─────────────────────────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if is_dead:
		_update_anim_conditions(false, false)
		return

	# 1. GRAVITÀ
	if not is_on_floor():
		velocity += get_gravity() * delta
		is_eating = false

	# 2. RILEVAMENTO PENDENZA
	_check_slope()

	# 3. TIMERS
	attack_cooldown_timer = max(0.0, attack_cooldown_timer - delta)

	# 4. ATTACCO
	if Input.is_action_just_pressed("attack") and attack_cooldown_timer <= 0.0:
		is_attacking = true
		is_eating    = false
		attack_cooldown_timer = ATTACK_COOLDOWN
		get_tree().create_timer(0.5).timeout.connect(func(): is_attacking = false)

	# 5. MANGIARE
	if Input.is_action_just_pressed("eat") and is_on_floor():
		is_eating = not is_eating

	# 6. INPUT MOVIMENTO
	var input_dir = Input.get_vector("sinistra", "destra", "indietro", "avanti")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	# 7. ROTAZIONE
	if not is_eating:
		var turn_input = Input.get_axis("turn_right", "turn_left")
		if turn_input:
			rotate_y(turn_input * ROTATION_SPEED * delta)

	# 8. INTERRUZIONI LOGICHE
	if input_dir.length() > 0 and is_eating:
		is_eating = false
	if is_attacking or is_eating:
		direction = Vector3.ZERO

	# 9. SPRINT con isteresi (evita flickering walk/gallop a stamina 0)
	var is_sprinting = (
		Input.is_action_pressed("sprint")
		and is_on_floor()
		and direction.length() > 0.001
		and stamina > 0.0
		and not _sprint_locked
		and current_slope_angle <= MAX_SLOPE_ANGLE * 0.8
	)
	var current_speed = GALLOP_SPEED if is_sprinting else WALK_SPEED
	if current_slope_angle > 30.0:
		current_speed *= 0.7

	# 10. STAMINA
	if is_sprinting:
		stamina = max(0.0, stamina - STAMINA_DRAIN * delta)
		if stamina <= 0.0:
			_sprint_locked = true
	else:
		stamina = min(STAMINA_MAX, stamina + STAMINA_RECOVER * delta)
		if _sprint_locked and stamina >= STAMINA_MAX * 0.3:
			_sprint_locked = false

	# 11. PROIEZIONE DIREZIONE SULLA PENDENZA
	if direction.length() > 0.001 and is_on_floor() and current_slope_angle > 2.0:
		var slope_axis = Vector3.UP.cross(slope_normal)
		if slope_axis.length() > 0.001:
			direction = direction.rotated(slope_axis.normalized(), Vector3.UP.angle_to(slope_normal))

	# 12. APPLICA VELOCITÀ
	if direction.length() > 0.001:
		velocity.x = move_toward(velocity.x, direction.x * current_speed, ACCELERATION * delta)
		velocity.z = move_toward(velocity.z, direction.z * current_speed, ACCELERATION * delta)
		# Componente Y derivata dalla velocità XZ e dalla normale — scala con qualsiasi speed
		if is_on_floor() and current_slope_angle > 2.0 and slope_normal.y > 0.1:
			velocity.y = -(velocity.x * slope_normal.x + velocity.z * slope_normal.z) / slope_normal.y
	else:
		velocity.x = move_toward(velocity.x, 0, FRICTION * delta)
		velocity.z = move_toward(velocity.z, 0, FRICTION * delta)

	# 13. SALTO
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		if not is_attacking and not is_eating:
			velocity.y = JUMP_VELOCITY

	# 14. FISICA
	move_and_slide()

	# 15. ANIMAZIONI + INCLINAZIONE VISIVA
	var h_speed   = Vector2(velocity.x, velocity.z).length()
	var is_moving = h_speed > 0.1
	_update_anim_conditions(is_moving, is_sprinting)

	if visual_model:
		_align_visual_to_slope(delta)


# ─── ALLINEAMENTO VISIVO ALLA PENDENZA ───────────────────────────────────────
func _align_visual_to_slope(delta: float) -> void:
	var target_normal := get_floor_normal() if is_on_floor() else Vector3.UP
	if target_normal.length_squared() < 0.01:
		target_normal = Vector3.UP

	_smooth_normal = _smooth_normal.lerp(target_normal, SLOPE_TILT_SPEED * delta).normalized()

	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.001:
		fwd = Vector3(0, 0, -1)
	fwd = fwd.normalized()

	var right := fwd.cross(_smooth_normal).normalized()
	var up    := _smooth_normal
	var front := up.cross(right).normalized()

	visual_model.global_transform.basis = Basis(right, up, -front).orthonormalized()


# ─── SLOPE CHECK ─────────────────────────────────────────────────────────────
func _check_slope() -> void:
	if not is_on_floor():
		current_slope_angle = 0.0
		slope_normal        = Vector3.UP
		return
	slope_normal        = get_floor_normal()
	current_slope_angle = rad_to_deg(acos(clamp(slope_normal.dot(Vector3.UP), -1.0, 1.0)))


# ─── ANIMATION TREE ───────────────────────────────────────────────────────────
func _update_anim_conditions(is_moving: bool, is_sprinting: bool) -> void:
	var p = "parameters/conditions/"
	anim_tree[p + "idle"]        = false
	anim_tree[p + "walk"]        = false
	anim_tree[p + "gallop"]      = false
	anim_tree[p + "gallop_jump"] = false
	anim_tree[p + "eating"]      = false

	if is_dead:
		return

	if not is_on_floor():
		if is_sprinting:
			anim_tree[p + "gallop_jump"] = true
		return

	if is_eating:
		anim_tree[p + "eating"] = true
		return

	if is_moving:
		if is_sprinting:
			anim_tree[p + "gallop"] = true
		else:
			anim_tree[p + "walk"] = true
	else:
		anim_tree[p + "idle"] = true
