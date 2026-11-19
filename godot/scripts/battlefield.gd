extends Node3D

# Prototype foundation for an RTS battlefield inspired by classic base-building strategy games.
const FIELD_SIZE := 120.0
const CAMERA_MIN := 22.0
const CAMERA_MAX := 72.0
var camera: Camera3D
var selected: Node3D
var drag_start := Vector2.ZERO
var dragging := false
var moved_gesture := false
var zoom := 42.0
var camera_yaw := 0.0
var units: Array[Node3D] = []
var hud: CanvasLayer
var status_label: Label
var resources := 5000
var selection_ring: MeshInstance3D
# Imported CC0 GLB assets; the tank is a real mesh, not the old box-only placeholder.
var tank_model_scene: PackedScene
var guard_tower_scene: PackedScene
var building_models: Array[PackedScene] = []
var tree_models: Array[PackedScene] = []

func _ready() -> void:
	tank_model_scene = load("res://assets/quaternius-tank.glb") as PackedScene
	guard_tower_scene = load("res://assets/quaternius-guard-tower.glb") as PackedScene
	for path in ["res://assets/b_small.glb", "res://assets/b_medium.glb", "res://assets/b_large.glb"]:
		var building_scene := load(path) as PackedScene
		if building_scene != null:
			building_models.append(building_scene)
	for path in ["res://assets/tree1.glb", "res://assets/tree2.glb", "res://assets/tree3.glb"]:
		var tree_scene := load(path) as PackedScene
		if tree_scene != null:
			tree_models.append(tree_scene)
	_build_world()
	_build_camera()
	_build_armies()
	_build_hud()

var income_clock := 0.0

func _process(delta: float) -> void:
	income_clock += delta
	if income_clock >= 1.0:
		income_clock = 0.0
		resources += 25
	for unit in units.duplicate():
		if not is_instance_valid(unit):
			units.erase(unit)
			continue
		if unit.has_meta("moving") and unit.get_meta("moving"):
			var move_target: Vector3 = unit.get_meta("move_target")
			var flat_target := Vector3(move_target.x, unit.position.y, move_target.z)
			unit.position = unit.position.move_toward(flat_target, delta * 7.0)
			if Vector2(unit.position.x, unit.position.z).distance_to(Vector2(move_target.x, move_target.z)) < 0.35:
				unit.set_meta("moving", false)
		_combat_unit(unit, delta)
	if is_instance_valid(selection_ring) and is_instance_valid(selected):
		selection_ring.global_position = selected.global_position + Vector3(0, 0.08, 0)
	if is_instance_valid(status_label):
		status_label.text = "الموارد: %d  |  القوات: %d  |  دخل الموارد: +25/ث" % [resources, _player_unit_count()]

