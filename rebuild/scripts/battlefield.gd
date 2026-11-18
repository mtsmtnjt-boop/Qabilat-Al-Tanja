extends Node3D

const MAP_SIZE := 120.0
const PLAYER := Color(0.16, 0.42, 0.27)
const ENEMY := Color(0.58, 0.20, 0.16)

var camera: Camera3D
var pivot: Node3D
var world: Node3D
var hud: CanvasLayer
var status_label: Label
var money := 5200
var selected: Node3D
var units: Array[Node3D] = []
var enemies: Array[Node3D] = []
var buildings: Array[Node3D] = []
var orbit := 0.0
var pitch := -0.82
var distance := 48.0
var drag_last := Vector2.ZERO
var touch_points: Dictionary = {}
var pinch_start := 0.0
var game_time := 0.0
var infantry_count := 0
var tank_count := 0

func _ready() -> void:
	_build_world()
	_build_camera()
	_build_base()
	_build_enemies()
	_build_hud()
	_update_camera()
	_set_status("القاعدة جاهزة — اختر وحدة أو أنشئ قواتك")

func _process(delta: float) -> void:
	game_time += delta
	for enemy in enemies:
		if is_instance_valid(enemy):
			var phase := game_time * 0.35 + float(enemy.get_instance_id() % 13)
			enemy.position.x += sin(phase) * delta * 0.35
			enemy.position.z += cos(phase) * delta * 0.25
	for unit in units:
		if is_instance_valid(unit) and unit.has_meta("move_target"):
			var target: Vector3 = unit.get_meta("move_target")
			var step := 7.0 * delta
			unit.position = unit.position.move_toward(target, step)
			if unit.position.distance_to(target) < 0.18:
				unit.remove_meta("move_target")

func _build_world() -> void:
	world = Node3D.new()
	world.name = "BattlefieldWorld"
	add_child(world)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(MAP_SIZE, MAP_SIZE)
	ground.mesh = plane
	ground.material_override = _mat(Color(0.25, 0.32, 0.22))
	world.add_child(ground)
	# Terrain panels add broad natural color variation without a flat black void.
	for i in range(42):
		var patch := MeshInstance3D.new()
		var m := CylinderMesh.new()
		m.top_radius = randf_range(2.0, 6.0)
		m.bottom_radius = m.top_radius
		m.height = 0.08
		patch.mesh = m
		patch.position = Vector3(randf_range(-55,55), 0.04, randf_range(-55,55))
		patch.material_override = _mat([Color(0.31,0.36,0.23),Color(0.35,0.34,0.22),Color(0.22,0.30,0.21)][i % 3])
		world.add_child(patch)
	_add_road(Vector3(0,0.08,0), Vector3(0,0.08,45), 7.0)
	_add_road(Vector3(-42,0.09,8), Vector3(42,0.09,8), 5.0)
	for i in range(55):
		_make_tree(Vector3(randf_range(-57,57),0,randf_range(-57,57)))

func _add_road(a: Vector3, b: Vector3, width: float) -> void:
	var road := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width,0.12,a.distance_to(b))
	road.mesh = mesh
	road.position = (a+b)*0.5
	road.rotation.y = atan2(b.x-a.x,b.z-a.z)
	road.material_override = _mat(Color(0.18,0.19,0.17))
	world.add_child(road)
	for i in range(1,8):
		var mark := MeshInstance3D.new()
		var stripe := BoxMesh.new()
		stripe.size = Vector3(0.18,0.025,2.2)
		mark.mesh = stripe
		mark.position = a.lerp(b,float(i)/8.0) + Vector3(0,0.08,0)
		mark.material_override = _mat(Color(0.72,0.68,0.48))
		world.add_child(mark)

func _make_tree(pos: Vector3) -> void:
	var tree := Node3D.new()
	tree.position = pos
	world.add_child(tree)
	_part(tree, Vector3(0,1.0,0), Vector3(0.42,2.0,0.42), Color(0.25,0.17,0.10))
	_part(tree, Vector3(0,2.35,0), Vector3(2.1,2.8,2.1), [Color(0.12,0.25,0.14),Color(0.17,0.30,0.16)][randi()%2], 1)
	_part(tree, Vector3(0.25,3.0,0.1), Vector3(1.25,1.8,1.25), Color(0.20,0.34,0.18), 1)

