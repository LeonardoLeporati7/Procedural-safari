extends Marker3D

@export_group("Riferimenti")
# Trascina qui il nodo 'TailRoot' (un Marker3D figlio del sedere della volpe)
@export var root_target: Node3D 
# Riferimento al controller per sapere se scodinzolare
@export var movement_controller: Node3D 

@export_group("Fisica Coda")
# Quanto è lunga la coda (distanza dal sedere)
@export var tail_length: float = 1.0 
# QUANTO RITARDO ha la coda. 
# 5.0 = Molto pesante/ritardata. 20.0 = Rigida.
@export var drag_stiffness: float = 8.0 
# Quanto la coda viene "buttata fuori" quando giri (Forza Centrifuga)
@export var turn_inertia_strength: float = 1.5 

@export_group("Scodinzolo")
@export var wag_speed: float = 10.0
@export var wag_amount: float = 0.4 # Ampiezza movimento

var time_counter: float = 0.0
var prev_body_rot_y: float = 0.0

func _ready():
	# Stacchiamo il target dalla gerarchia per gestire la fisica noi
	top_level = true
	if movement_controller:
		prev_body_rot_y = movement_controller.global_rotation.y

func _process(delta):
	if not root_target: return
	
	time_counter += delta
	
	# 1. POSIZIONE BASE (Dietro al sedere)
	# Prendiamo la posizione del sedere e andiamo indietro (asse Z locale)
	# root_target.global_transform.basis.z è il vettore "Indietro" del sedere
	var target_pos = root_target.global_position + (root_target.global_transform.basis.z * tail_length)
	
	# 2. SCODINZOLIO (Onda sinusoidale)
	var oscillation = sin(time_counter * wag_speed) * wag_amount
	
	# Se siamo fermi, riduciamo lo scodinzolio (opzionale)
	if movement_controller and movement_controller.move_speed < 0.1:
		oscillation *= 0.2 # Scodinzola piano quando è ferma
		
	# Applichiamo lo scodinzolio sull'asse X locale del sedere (Destra/Sinistra)
	target_pos += root_target.global_transform.basis.x * oscillation
	
	# 3. FORZA CENTRIFUGA (Curva)
	# Calcoliamo quanto la volpe ha girato rispetto al frame prima
	var current_rot_y = 0.0
	if movement_controller:
		current_rot_y = movement_controller.global_rotation.y
		
	# Differenza di rotazione (Delta rotazione)
	# Usiamo angle_difference per gestire il salto da 360 a 0 gradi
	var rot_diff = angle_difference(prev_body_rot_y, current_rot_y)
	
	# Se giri a destra, la coda deve andare a sinistra (inerzia)
	# Moltiplichiamo per un fattore di forza
	var inertia_offset = -rot_diff * turn_inertia_strength * 10.0 # x10 per bilanciare valori piccoli
	
	# Aggiungiamo l'inerzia alla posizione target (sempre asse X locale)
	target_pos += root_target.global_transform.basis.x * inertia_offset
	
	# 4. APPLICAZIONE (LAG/DRAG)
	# Usiamo lerp per muovere il target verso la posizione ideale.
	# Il lerp crea naturalmente l'effetto "coda che segue in ritardo".
	global_position = global_position.lerp(target_pos, drag_stiffness * delta)
	
	# Aggiorna rotazione precedente
	prev_body_rot_y = current_rot_y

# Funzione di utilità per calcolare la differenza tra angoli in radianti
func angle_difference(from, to):
	var diff = fmod(to - from, TAU)
	return fmod(2.0 * diff, TAU) - diff