func _mat(color: Color, metallic := 0.0, roughness := 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m

func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	node.material_override = _mat(color, 0.16)
	parent.add_child(node)
	return node

func _cylinder(parent: Node3D, radius: float, height: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	node.material_override = _mat(color, 0.2, 0.65)
	parent.add_child(node)
	return node

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	e.sky = Sky.new()
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.68, 0.70, 0.66)
	e.ambient_light_energy = 0.9
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	add_child(sun)
	_build_realistic_landscape()

func _terrain_height(x: float, z: float, noise: FastNoiseLite) -> float:
	var edge := clampf((maxf(absf(x), absf(z)) - 27.0) / 30.0, 0.0, 1.0)
	return noise.get_noise_2d(x, z) * 2.2 * edge + sin(x * 0.045) * 0.22 * edge

func _build_realistic_landscape() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 7419
	noise.frequency = 0.035
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 84
	var half := FIELD_SIZE * 0.5
	for z in range(steps):
		for x in range(steps):
			var x0 := -half + float(x) * FIELD_SIZE / steps
			var x1 := -half + float(x + 1) * FIELD_SIZE / steps
			var z0 := -half + float(z) * FIELD_SIZE / steps
			var z1 := -half + float(z + 1) * FIELD_SIZE / steps
			var p00 := Vector3(x0, _terrain_height(x0, z0, noise), z0)
			var p10 := Vector3(x1, _terrain_height(x1, z0, noise), z0)
			var p01 := Vector3(x0, _terrain_height(x0, z1, noise), z1)
			var p11 := Vector3(x1, _terrain_height(x1, z1, noise), z1)
			for p in [p00, p01, p10, p10, p01, p11]:
				var h := p.y
				var shade := noise.get_noise_2d(p.x * 2.0, p.z * 2.0) * 0.035
				var ground_color := Color(0.29, 0.32, 0.22)
				if h > 0.8:
					ground_color = Color(0.34, 0.33, 0.27)
				elif h < -0.45:
					ground_color = Color(0.25, 0.29, 0.20)
				st.set_color(ground_color + Color(shade, shade, shade))
				st.set_normal(Vector3.UP)
				st.add_vertex(p)
	st.generate_normals()
	var terrain_mesh := st.commit()
	var terrain := MeshInstance3D.new()
	terrain.name = "NaturalTerrain"
	terrain.mesh = terrain_mesh
	var terrain_mat := _mat(Color.WHITE, 0.0, 1.0)
	terrain_mat.vertex_color_use_as_albedo = true
	terrain.material_override = terrain_mat
	add_child(terrain)
	var terrain_body := StaticBody3D.new()
	terrain_body.name = "TerrainCollision"
	var terrain_collision := CollisionShape3D.new()
	terrain_collision.shape = terrain_mesh.create_trimesh_shape()
	terrain_body.add_child(terrain_collision)
	add_child(terrain_body)

	# Gravel roads with shoulders and visible center wear.
	_add_road(Vector3(0.0, 0.12, 8.0), Vector3(120.0, 0.12, 7.2), Color(0.20, 0.20, 0.17))
	_add_road(Vector3(-18.0, 0.14, 0.0), Vector3(6.8, 0.14, 120.0), Color(0.22, 0.21, 0.18))
	_add_road(Vector3(-14.0, 0.18, -13.0), Vector3(22.0, 0.16, 4.0), Color(0.25, 0.24, 0.20))

	_add_crop_field(Vector3(-42.0, 0.16, 4.0), Vector2(17.0, 24.0), Color(0.43, 0.37, 0.19))
	_add_crop_field(Vector3(39.0, 0.16, -13.0), Vector2(18.0, 26.0), Color(0.36, 0.38, 0.20))
	_add_crop_field(Vector3(5.0, 0.16, 43.0), Vector2(24.0, 12.0), Color(0.40, 0.36, 0.18))

	# Water surface, muddy bank and shoreline stones.
	var bank := MeshInstance3D.new()
	var bank_mesh := CylinderMesh.new()
	bank_mesh.top_radius = 6.8
	bank_mesh.bottom_radius = 7.2
	bank_mesh.height = 0.24
	bank.mesh = bank_mesh
	bank.position = Vector3(43.0, 0.10, 18.0)
	bank.material_override = _mat(Color(0.30, 0.29, 0.21), 0.0, 1.0)
	add_child(bank)
	var pond := MeshInstance3D.new()
	var water := PlaneMesh.new()
	water.size = Vector2(11.5, 6.0)
	pond.mesh = water
	pond.position = Vector3(43.0, 0.25, 18.0)
	var water_mat := _mat(Color(0.08, 0.24, 0.29), 0.35, 0.18)
	water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_mat.albedo_color.a = 0.92
	pond.material_override = water_mat
	add_child(pond)

	# Irregular ridgelines made from faceted rock cones rather than stretched spheres.
	for i in range(18):
		var side := -1.0 if i % 2 == 0 else 1.0
		var x := side * randf_range(43.0, 57.0)
		var z := randf_range(-52.0, 52.0)
		_add_rock(Vector3(x, _terrain_height(x, z, noise), z), randf_range(3.0, 7.0))
	for i in range(58):
		var x := randf_range(-56.0, 56.0)
		var z := randf_range(-56.0, 56.0)
		if Vector2(x, z).distance_to(Vector2(-14, -13)) < 18.0:
			continue
		if Vector2(x, z).distance_to(Vector2(43, 18)) < 9.0:
			continue
		_add_tree(Vector3(x, _terrain_height(x, z, noise), z), randf_range(0.75, 1.35))

func _add_road(center: Vector3, size: Vector3, color: Color) -> void:
	var road := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	road.mesh = mesh
	road.position = center
	road.material_override = _mat(color, 0.0, 1.0)
	add_child(road)
	for side in [-1.0, 1.0]:
		var shoulder := MeshInstance3D.new()
		var shoulder_mesh := BoxMesh.new()
		shoulder_mesh.size = Vector3(size.x, 0.06, size.z + 0.9) if size.x > size.z else Vector3(size.x + 0.9, 0.06, size.z)
		shoulder.mesh = shoulder_mesh
		shoulder.position = center + Vector3(0, -0.035, 0)
		shoulder.material_override = _mat(Color(0.34, 0.31, 0.23), 0.0, 1.0)
		add_child(shoulder)
		break

func _add_crop_field(center: Vector3, field_size: Vector2, crop_color: Color) -> void:
	var plot := MeshInstance3D.new()
	var plot_mesh := PlaneMesh.new()
	plot_mesh.size = field_size
	plot.mesh = plot_mesh
	plot.position = center
	plot.material_override = _mat(crop_color.darkened(0.18), 0.0, 1.0)
	add_child(plot)
	var rows := MultiMesh.new()
	rows.transform_format = MultiMesh.TRANSFORM_3D
	var stalk := BoxMesh.new()
	stalk.size = Vector3(0.18, 0.42, 0.11)
	rows.mesh = stalk
	rows.instance_count = 360
	for i in range(rows.instance_count):
		var col := i % 20
		var row := i / 20
		var px := -field_size.x * 0.44 + float(col) * field_size.x * 0.88 / 19.0
		var pz := -field_size.y * 0.43 + float(row) * field_size.y * 0.86 / 17.0
		var basis := Basis(Vector3.UP, randf_range(-0.12, 0.12)).scaled(Vector3.ONE * randf_range(0.8, 1.25))
		rows.set_instance_transform(i, Transform3D(basis, Vector3(px, 0.22, pz)))
	var crop_mesh := MultiMeshInstance3D.new()
	crop_mesh.multimesh = rows
	crop_mesh.position = center
	crop_mesh.material_override = _mat(crop_color.lightened(0.18), 0.0, 0.9)
	add_child(crop_mesh)

func _add_tree(pos: Vector3, scale_factor: float) -> void:
	var tree := Node3D.new()
	tree.position = pos
	tree.scale = Vector3.ONE * scale_factor
	add_child(tree)
	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.22
	trunk_mesh.bottom_radius = 0.38
	trunk_mesh.height = 2.7
	trunk.mesh = trunk_mesh
	trunk.position.y = 1.25
	trunk.material_override = _mat(Color(0.25, 0.17, 0.10), 0.0, 1.0)
	tree.add_child(trunk)
	for layer in range(3):
		var crown := MeshInstance3D.new()
		var crown_mesh := CylinderMesh.new()
		crown_mesh.top_radius = 0.05
		crown_mesh.bottom_radius = 1.65 - float(layer) * 0.24
		crown_mesh.height = 2.0
		crown_mesh.radial_segments = 7
		crown.mesh = crown_mesh
		crown.position.y = 2.25 + float(layer) * 0.82
		crown.material_override = _mat([Color(0.12,0.22,0.12), Color(0.16,0.27,0.14), Color(0.20,0.30,0.16)][layer], 0.0, 1.0)
		tree.add_child(crown)

func _add_rock(pos: Vector3, size: float) -> void:
	var rock := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = size * randf_range(0.18, 0.42)
	mesh.bottom_radius = size
	mesh.height = size * randf_range(0.8, 1.45)
	mesh.radial_segments = 7
	mesh.rings = 2
	rock.mesh = mesh
	rock.position = pos + Vector3(0, mesh.height * 0.45, 0)
	rock.rotation_degrees = Vector3(randf_range(-9, 9), randf_range(0, 360), randf_range(-12, 12))
	rock.material_override = _mat(Color(0.28, 0.28, 0.25), 0.0, 1.0)
	add_child(rock)

func _build_landscape_details() -> void:
	# Layered low-poly terrain silhouettes around the playable area.
	var ridge_specs := [
		[Vector3(-49.0, 3.0, -48.0), Vector3(19.0, 10.0, 13.0)],
		[Vector3(-27.0, 4.0, -53.0), Vector3(24.0, 13.0, 15.0)],
		[Vector3(4.0, 3.0, -54.0), Vector3(21.0, 9.0, 14.0)],
		[Vector3(48.0, 4.0, -49.0), Vector3(23.0, 12.0, 16.0)],
		[Vector3(-52.0, 3.0, 38.0), Vector3(22.0, 10.0, 16.0)],
		[Vector3(51.0, 4.0, 39.0), Vector3(25.0, 13.0, 18.0)]
	]
	for spec in ridge_specs:
		var hill := MeshInstance3D.new()
		var hill_mesh := SphereMesh.new()
		hill_mesh.radius = 1.0
		hill_mesh.height = 2.0
		hill.mesh = hill_mesh
		hill.position = spec[0]
		hill.scale = spec[1]
		hill.material_override = _mat(Color(0.30, 0.31, 0.25), 0.0, 1.0)
		add_child(hill)
		# A smaller rocky crown breaks the silhouette and gives the ridge depth.
		var crown := MeshInstance3D.new()
		var crown_mesh := SphereMesh.new()
		crown_mesh.radius = 1.0
		crown_mesh.height = 1.7
		crown.mesh = crown_mesh
		crown.position = spec[0] + Vector3(0.0, spec[1].y * 0.52, -1.5)
		crown.scale = Vector3(spec[1].x * 0.48, spec[1].y * 0.62, spec[1].z * 0.72)
		crown.material_override = _mat(Color(0.24, 0.25, 0.22), 0.0, 1.0)
		add_child(crown)

	# Agricultural plots with repeated crop furrows; MultiMesh keeps draw calls low.
	_add_field_patch(Vector3(-42.0, 0.07, 4.0), Vector2(18.0, 25.0), Color(0.43, 0.38, 0.20))
	_add_field_patch(Vector3(39.0, 0.07, -13.0), Vector2(19.0, 27.0), Color(0.36, 0.38, 0.20))
	_add_field_patch(Vector3(5.0, 0.07, 43.0), Vector2(25.0, 13.0), Color(0.39, 0.36, 0.19))

	# A narrow pond adds a natural landmark beside the eastern fields.
	var pond := MeshInstance3D.new()
	var water := PlaneMesh.new()
	water.size = Vector2(12.0, 7.0)
	pond.mesh = water
	pond.position = Vector3(43.0, 0.10, 18.0)
	var water_mat := _mat(Color(0.10, 0.27, 0.31), 0.28, 0.22)
	water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_mat.albedo_color.a = 0.88
	pond.material_override = water_mat
	add_child(pond)

func _add_field_patch(center: Vector3, field_size: Vector2, field_color: Color) -> void:
	var plot := MeshInstance3D.new()
	var plot_mesh := PlaneMesh.new()
	plot_mesh.size = field_size
	plot.mesh = plot_mesh
	plot.position = center
	plot.material_override = _mat(field_color, 0.0, 1.0)
	add_child(plot)

	var furrow_mesh := BoxMesh.new()
	furrow_mesh.size = Vector3(0.10, 0.045, field_size.y * 0.94)
	var furrows := MultiMesh.new()
	furrows.transform_format = MultiMesh.TRANSFORM_3D
	furrows.mesh = furrow_mesh
	furrows.instance_count = 17
	for i in range(furrows.instance_count):
		var x_offset := -field_size.x * 0.44 + float(i) * field_size.x * 0.88 / 16.0
		furrows.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(x_offset, 0.04, 0.0)))
	var furrow_instance := MultiMeshInstance3D.new()
	furrow_instance.multimesh = furrows
	furrow_instance.position = center + Vector3(0.0, 0.035, 0.0)
	furrow_instance.material_override = _mat(field_color.darkened(0.24), 0.0, 1.0)
	add_child(furrow_instance)

