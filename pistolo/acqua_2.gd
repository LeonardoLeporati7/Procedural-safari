extends MeshInstance3D

@onready var terr := $"../../terrain_scene_instance/Terrain"
# Called when the node enters the scene tree for the first time.
@onready var collShape := $"../CollisionShape3D"

# ─── FOOD/WATER MARKERS (per AI animali) ─────────────────────────────────────
@export_group("Water markers (gruppo 'water')")
## Se true, spawna automaticamente Marker3D nel gruppo "water" sulla RIVA
## (lato terra) così che gli erbivori si fermino al bordo dell'acqua per bere
## invece di entrarci dentro.
@export var spawn_water_markers: bool = true
## Passo della griglia di campionamento (m). Più fine → più precisione (ma
## costo CPU iniziale maggiore). 20-30 va bene per terreni 1200x1200.
@export var sample_spacing: float    = 20.0
## Una cella è "acqua" se il terreno in quel punto è almeno tanto sotto al
## livello dell'acqua. Evita falsi positivi su microvariazioni.
@export var depth_threshold: float   = 0.3
## Distanza minima tra due marker. Sotto questo valore vengono fusi.
@export var min_marker_spacing: float = 25.0
## Quanto spostare il marker verso il vicino d'acqua (0..1 di sample_spacing).
## 0 = al centro della cella terra; 0.5 = a metà tra terra e acqua (consigliato);
## 1.0 = quasi dentro l'acqua.
@export_range(0.0, 1.0) var marker_shore_offset: float = 0.5
## Alza i marker di questo offset rispetto alla quota del terreno (evita che
## sprofondino nel mesh per piccole imprecisioni della heightmap).
@export var marker_y_offset: float = 0.2
## Se ON, ogni marker mostra una colonna blu visibile da lontano per debug.
@export var show_debug_meshes: bool  = true
## Altezza della colonna di debug (m). Più alta → visibile da più lontano.
@export var debug_pillar_height: float = 8.0

func _ready():
	var waterSize = terr.size
	var altezza = terr.position.y
	var altezzaRel = (terr.height*(1.4))/8

	self.mesh.size = Vector2(waterSize, waterSize)
	collShape.shape.size = Vector3(waterSize, 32, waterSize)


	print("mia altezza: " , position.y , ", altozza della capo: " , terr.height)

	# Aspetta un frame: il terreno potrebbe non aver ancora terminato la
	# generazione della mesh quando arriviamo qui.
	if spawn_water_markers:
		await get_tree().process_frame
		_spawn_water_markers()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass


# ─── SPAWN MARKERS SULLA RIVA (lato terra) ───────────────────────────────────
## Campiona una griglia su tutto il terreno, individua le celle "riva":
## celle di TERRA che hanno almeno un vicino d'acqua. Spawn-a un Marker3D
## SPOSTATO verso il vicino d'acqua (così è sul bordo, non al centro della
## cella terra) e alla QUOTA DEL TERRENO (così l'animale ci arriva camminando).
func _spawn_water_markers() -> void:
	if not terr:
		push_warning("acqua_2: nessun riferimento al terrain — niente marker spawnati.")
		return

	var water_y: float = global_position.y
	var size: float    = terr.size
	var half: float    = size * 0.5

	# 1) Griglia is_land: true = sopra il livello dell'acqua
	var cols: int = int(size / sample_spacing) + 1
	var rows: int = cols
	var is_land: Array = []
	is_land.resize(rows)
	for r in rows:
		var row: Array = []
		row.resize(cols)
		for c in cols:
			var x: float = -half + c * sample_spacing
			var z: float = -half + r * sample_spacing
			var h: float = terr.get_height(x, z) * _radial_falloff(x, z, half)
			row[c] = h > water_y + depth_threshold
		is_land[r] = row

	# 2) Trova le celle "RIVA": TERRA con almeno un vicino ACQUA, e calcola
	# la direzione verso il vicino d'acqua più vicino per spostare il marker.
	var raw_points: Array[Vector3] = []
	for r in rows:
		for c in cols:
			if not is_land[r][c]:
				continue
			var water_dir := _water_neighbor_direction(is_land, r, c, rows, cols)
			if water_dir == Vector2.ZERO:
				continue  # nessun vicino acqua → entroterra

			# Posizione base della cella terra (xz)
			var x_land: float = -half + c * sample_spacing
			var z_land: float = -half + r * sample_spacing
			# Sposta verso l'acqua di una frazione di sample_spacing → riva
			var x: float = x_land + water_dir.x * sample_spacing * marker_shore_offset
			var z: float = z_land + water_dir.y * sample_spacing * marker_shore_offset
			# Quota = altezza del terreno in quel punto (non livello acqua)
			var terr_h: float = terr.get_height(x, z) * _radial_falloff(x, z, half)
			# Se siamo già finiti sott'acqua per via dello spostamento, alza
			# almeno al livello dell'acqua
			var y: float = max(terr_h, water_y) + marker_y_offset

			raw_points.append(Vector3(x, y, z))

	# 3) Decimazione
	var kept: Array[Vector3] = []
	var min_d2 := min_marker_spacing * min_marker_spacing
	for p in raw_points:
		var too_close := false
		for k in kept:
			# Usa solo XZ per la decimazione (ignora differenze di quota)
			var dx: float = p.x - k.x
			var dz: float = p.z - k.z
			if dx * dx + dz * dz < min_d2:
				too_close = true
				break
		if not too_close:
			kept.append(p)

	# 4) Spawn dei Marker3D come figli del parent dell'acqua
	var parent := get_parent()  # = acquaArea
	for p in kept:
		var m := Marker3D.new()
		# Marker3D posizionato in coordinate locali al parent
		m.position = p - parent.global_position
		parent.add_child(m)
		m.add_to_group("water")
		if show_debug_meshes:
			m.add_child(_make_debug_sphere())

	print("[acqua_2] spawnati %d punti d'acqua sulla riva (raw=%d)  debug_visivo=%s"
		  % [kept.size(), raw_points.size(), str(show_debug_meshes)])
	# Stampa un campione di posizioni così sai dove guardare nella scena
	for i in min(5, kept.size()):
		print("  [acqua_2] marker #", i, " @ ", kept[i])
	if kept.size() == 0:
		push_warning("[acqua_2] NESSUN marker spawnato! Controlla sample_spacing, depth_threshold, o se il terreno ha effettivamente zone d'acqua.")

