## ecosystem_manager.gd
## Spawna gli animali sul terreno procedurale usando get_height() del terrain.
## Attacca questo script a un Node nella scena principale.

extends Node

# ─── RIFERIMENTI ─────────────────────────────────────────────────────────────
@export var terrain: TerrainGenerator
# ─── SCENE ANIMALI ───────────────────────────────────────────────────────────
@export_group("Spawn")
@export var deer_scene:  PackedScene
@export var fox_scene:   PackedScene

@export var deer_count:  int = 8
@export var fox_count:   int = 3

# ─── PARAMETRI TERRENO (devono corrispondere a quelli del terrain script) ────
@export_group("Terreno")
@export var terrain_size:   float = 700.0
@export var spawn_y_min:    float = 1.0    # sotto = acqua/spiaggia, non spawnare
@export var spawn_dist_max: float = 0.58   # dist normalizzata massima dall'origine (< 0.65 = entroterra)

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	# Aspetta un frame: il terrain genera la mesh in _ready(),
	# vogliamo essere sicuri che sia finita prima di spawnare.
	await get_tree().process_frame
	await get_tree().process_frame
	_spawn_all()

# ─────────────────────────────────────────────────────────────────────────────
func _spawn_all() -> void:
	if not terrain:
		push_error("EcosystemManager: nessun terrain assegnato!")
		return

	_spawn_group(deer_scene,  deer_count,  "Deer")
	_spawn_group(fox_scene,   fox_count,   "Fox")

func _spawn_group(scene: PackedScene, count: int, label: String) -> void:
	if not scene:
		push_warning("EcosystemManager: scena '%s' non assegnata." % label)
		return

	var spawned := 0
	var attempts := 0
	var max_attempts := count * 30   # evita loop infiniti

	while spawned < count and attempts < max_attempts:
		attempts += 1
		var pos := _random_land_position()
		if pos == Vector3.ZERO:
			continue  # posizione non valida, riprova

		var animal := scene.instantiate()
		get_tree().current_scene.add_child(animal)
		animal.global_position = pos
		spawned += 1

	print("EcosystemManager: spawnati %d/%d %s" % [spawned, count, label])

# ─── TROVA UNA POSIZIONE VALIDA SUL TERRENO ──────────────────────────────────
## Ritorna una posizione XYZ sulla terra, oppure Vector3.ZERO se non valida.
func _random_land_position() -> Vector3:
	var half := terrain_size * 0.5

	# Posizione XZ casuale dentro il cerchio dell'isola
	var angle := randf_range(0.0, TAU)
	var radius := randf_range(0.0, half * spawn_dist_max)
	var x := cos(angle) * radius
	var z := sin(angle) * radius

	# Calcola la Y reale usando la stessa funzione del terrain
	var dist_norm := Vector2(x, z).length() / half
	var island_mask :float = clamp(1.0 - dist_norm, 0.0, 1.0)
	var h: float = terrain.get_height(x, z)
	var y: float = h * island_mask

	# Scarta spiagge e zone d'acqua
	if y < spawn_y_min:
		return Vector3.ZERO

	return Vector3(x, y + 0.5, z)   # +0.5 per non entrare nel terreno

# ─── GESTIONE RIPRODUZIONE ───────────────────────────────────────────────────
## Chiama questo metodo per ascoltare il segnale "reproduced" degli animali.
## Collegalo nel codice oppure manualmente dall'Inspector.
func _on_animal_reproduced(data: Dictionary) -> void:
	var scene_path: String = data.get("species", "")
	var count: int         = data.get("count", 1)
	var origin: Vector3    = data.get("position", Vector3.ZERO)

	if scene_path.is_empty():
		return

	var scene := load(scene_path) as PackedScene
	if not scene:
		return

	for i in count:
		# Spawna i figli vicino al genitore con piccolo offset casuale
		var offset := Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-2.0, 2.0))
		var spawn_pos := origin + offset
		# Ricalcola la Y corretta nel punto di spawn
		var half := terrain_size * 0.5
		var dist_norm := Vector2(spawn_pos.x, spawn_pos.z).length() / half
		var island_mask :float = clamp(1.0 - dist_norm, 0.0, 1.0)
		var spawn_h: float = terrain.get_height(spawn_pos.x, spawn_pos.z)
		spawn_pos.y = spawn_h * island_mask + 0.5

		var offspring := scene.instantiate()
		get_tree().current_scene.add_child(offspring)
		offspring.global_position = spawn_pos

		# Collega il segnale di riproduzione del figlio
		var ctrl := offspring.get_node_or_null("BehaviorController")
		if ctrl and ctrl.has_signal("reproduced"):
			ctrl.reproduced.connect(_on_animal_reproduced)