func _build_camera() -> void:
	camera = Camera3D.new()
	camera.position = Vector3(0, zoom, zoom*0.82)
	camera.current = true
	add_child(camera)
	_update_camera()

func _update_camera() -> void:
	if not is_instance_valid(camera):
		return
	var focus := Vector3(camera.position.x, 0, camera.position.z - zoom*0.48)
	var offset := Vector3(sin(camera_yaw)*zoom*0.82, zoom, cos(camera_yaw)*zoom*0.82)
	camera.position = focus + offset
	camera.look_at(focus, Vector3.UP)

func _make_building(pos: Vector3, size: Vector3, color: Color, label: String) -> void:
	var b := Node3D.new()
	b.position = pos
	b.name = "مبنى_قيادة" if label == "HQ" else "مبنى_قاعدة"
	add_child(b)
	# Use authored Quaternius building meshes; never replace a missing model with a visible box.
	if building_models.size() > 0:
		var model_index := 1 if label == "HQ" and building_models.size() > 1 else (2 if size.x >= 9.0 and building_models.size() > 2 else 0)
		var visual := building_models[model_index].instantiate() as Node3D
		visual.name = "RealBuildingModel"
		visual.scale = Vector3.ONE * (1.15 if label == "HQ" else 0.9)
		b.add_child(visual)
	else:
		push_error("Missing real building GLB; building intentionally not rendered as a primitive.")
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	collision.position.y = size.y / 2.0
	body.add_child(collision)
	b.add_child(body)
	if label == "HQ":
		var flag := Label3D.new()
		flag.text = "قبيلة ال طنجة"
		flag.font_size = 48
		flag.position = Vector3(0, size.y + 3.0, 0)
		b.add_child(flag)