func _build_camera() -> void:
	pivot = Node3D.new()
	pivot.position = Vector3(0,0,0)
	add_child(pivot)
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 48
	pivot.add_child(camera)

func _update_camera() -> void:
	camera.position = Vector3(0, distance * 0.72, distance)
	camera.rotation = Vector3(pitch,0,0)
	pivot.rotation.y = orbit

func _build_base() -> void:
	_make_building("مركز القيادة",Vector3(-12,0,5),Vector3(10,5,8),Color(0.35,0.40,0.34),true)
	_make_building("مصنع المدرعات",Vector3(4,0,8),Vector3(12,4.5,9),Color(0.34,0.38,0.34),false)
	_make_building("ثكنة الجنود",Vector3(-27,0,17),Vector3(9,4,7),Color(0.39,0.37,0.29),false)
	_make_building("محطة الطاقة",Vector3(18,0,23),Vector3(8,5,8),Color(0.35,0.39,0.37),false)
	_make_building("مستودع الإمداد",Vector3(-5,0,29),Vector3(11,4,7),Color(0.39,0.35,0.27),false)
	for i in range(3):
		_make_tank(Vector3(-17 + i*5,0, -7),PLAYER,false)
	for i in range(5):
		_make_soldier(Vector3(-30 + i*2.1,0,5),PLAYER)
	_make_tower(Vector3(27,0,2),PLAYER)
	_make_tower(Vector3(-39,0,26),PLAYER)

func _build_enemies() -> void:
	for i in range(5):
		var base := Node3D.new()
		base.position = Vector3(randf_range(-38,38),0,randf_range(-48,-34))
		world.add_child(base)
		_make_building("موقع العدو",base.position,Vector3(8,4,7),ENEMY,false)
		var tank := _make_tank(base.position+Vector3(randf_range(-7,7),0,randf_range(-7,7)),ENEMY,true)
		enemies.append(tank)

func _make_building(label_text: String, pos: Vector3, size: Vector3, tint: Color, command: bool) -> void:
	var root := Node3D.new()
	root.position = pos
	root.name = label_text
	world.add_child(root)
	_part(root,Vector3(0,size.y*0.42,0),Vector3(size.x,size.y*0.84,size.z),tint)
	_part(root,Vector3(0,size.y*0.9,0),Vector3(size.x*1.08,0.45,size.z*1.08),Color(0.16,0.19,0.18))
	# Roof ridge, vents, doors and windows give each structure readable detail.
	_part(root,Vector3(0,size.y+0.5,0),Vector3(size.x*0.72,0.55,size.z*0.72),Color(0.22,0.25,0.23),1)
	_part(root,Vector3(0,1.2,size.z*0.51),Vector3(size.x*0.22,2.2,0.16),Color(0.10,0.13,0.12))
	for x in [-0.32,0.32]:
		_part(root,Vector3(size.x*x,size.y*0.55,size.z*0.51),Vector3(1.0,0.75,0.16),Color(0.10,0.18,0.19))
	for x in [-0.32,0.32]:
		_part(root,Vector3(size.x*x,size.y+1.0,0),Vector3(0.8,1.0,0.8),Color(0.24,0.28,0.25))
	if command:
		_part(root,Vector3(0,size.y+2.2,0),Vector3(0.16,3.0,0.16),Color(0.12,0.12,0.12))
		_part(root,Vector3(0.9,size.y+3.1,0),Vector3(1.8,0.9,0.08),Color(0.12,0.36,0.20))
	buildings.append(root)

func _make_tank(pos: Vector3, tint: Color, hostile: bool) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.name = "دبابة"
	world.add_child(root)
	var dark := Color(0.10,0.12,0.11)
	_part(root,Vector3(0,0.75,0),Vector3(4.4,1.05,6.0),dark)
	for side in [-1.0,1.0]:
		_part(root,Vector3(side*2.0,0.88,0),Vector3(0.45,1.15,6.2),Color(0.16,0.18,0.16))
		for j in range(6):
			_part(root,Vector3(side*2.25,0.72,-2.35+j*0.92),Vector3(0.20,0.82,0.68),Color(0.34,0.35,0.30),2)
	_part(root,Vector3(0,1.55,0.15),Vector3(3.2,0.9,3.7),tint)
	_part(root,Vector3(0,2.05,-0.05),Vector3(2.25,0.72,2.35),tint,2)
	_part(root,Vector3(0,2.08,-2.0),Vector3(0.42,0.42,3.7),dark,2)
	_part(root,Vector3(0,2.25,-3.8),Vector3(0.58,0.52,0.45),Color(0.18,0.20,0.18),2)
	_part(root,Vector3(0,2.7,0.2),Vector3(0.16,1.0,0.16),dark)
	if hostile:
		_part(root,Vector3(0,3.0,0.3),Vector3(1.0,0.45,0.08),ENEMY)
	units.append(root)
	return root