## Restituisce la direzione (xz, normalizzata) verso il vicino d'acqua più
## "rappresentativo": è la media dei vettori che puntano ai vicini d'acqua
## attorno alla cella. Se non ci sono vicini d'acqua, ritorna Vector2.ZERO.
func _water_neighbor_direction(grid: Array, r: int, c: int, rows: int, cols: int) -> Vector2:
	var dir := Vector2.ZERO
	for dr in [-1, 0, 1]:
		for dc in [-1, 0, 1]:
			if dr == 0 and dc == 0:
				continue
			var nr: int = r + dr
			var nc: int = c + dc
			if nr < 0 or nr >= rows or nc < 0 or nc >= cols:
				continue
			# Se il vicino è ACQUA, sommiamo la direzione verso di lui
			if not grid[nr][nc]:
				dir += Vector2(float(dc), float(dr))
	if dir.length_squared() < 0.0001:
		return Vector2.ZERO
	return dir.normalized()


# ─── HELPER ──────────────────────────────────────────────────────────────────
## Replica la stessa attenuazione radiale che fa il TerrainGenerator
## (riga `v.y = get_height(...) * clamp(1.0 - dist, ...)`) così la nostra mappa
## land/water combacia con il terreno reale.
func _radial_falloff(x: float, z: float, half: float) -> float:
	var dist: float = Vector2(x, z).length() / half
	return clamp(1.0 - dist, 0.0, 1.0)

func _has_land_neighbor(grid: Array, r: int, c: int, rows: int, cols: int) -> bool:
	for dr in [-1, 0, 1]:
		for dc in [-1, 0, 1]:
			if dr == 0 and dc == 0:
				continue
			var nr: int = r + dr
			var nc: int = c + dc
			if nr < 0 or nr >= rows or nc < 0 or nc >= cols:
				continue
			if grid[nr][nc]:
				return true
	return false

## Genera un nodo "colonna + sfera in cima" visibile da lontano, attaccato al
## marker. Usato per debug visivo dei punti d'acqua.
func _make_debug_sphere() -> Node3D:
	var root := Node3D.new()

	# Colonna verticale (cilindro alto) per essere visti da lontano
	var pillar := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.15
	cyl.bottom_radius = 0.15
	cyl.height = debug_pillar_height
	pillar.mesh = cyl
	pillar.position = Vector3(0, debug_pillar_height * 0.5, 0)
	var pillar_mat := StandardMaterial3D.new()
	pillar_mat.albedo_color = Color(0.1, 0.5, 1.0, 1.0)
	pillar_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pillar.material_override = pillar_mat
	root.add_child(pillar)

	# Sfera in cima (più grande, neon blue) per facile identificazione
	var ball := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.6
	sph.height = 1.2
	ball.mesh = sph
	ball.position = Vector3(0, debug_pillar_height, 0)
	var ball_mat := StandardMaterial3D.new()
	ball_mat.albedo_color = Color(0.0, 0.8, 1.0, 1.0)
	ball_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ball_mat.emission_enabled = true
	ball_mat.emission = Color(0.0, 0.5, 1.0)
	ball_mat.emission_energy_multiplier = 2.0
	ball.material_override = ball_mat
	root.add_child(ball)

	return root