func _make_tank(pos: Vector3, color: Color, team: int) -> Node3D:
	var tank := Node3D.new()
	tank.position = pos
	tank.set_meta("team",team)
	tank.set_meta("moving",false)
	tank.set_meta("health",100.0)
	tank.set_meta("max_health",100.0)
	tank.set_meta("damage",14.0 if team == 0 else 10.0)
	tank.set_meta("attack_range",19.0 if team == 0 else 16.0)
	tank.set_meta("cooldown",randf_range(0.2,1.0))
	add_child(tank)
	var hit_body := StaticBody3D.new()
	hit_body.position = Vector3(0,1.1,0)
	hit_body.set_meta("team",team)
	var hit_shape := CollisionShape3D.new()
	var hit_box := BoxShape3D.new()
	hit_box.size = Vector3(4.8,3.0,6.0)
	hit_shape.shape = hit_box
	hit_body.add_child(hit_shape)
	tank.add_child(hit_body)
	# Use the imported CC0 tank model. Keep the old primitive fallback only for editor/import failures.
	if tank_model_scene != null:
		var visual := tank_model_scene.instantiate() as Node3D
		visual.name = "ImportedTankModel"
		visual.position = Vector3(0, 0.12, 0)
		visual.scale = Vector3(1.0, 1.0, 1.0)
		tank.add_child(visual)
	else:
		_build_detailed_tank(tank, color)
	units.append(tank)
	return tank