func _make_soldier(pos: Vector3, tint: Color) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.name = "جندي"
	world.add_child(root)
	_part(root,Vector3(0,1.0,0),Vector3(0.62,1.1,0.38),tint,2)
	_part(root,Vector3(0,1.82,0),Vector3(0.48,0.48,0.48),Color(0.68,0.53,0.38),2)
	_part(root,Vector3(0,2.12,0),Vector3(0.58,0.18,0.58),Color(0.15,0.20,0.15),2)
	_part(root,Vector3(0.42,1.05,-0.1),Vector3(0.14,0.16,1.0),Color(0.10,0.12,0.10),2)
	units.append(root)
	return root

func _make_tower(pos: Vector3, tint: Color) -> void:
	var root := Node3D.new()
	root.position = pos
	world.add_child(root)
	_part(root,Vector3(0,2.3,0),Vector3(3.2,4.6,3.2),Color(0.30,0.34,0.30))
	_part(root,Vector3(0,5.0,0),Vector3(4.0,0.55,4.0),tint)
	_part(root,Vector3(0,6.0,0),Vector3(2.2,1.6,2.2),Color(0.22,0.27,0.23))
	for x in [-1.0,1.0]:
		_part(root,Vector3(x,3.0,1.7),Vector3(0.22,2.0,0.15),Color(0.12,0.15,0.13))

func _part(parent: Node3D, pos: Vector3, size: Vector3, color: Color, shape: int = 0) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	if shape == 1:
		var mesh := SphereMesh.new()
		mesh.radius = maxf(size.x,size.y)*0.5
		mesh.height = maxf(size.x,size.y)
		node.mesh = mesh
	elif shape == 2:
		var mesh := CylinderMesh.new()
		mesh.top_radius = minf(size.x,size.z)*0.5
		mesh.bottom_radius = mesh.top_radius
		mesh.height = size.y
		node.mesh = mesh
	else:
		var mesh := BoxMesh.new()
		mesh.size = size
		node.mesh = mesh
	node.position = pos
	node.material_override = _mat(color)
	parent.add_child(node)
	return node

