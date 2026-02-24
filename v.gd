extends CharacterBody3D

@export_group("Movimento")
@export var speed: float = 5.0
@export var acceleration: float = 10.0
@export var rotation_speed: float = 10.0
@export var gravity: float = 9.8

@export_group("Stato Salute")
@export var is_low_health: bool = false
@export var is_dead: bool = false

# Timer per l'Idle alternativo (Idle2)
var idle_timer: float = 0.0
var time_to_next_idle2: float = 5.0

@onready var anim_tree: AnimationTree = $AnimationTree

func _ready():
	anim_tree.active = true

func _physics_process(delta):
	# Se è morto, blocca movimento e aggiorna solo animazione
	if is_dead:
		_update_animation_conditions()
		return

	# 1. Gravità
	if not is_on_floor():
		velocity.y -= gravity * delta

	# 2. Input Movimento
	var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if direction:
		# Movimento
		velocity.x = lerp(velocity.x, direction.x * speed, acceleration * delta)
		velocity.z = lerp(velocity.z, direction.z * speed, acceleration * delta)
		
		# Rotazione verso la direzione
		var target_rotation = atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_rotation, rotation_speed * delta)
		
		# Resetta il timer dell'Idle2 se ci muoviamo
		idle_timer = 0.0
	else:
		# Frenata
		velocity.x = lerp(velocity.x, 0.0, acceleration * delta)
		velocity.z = lerp(velocity.z, 0.0, acceleration * delta)
		
		# Conta il tempo mentre siamo fermi per far partire Idle2
		idle_timer += delta

	move_and_slide()
	
	# 3. Aggiorna le Condizioni dell'AnimationTree
	_update_animation_conditions()

func _update_animation_conditions():
	# Calcola se ci stiamo muovendo (ignora movimento verticale/gravità)
	var horizontal_speed = Vector2(velocity.x, velocity.z).length()
	var is_moving = horizontal_speed > 0.1
	print(horizontal_speed)
	# --- RESETTA TUTTE LE CONDIZIONI ---
	# È importante spegnerle tutte prima di accendere quella giusta
	# Nota: Il percorso è "parameters/conditions/NOME_CONDITION"
	anim_tree["parameters/conditions/Walk"] = false
	anim_tree["parameters/conditions/Idle"] = false
	anim_tree["parameters/conditions/IdleLow"] = false
	anim_tree["parameters/conditions/Idle2"] = false
	anim_tree["parameters/conditions/Death"] = false

	# --- LOGICA DI SELEZIONE ---
	
	if is_dead:
		anim_tree["parameters/conditions/Death"] = true
		
	elif is_moving:
		anim_tree["parameters/conditions/Walk"] = true
		
	else:
		# Siamo fermi (Idle) -> Quale Idle scegliamo?
		if is_low_health:
			anim_tree["parameters/conditions/IdleLow"] = true
		else:
			# Logica per Idle2 (random o a tempo)
			# Esempio: Se siamo fermi da più di 5 secondi, attiva Idle2
			if idle_timer > time_to_next_idle2:
				anim_tree["parameters/conditions/Idle2"] = true
				
				# Reset timer dopo un po' per tornare a Idle normale (opzionale)
				if idle_timer > time_to_next_idle2 + 2.0: 
					idle_timer = 0.0
			else:
				# Idle Normale
				anim_tree["parameters/conditions/Idle"] = true

# Funzione pubblica per uccidere la volpe
func die():
	is_dead = true

# Funzione pubblica per ferire la volpe
func set_damaged(damaged: bool):
	is_low_health = damaged
