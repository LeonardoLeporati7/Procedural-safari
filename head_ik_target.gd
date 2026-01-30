extends Marker3D

@export var movement_controller: Node3D

@export_group("Posizione Testa")
@export var head_height_normal: float = 1.2 # Testa alta
@export var head_height_attack: float = 0.4 # Testa bassa (vicino a terra)

@export_group("Scuotimento (Thrash)")
@export var shake_speed: float = 30.0   # Velocità (Molto alta)
@export var shake_width: float = 0.4    # Quanto si sposta a destra/sinistra (Metri)

var time_counter: float = 0.0

func _process(delta):
	if not movement_controller: return
	
	time_counter += delta
	
	# Calcoliamo la posizione target LOCALE
	var target_pos = position
	
	if movement_controller.is_attacking:
		# --- FASE ATTACCO (Scuotimento) ---
		
		# 1. Abbassa la testa (senza lerp o con lerp veloce per l'entrata)
		target_pos.y = lerp(target_pos.y, head_height_attack, 10.0 * delta)
		
		# 2. SCUOTIMENTO LATERALE (Senza Lerp!)
		# Usiamo il Seno per calcolare destra/sinistra
		var shake_offset = sin(time_counter * shake_speed) * shake_width
		
		# Applichiamo direttamente alla X (Destra/Sinistra locale)
		target_pos.x = shake_offset
		
	else:
		# --- FASE NORMALE ---
		# Riporta la testa al centro e in alto (dolcemente)
		target_pos.y = lerp(target_pos.y, head_height_normal, 5.0 * delta)
		target_pos.x = lerp(target_pos.x, 0.0, 5.0 * delta)
	
	# Applica la posizione finale
	position = target_pos