func _build_detailed_tank(tank: Node3D, paint: Color) -> void:
	# Layered hull, continuous track guards, individually visible road wheels and a detailed turret.
	_box(tank, Vector3(3.55, 0.72, 4.85), Vector3(0, 0.92, 0), paint.darkened(0.08))
	_box(tank, Vector3(3.0, 0.24, 3.8), Vector3(0, 1.36, 0.05), paint.lightened(0.08))
	for side in [-1.0, 1.0]:
		_box(tank, Vector3(0.52, 0.82, 4.95), Vector3(side * 1.86, 0.60, 0), Color(0.105,0.115,0.105))
		for wheel in range(7):
			var wz := -2.0 + float(wheel) * 0.66
			_cylinder(tank, 0.37, 0.18, Vector3(side * 2.14, 0.57, wz), Color(0.16,0.17,0.15))
			_cylinder(tank, 0.16, 0.195, Vector3(side * 2.15, 0.57, wz), Color(0.36,0.36,0.31))
		_box(tank, Vector3(0.12,0.12,4.35), Vector3(side * 2.14,1.02,0), Color(0.27,0.28,0.24))
	_box(tank, Vector3(2.55,0.58,2.55), Vector3(0,1.72,-0.12), paint.lightened(0.12))
	_cylinder(tank, 0.92, 0.22, Vector3(0,2.06,-0.12), Color(0.15,0.16,0.14))
	_box(tank, Vector3(1.72,0.62,1.72), Vector3(0,2.34,-0.15), paint)
	_cylinder(tank, 0.22, 3.15, Vector3(0,2.42,-2.05), Color(0.16,0.17,0.15))
	_cylinder(tank, 0.27, 0.42, Vector3(0,2.42,-3.58), Color(0.11,0.12,0.11))
	_box(tank, Vector3(0.52,0.34,0.62), Vector3(0.52,2.78,0.22), paint.darkened(0.12))
	_cylinder(tank, 0.28, 0.12, Vector3(-0.48,2.72,-0.25), Color(0.12,0.13,0.12))
	for side in [-1.0,1.0]:
		var lamp := MeshInstance3D.new()
		var lamp_mesh := SphereMesh.new()
		lamp_mesh.radius = 0.12
		lamp.mesh = lamp_mesh
		lamp.position = Vector3(side * 1.22,1.22,-2.40)
		lamp.material_override = _mat(Color(0.82,0.72,0.42),0.1,0.25)
		tank.add_child(lamp)

