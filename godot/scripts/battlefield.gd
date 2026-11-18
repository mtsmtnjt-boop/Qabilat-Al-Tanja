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
		var scene := load(path) as PackedScene
		if scene != null:
			building_models.append(scene)
	for path in ["res://assets/tree1.glb", "res://assets/tree2.glb", "res://assets/tree3.glb"]:
		var scene := load(path) as PackedScene
		if scene != null:
			tree_models.append(scene)
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
	e.ambient_light_energy = 0.8
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -28, 0)
	sun.light_energy = 1.45
	sun.shadow_enabled = true
	add_child(sun)

	var ground_body := StaticBody3D.new()
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(FIELD_SIZE, FIELD_SIZE)
	ground.mesh = plane
	ground.material_override = _mat(Color(0.31, 0.30, 0.23))
	ground_body.add_child(ground)
	var ground_shape := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(FIELD_SIZE, 0.4, FIELD_SIZE)
	ground_shape.shape = shape
	ground_shape.position.y = -0.22
	ground_body.add_child(ground_shape)
	add_child(ground_body)

	# Broken terrain coloration, roads, rocky ridges and sparse vegetation.
	for i in range(85):
		var patch := MeshInstance3D.new()
		var p := CylinderMesh.new()
		p.top_radius = randf_range(0.7, 3.8)
		p.bottom_radius = p.top_radius
		p.height = 0.035
		patch.mesh = p
		patch.position = Vector3(randf_range(-55,55),0.025,randf_range(-55,55))
		patch.material_override = _mat([Color(0.38,0.35,0.27),Color(0.25,0.29,0.22),Color(0.43,0.38,0.28)][i%3])
		add_child(patch)
	_box(self, Vector3(120,0.07,7), Vector3(0,0.045,8), Color(0.19,0.20,0.18))
	_box(self, Vector3(7,0.075,120), Vector3(-18,0.05,0), Color(0.20,0.21,0.19))
	for i in range(32):
		var rock := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = randf_range(0.45,1.6)
		sphere.height = sphere.radius * 1.35
		rock.mesh = sphere
		rock.position = Vector3(randf_range(-57,57),sphere.radius*0.3,randf_range(-57,57))
		rock.material_override = _mat(Color(0.24,0.25,0.22))
		add_child(rock)
	for i in range(24):
		if tree_models.is_empty():
			push_error("Missing real tree GLB; skipping tree rather than drawing a sphere.")
			break
		var tree := tree_models[i % tree_models.size()].instantiate() as Node3D
		tree.position = Vector3(randf_range(-54,54),0,randf_range(-54,54))
		tree.scale = Vector3.ONE * randf_range(1.1, 1.8)
		add_child(tree)

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
		_box(tank,Vector3(3.35,0.8,4.7),Vector3(0,0.8,0),color)
		_box(tank,Vector3(2.15,0.72,2.35),Vector3(0,1.48,-0.15),color.lightened(0.12))
		_cylinder(tank,0.82,0.22,Vector3(0,1.88,-0.1),Color(0.16,0.17,0.15))
		_box(tank,Vector3(0.38,0.38,3.4),Vector3(0,1.65,-2.0),Color(0.17,0.18,0.16))
		for side in [-1.0,1.0]:
			_box(tank,Vector3(0.48,0.72,4.9),Vector3(side*1.82,0.58,0),Color(0.12,0.13,0.12))
			for wheel in range(5):
				_cylinder(tank,0.34,0.16,Vector3(side*2.08,0.52,-1.75+wheel*0.86),Color(0.09,0.10,0.09))
	units.append(tank)
	return tank

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