func _mat(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.88
	return material

func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	var panel := PanelContainer.new()
	panel.position = Vector2(12,12)
	panel.size = Vector2(370,112)
	hud.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	var title := Label.new()
	title.text = "⚔ قبيلة ال طنجة  |  مركز القيادة"
	title.add_theme_font_size_override("font_size",22)
	column.add_child(title)
	status_label = Label.new()
	status_label.text = "الموارد: 5200"
	column.add_child(status_label)
	var controls := HBoxContainer.new()
	controls.position = Vector2(12,132)
	controls.size = Vector2(720,58)
	hud.add_child(controls)
	_add_button(controls,"🏭 إنتاج دبابة  —  800",_train_tank)
	_add_button(controls,"🪖 تدريب جنود  —  250",_train_infantry)
	_add_button(controls,"⚙ الإعدادات",_show_settings)
	_add_button(controls,"⤢ تدوير",_rotate_button)
	var help := Label.new()
	help.text = "اسحب بإصبع واحد لتحريك الكاميرا • إصبعان للتدوير والتقريب • المس وحدة لاختيارها"
	help.position = Vector2(14, get_viewport().get_visible_rect().size.y-38)
	help.add_theme_font_size_override("font_size",16)
	hud.add_child(help)
	var minimap := Panel.new()
	minimap.position = Vector2(get_viewport().get_visible_rect().size.x-205,14)
	minimap.size = Vector2(188,145)
	hud.add_child(minimap)
	var map_label := Label.new()
	map_label.text = "خريطة المعركة\n\n🟢 قوات طنجة\n🔴 قوات الخصم"
	map_label.position = Vector2(12,10)
	minimap.add_child(map_label)

func _add_button(parent: HBoxContainer, caption: String, action: Callable) -> void:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size = Vector2(160,54)
	button.pressed.connect(action)
	parent.add_child(button)

func _set_status(message: String) -> void:
	if status_label:
		status_label.text = "الموارد: %d   |   %s" % [money,message]

func _train_tank() -> void:
	if money < 800:
		_set_status("الموارد غير كافية")
		return
	money -= 800
	tank_count += 1
	_make_tank(Vector3(-8 + (tank_count%3)*4,0, -5 + int(tank_count/3)*5),PLAYER,false)
	_set_status("تم إنتاج دبابة جديدة")

func _train_infantry() -> void:
	if money < 250:
		_set_status("الموارد غير كافية")
		return
	money -= 250
	infantry_count += 1
	for i in range(3):
		_make_soldier(Vector3(-27 + (infantry_count%4)*2 + i*0.8,0,12 + int(infantry_count/4)*2),PLAYER)
	_set_status("تم تدريب 3 جنود")

func _show_settings() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "إعدادات التحكم"
	dialog.dialog_text = "تحريك الكاميرا: سحب بإصبع واحد\nالتدوير والتقريب: سحب بإصبعين / حركة القرص\nالتحكم بالزوم: أزرار التقريب والتبعيد"
	add_child(dialog)
	dialog.popup_centered()

func _rotate_button() -> void:
	orbit += 0.28
	_update_camera()

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			touch_points[event.index] = event.position
			if touch_points.size() == 2:
				pinch_start = _touch_distance()
		else:
			if touch_points.size() == 1:
				if not _select_at(event.position):
					_order_selected_at(event.position)
			touch_points.erase(event.index)
	elif event is InputEventScreenDrag:
		touch_points[event.index] = event.position
		if touch_points.size() >= 2:
			var d := _touch_distance()
			if pinch_start > 0.0:
				distance = clampf(distance - (d-pinch_start)*0.055,18.0,85.0)
			pinch_start = d
			orbit += event.relative.x * 0.006
			pitch = clampf(pitch + event.relative.y*0.002,-1.18,-0.35)
			_update_camera()
		else:
			var right := pivot.global_transform.basis.x
			var forward := pivot.global_transform.basis.z
			pivot.position += (-right*event.relative.x + forward*event.relative.y) * distance * 0.0018
			_update_camera()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(18.0,distance-3.0)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(85.0,distance+3.0)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if not _select_at(event.position):
				_order_selected_at(event.position)
	elif event is InputEventMagnifyGesture:
		distance = clampf(distance / event.factor,18.0,85.0)
		_update_camera()

func _touch_distance() -> float:
	var keys := touch_points.keys()
	if keys.size() < 2:
		return 0.0
	return Vector2(touch_points[keys[0]]).distance_to(Vector2(touch_points[keys[1]]))

func _select_at(screen_pos: Vector2) -> bool:
	# Select using screen-space positions; no hidden collision dependency.
	var nearest: Node3D = null
	var nearest_distance := 72.0
	for unit in units:
		if not is_instance_valid(unit):
			continue
		var marker := unit.global_position + Vector3(0,2.2,0)
		if camera.is_position_behind(marker):
			continue
		var point := camera.unproject_position(marker)
		var d := point.distance_to(screen_pos)
		if d < nearest_distance:
			nearest_distance = d
			nearest = unit
	if nearest:
		selected = nearest
		_set_status("تم اختيار: " + str(selected.name))
		return true
	return false

func _order_selected_at(screen_pos: Vector2) -> void:
	if not is_instance_valid(selected):
		_set_status("اختر دبابة أو جندياً أولاً")
		return
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	if absf(direction.y) < 0.0001:
		return
	var distance_to_ground := -origin.y / direction.y
	if distance_to_ground <= 0.0:
		return
	var destination := origin + direction * distance_to_ground
	destination.x = clampf(destination.x, -MAP_SIZE * 0.48, MAP_SIZE * 0.48)
	destination.z = clampf(destination.z, -MAP_SIZE * 0.48, MAP_SIZE * 0.48)
	selected.set_meta("move_target", Vector3(destination.x, 0.0, destination.z))
	_set_status("أمر حركة: " + str(selected.name) + " يتقدم إلى الموقع المحدد")