func _make_guard_tower(pos: Vector3, team: int) -> void:
	if guard_tower_scene == null:
		return
	var tower := guard_tower_scene.instantiate() as Node3D
	tower.position = pos
	tower.name = "ImportedGuardTower_%d" % team
	tower.scale = Vector3.ONE * 1.7
	add_child(tower)

func _build_armies() -> void:
	_make_building(Vector3(-14,0,-13),Vector3(10,3.5,9),Color(0.22,0.31,0.25),"HQ")
	_make_guard_tower(Vector3(-27,0,-22), 0)
	_make_guard_tower(Vector3(-2,0,-22), 0)
	_make_building(Vector3(-27,0,-10),Vector3(7,2.8,7),Color(0.35,0.31,0.22),"")
	_make_building(Vector3(-13,0,-28),Vector3(8,3.2,7),Color(0.28,0.29,0.27),"")
	for i in range(5):
		_make_tank(Vector3(-20+i*4.2,0,-1),Color(0.29,0.38,0.25),0)
	var colors=[Color(0.55,0.22,0.16),Color(0.18,0.34,0.55),Color(0.58,0.48,0.16),Color(0.42,0.25,0.52),Color(0.18,0.48,0.43)]
	var faction_z=[-38.0,-20.0,0.0,20.0,38.0]
	for team in range(5):
		var x := 31.0 + (team%2)*5.0
		var z: float = faction_z[team]
		_make_building(Vector3(x,0,z),Vector3(8,3,8),colors[team],"")
		for j in range(3):
			_make_tank(Vector3(x-5+j*3.2,0,z+9),colors[team],team+1)

