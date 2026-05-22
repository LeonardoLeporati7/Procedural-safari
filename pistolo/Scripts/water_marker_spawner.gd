## water_marker_spawner.gd
## Genera a runtime dei Marker3D "punti d'abbeveraggio" lungo la costa del
## terreno procedurale, e li aggiunge al gruppo "water" così che gli erbivori
## (e in generale gli animali) li trovino con la scansione globale.
##
## Setup nella scena:
##   Aggiungi un Node3D figlio del nodo del livello, attacca questo script,
##   poi dall'Inspector assegna:
##     - terrain : il TerrainGenerator (mesh del terreno, lo script in
##                 mesh_instance_3d.gd)
##     - water   : la mesh d'acqua (per leggere `position.y` come livello).
##
## Cosa fa, riassunto:
##   1) campiona una griglia regolare di passo `sample_spacing` su tutta l'area
##      del terreno
##   2) per ogni cella scopre se è "sott'acqua" (terrain_height < water_y)
##   3) considera una cella "costa" se è sott'acqua e ha almeno un vicino
##      sopra l'acqua → lì spawn-a un Marker3D
##   4) opzionalmente assottiglia i punti (decimazione) per non avere troppi
##      marker addossati
##
## Tutti i marker spawnati finiscono nel gruppo "water" e sono fratelli del
## WaterMarkerSpawner stesso (per pulizia tieni un Node3D padre dedicato).

class_name WaterMarkerSpawner
extends Node3D

@export var terrain: TerrainGenerator
@export var water:   MeshInstance3D
## Distanza tra i campioni della griglia (metri). Più basso = più marker e più
## costosa la generazione iniziale. Per `terrain.size = 1200` un valore di
## 25-40 va bene.
@export var sample_spacing: float = 30.0
## Margine sotto il livello dell'acqua per considerare una cella "acqua"
## (evita falsi positivi su microvariazioni della heightmap).
@export var depth_threshold: float = 0.3
## Decimazione finale: distanza minima tra due marker (metri). Se due punti
## costa sono più vicini di tanto, ne tengo solo uno.
@export var min_marker_spacing: float = 25.0
## Disegna anche una piccola sfera blu visibile per il debug.
@export var show_debug_meshes: bool = false
## Stampa un riassunto in console al termine della generazione.
@export var verbose: bool = true

func _ready() -> void:
	# Aspetta un frame: il TerrainGenerator genera il terreno nel suo _ready()
	# ma noi vogliamo essere sicuri sia tutto pronto.
	await get_tree().process_frame
	_spawn_water_markers()

func _spawn_water_markers() -> void:
	if terrain == null:
		push_warning("WaterMarkerSpawner: 'terrain' non assegnato.")
		return
	if water == null:
		push_warning("WaterMarkerSpawner: 'water' non assegnato.")
		return

	var water_y: float = water.global_position.y
	var size: float    = terrain.size
	var half: float    = size * 0.5

	# Heightmap discretizzata (HxW): true = sopra il livello dell'acqua.
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
			var h: float = terrain.get_height(x, z) * _radial_falloff(x, z, half)
			row[c] = h > water_y + depth_threshold
		is_land[r] = row

	# 2) trova le celle "costa": sono ACQUA con almeno un vicino TERRA
	var raw_points: Array[Vector3] = []
	for r in rows:
		for c in cols:
			if is_land[r][c]:
				continue
			if _has_land_neighbor(is_land, r, c, rows, cols):
				var x: float = -half + c * sample_spacing
				var z: float = -half + r * sample_spacing
				raw_points.append(Vector3(x, water_y, z))

	# 3) decimazione (rimuove punti troppo vicini fra loro)
	var kept: Array[Vector3] = []
	var min_d2 := min_marker_spacing * min_marker_spacing
	for p in raw_points:
		var too_close := false
		for k in kept:
			if p.distance_squared_to(k) < min_d2:
				too_close = true
				break
		if not too_close:
			kept.append(p)

	# 4) spawn dei Marker3D
	for p in kept:
		var m := Marker3D.new()
		m.position = p
		add_child(m)
		m.add_to_group("water")
		if show_debug_meshes:
			m.add_child(_make_debug_sphere())

	if verbose:
		print("[WaterMarkerSpawner] spawnati %d punti d'acqua (raw=%d)"
			  % [kept.size(), raw_points.size()])

# ─── HELPER ──────────────────────────────────────────────────────────────────
## Replica la stessa attenuazione radiale che fa il TerrainGenerator in
## generate_terrain() (riga `v.y = get_height(...) * clamp(1.0 - dist, ...)`)
## così la nostra mappa di "land/water" combacia col terreno reale.
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

func _make_debug_sphere() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 1.2
	sph.height = 2.4
	mi.mesh = sph
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.6, 1.0, 0.8)
	mat.flags_transparent = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	return mi
