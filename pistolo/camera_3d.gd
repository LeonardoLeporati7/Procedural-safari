extends Camera3D

var velocity = 0.6
var sensitivity= 0.2
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	
var sprint = 0
func _input(event):
	if event is InputEventMouseMotion && Input.mouse_mode==2:
		# 1. Ruota il corpo a destra e sinistra (Asse Y)
		# Moltiplichiamo direttamente per il valore relativo: più muovi, più ruota
		rotation_degrees.y -= event.relative.x * sensitivity
		
		# 2. Ruota la camera (o il corpo) su e giù (Asse X)
		rotation_degrees.x -= event.relative.y * sensitivity
		
		# 3. Limita la rotazione su/giù per non ribaltarti (Clamping)
		rotation_degrees.x = clamp(rotation_degrees.x, -80, 80)
		

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	
	if Input.is_action_just_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		
	elif get_window().has_focus():
		# Se l'utente clicca nella finestra, cattura il mouse
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	


	
	if Input.is_action_pressed("ui_up"):
		rotation_degrees+= Vector3(5, 0, 0)
		print(rotation_degrees)
	if Input.is_action_pressed("ui_down"):
		rotation_degrees+= Vector3(-5, 0, 0)
	if Input.is_action_pressed("ui_left"):
		rotation_degrees+= Vector3(0, 5, 0)
	if Input.is_action_pressed("ui_right"):
		rotation_degrees+= Vector3(0, -5, 0)
		
	var direction = Vector3.ZERO
	
	if Input.is_action_pressed("w"):
		direction -= transform.basis.z
	if Input.is_action_pressed("s"):
		direction += transform.basis.z
	if Input.is_action_pressed("a"):
		direction -= transform.basis.x
	if Input.is_action_pressed("d"):
		direction += transform.basis.x
		
	direction.y=0
	
	if Input.is_action_pressed("ui_accept"):
		direction.y += 1 * velocity
	if Input.is_action_pressed("shi"):
		direction.y -= 1 * velocity
	
	if Input.is_action_just_pressed("ui_focus_next"):
		print(position)
		
	if(direction):
		
		
		if Input.is_action_pressed("ctrl"):
			sprint = (velocity/100 * 100)
		else:
			sprint = 0
			
		position += direction.normalized() * (velocity + sprint)