func _build_hud() -> void:
	hud=CanvasLayer.new()
	add_child(hud)
	var panel=PanelContainer.new()
	panel.position=Vector2(18,16)
	panel.size=Vector2(470,104)
	hud.add_child(panel)
	var col=VBoxContainer.new()
	panel.add_child(col)
	var title=Label.new()
	title.text="قبيلة ال طنجة  |  القيادة والسيطرة"
	title.add_theme_font_size_override("font_size",25)
	col.add_child(title)
	status_label=Label.new()
	status_label.text="الموارد: 5000  |  الطاقة: 100%  |  القوات: جاهزة"
	col.add_child(status_label)
	var hint=Label.new()
	hint.text="المس وحدة لتحديدها، ثم المس الأرض لإصدار أمر حركة"
	hint.position=Vector2(20,126)
	hint.add_theme_font_size_override("font_size",18)
	hud.add_child(hint)
	var flag=Label.new()
	flag.text="🏴  قبيلة ال طنجة"
	flag.position=Vector2(20,162)
	flag.add_theme_font_size_override("font_size",24)
	hud.add_child(flag)
	var train_button := Button.new()
	train_button.text = "تدريب دبابة جديدة — 800 مورد"
	train_button.position = Vector2(20, 205)
	train_button.size = Vector2(300, 54)
	train_button.add_theme_font_size_override("font_size", 19)
	train_button.pressed.connect(_train_tank)
	hud.add_child(train_button)

func _player_unit_count() -> int:
	var count := 0
	for unit in units:
		if is_instance_valid(unit) and int(unit.get_meta("team", -1)) == 0:
			count += 1
	return count

func _train_tank() -> void:
	if resources < 800:
		status_label.text = "الموارد غير كافية — تحتاج 800 مورد"
		return
	resources -= 800
	var count := _player_unit_count()
	var spawn := Vector3(-20.0 + float(count % 4) * 4.2, 0, 5.0 + float(count / 4) * 4.2)
	_make_tank(spawn, Color(0.29, 0.38, 0.25), 0)
	status_label.text = "بدأ تدريب دبابة جديدة — جاهزة للقتال"

func _combat_unit(unit: Node3D, delta: float) -> void:
	var enemy := _nearest_enemy(unit)
	if not is_instance_valid(enemy):
		return
	var distance := unit.global_position.distance_to(enemy.global_position)
	var attack_range := float(unit.get_meta("attack_range", 16.0))
	var team := int(unit.get_meta("team", -1))
	if team != 0 and distance > attack_range:
		unit.set_meta("move_target", Vector3(enemy.global_position.x, 0, enemy.global_position.z))
		unit.set_meta("moving", true)
	if distance <= attack_range:
		var cooldown := maxf(0.0, float(unit.get_meta("cooldown", 0.0)) - delta)
		if cooldown <= 0.0:
			var health := float(enemy.get_meta("health", 100.0))
			health -= float(unit.get_meta("damage", 10.0))
			enemy.set_meta("health", health)
			unit.set_meta("cooldown", 1.25 if team == 0 else 1.65)
			if health <= 0.0:
				if enemy == selected:
					selected = null
					if is_instance_valid(selection_ring):
						selection_ring.queue_free()
						selection_ring = null
				units.erase(enemy)
				enemy.queue_free()

func _nearest_enemy(unit: Node3D) -> Node3D:
	var nearest: Node3D = null
	var best_distance := INF
	var team := int(unit.get_meta("team", -1))
	for other in units:
		if not is_instance_valid(other) or other == unit:
			continue
		if int(other.get_meta("team", -1)) == team:
			continue
		var distance := unit.global_position.distance_to(other.global_position)
		if distance < best_distance:
			best_distance = distance
			nearest = other
	return nearest

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			drag_start=event.position
			dragging=true
			moved_gesture=false
		else:
			if dragging and not moved_gesture and event.position.distance_to(drag_start)<18:
				_handle_tap(event.position)
			dragging=false
	elif event is InputEventScreenDrag and dragging:
		if event.position.distance_to(drag_start)>18:
			moved_gesture=true
		_pan(event.relative)
	elif event is InputEventMagnifyGesture:
		zoom=clamp(zoom/event.factor,CAMERA_MIN,CAMERA_MAX)
		_update_camera()
	elif event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom=max(CAMERA_MIN,zoom-3.0); _update_camera()
		elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom=min(CAMERA_MAX,zoom+3.0); _update_camera()
		elif event.button_index==MOUSE_BUTTON_LEFT:
			if event.pressed: drag_start=event.position; dragging=true
			else:
				if dragging and event.position.distance_to(drag_start)<8: _handle_tap(event.position)
				dragging=false
		elif event.button_index==MOUSE_BUTTON_RIGHT and event.pressed:
			_issue_move_at(event.position)
	elif event is InputEventMouseMotion and dragging:
		_pan(event.relative)
	elif event is InputEventKey and event.pressed:
		if event.keycode==KEY_Q:
			camera_yaw-=0.12; _update_camera()
		elif event.keycode==KEY_E:
			camera_yaw+=0.12; _update_camera()

func _handle_tap(screen_pos: Vector2) -> void:
	var hit := _ray_hit(screen_pos)
	if hit.is_empty():
		return
	var n: Node = hit.collider
	while n and not n.has_meta("team"):
		n=n.get_parent()
	if n and n.has_meta("team"):
		if int(n.get_meta("team")) == 0:
			_select_unit(n as Node3D)
		else:
			status_label.text="وحدة معادية — اختر دبابة من جيش ال طنجة أولاً"
	elif is_instance_valid(selected):
		_order_selected(hit.position)

func _ray_hit(screen_pos: Vector2) -> Dictionary:
	var from=camera.project_ray_origin(screen_pos)
	var to=from+camera.project_ray_normal(screen_pos)*350.0
	var query=PhysicsRayQueryParameters3D.create(from,to)
	return get_world_3d().direct_space_state.intersect_ray(query)

func _select_unit(unit: Node3D) -> void:
	selected=unit
	if is_instance_valid(selection_ring):
		selection_ring.queue_free()
	var ring := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius=2.4
	mesh.outer_radius=2.65
	ring.mesh=mesh
	ring.material_override=_mat(Color(0.2,0.95,0.28),0.0,0.35)
	ring.rotation_degrees.x=90
	add_child(ring)
	selection_ring=ring
	status_label.text="تم تحديد دبابة من جيش قبيلة ال طنجة"

func _issue_move_at(screen_pos: Vector2) -> void:
	if not is_instance_valid(selected):
		return
	var hit := _ray_hit(screen_pos)
	if not hit.is_empty():
		_order_selected(hit.position)

func _order_selected(destination: Vector3) -> void:
	selected.set_meta("move_target",Vector3(destination.x,0,destination.z))
	selected.set_meta("moving",true)
	status_label.text="أمر حركة صادر — الدبابة تتقدم إلى الموقع المحدد"

func _pan(delta: Vector2) -> void:
	camera.position.x-=delta.x*0.065
	camera.position.z-=delta.y*0.065
	camera.position.x=clamp(camera.position.x,-72,72)
	camera.position.z=clamp(camera.position.z,-72,72)
	_update_camera()
