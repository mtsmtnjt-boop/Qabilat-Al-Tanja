extends Node3D

const FIELD_SIZE := 90.0
var camera: Camera3D
var selected: Node3D
var drag_start := Vector2.ZERO
var dragging := false
var zoom := 34.0
var units: Array[Node3D] = []
var hud: CanvasLayer
var status_label: Label

func _ready() -> void:
	_build_world()
	_build_camera()
	_build_armies()
	_build_hud()

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
	node.material_override = _mat(color, 0.12)
	parent.add_child(node)
	return node

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	e.sky = Sky.new()
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.65, 0.68, 0.62)
	e.ambient_light_energy = 0.7
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -28, 0)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(FIELD_SIZE, FIELD_SIZE)
	ground.mesh = plane
	ground.material_override = _mat(Color(0.34, 0.31, 0.22))
	add_child(ground)
	# Sandy terrain patches and roads make the battlefield readable.
	for i in range(34):
		var patch := MeshInstance3D.new()
		var p := CylinderMesh.new()
		p.top_radius = randf_range(0.8, 3.2)
		p.bottom_radius = p.top_radius
		p.height = 0.05
		patch.mesh = p
		patch.position = Vector3(randf_range(-42,42),0.04,randf_range(-42,42))
		patch.material_override = _mat([Color(0.39,0.35,0.25),Color(0.29,0.30,0.22),Color(0.43,0.37,0.26)][i%3])
		add_child(patch)
	_box(self, Vector3(90,0.08,5), Vector3(0,0.07,5), Color(0.22,0.22,0.19))
	# rocks around edges
	for i in range(22):
		var rock := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = randf_range(0.5,1.5)
		sphere.height = sphere.radius*1.4
		rock.mesh = sphere
		rock.position = Vector3(randf_range(-43,43),sphere.radius*0.35,randf_range(-43,43))
		rock.material_override = _mat(Color(0.25,0.25,0.22))
		add_child(rock)

func _build_camera() -> void:
	camera = Camera3D.new()
	camera.position = Vector3(0, zoom, zoom*0.85)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	camera.current = true
	add_child(camera)

func _make_building(pos: Vector3, size: Vector3, color: Color, label: String) -> void:
	var b := Node3D.new()
	b.position = pos
	add_child(b)
	_box(b,size,Vector3(0,size.y/2,0),color)
	_box(b,Vector3(size.x*0.72,0.55,size.z*0.72),Vector3(0,size.y+0.25,0),Color(0.24,0.25,0.23))
	if label == "HQ":
		_box(b,Vector3(0.18,3.2,0.18),Vector3(1.4,size.y+1.6,0),Color(0.13,0.13,0.12))
		_box(b,Vector3(2.2,1.25,0.08),Vector3(2.5,size.y+2.2,0),Color(0.04,0.04,0.04))
		var flag := Label3D.new()
		flag.text = "معتصم الموالي"
		flag.font_size = 42
		flag.position = Vector3(2.5,size.y+2.2,0.08)
		flag.modulate = Color.WHITE
		b.add_child(flag)

func _make_tank(pos: Vector3, color: Color, team: int) -> Node3D:
	var tank := Node3D.new()
	tank.position = pos
	tank.set_meta("team",team)
	add_child(tank)
	# Real collision body: without this, touch selection raycasts hit nothing.
	var hit_body := StaticBody3D.new()
	hit_body.position = Vector3(0,1.15,0)
	hit_body.set_meta("team",team)
	var hit_shape := CollisionShape3D.new()
	var hit_box := BoxShape3D.new()
	hit_box.size = Vector3(4.4,3.0,5.8)
	hit_shape.shape = hit_box
	hit_body.add_child(hit_shape)
	tank.add_child(hit_body)
	_box(tank,Vector3(3.2,0.8,4.4),Vector3(0,0.75,0),color)
	_box(tank,Vector3(2.0,0.65,2.3),Vector3(0,1.4,-0.1),color.lightened(0.12))
	_box(tank,Vector3(0.45,0.35,2.8),Vector3(0,1.55,-1.8),Color(0.18,0.19,0.17))
	for side in [-1.0,1.0]:
		_box(tank,Vector3(0.45,0.65,4.8),Vector3(side*1.75,0.55,0),Color(0.12,0.13,0.12))
	units.append(tank)
	return tank

func _build_armies() -> void:
	_make_building(Vector3(-12,0,-10),Vector3(9,3.2,8),Color(0.22,0.31,0.25),"HQ")
	_make_building(Vector3(-23,0,-8),Vector3(6,2.5,6),Color(0.35,0.31,0.22),"")
	_make_building(Vector3(-10,0,-23),Vector3(7,3,6),Color(0.28,0.29,0.27),"")
	for i in range(4):
		_make_tank(Vector3(-16+i*3.6,0,-1),Color(0.29,0.38,0.25),0)
	# Five rival factions face the strongest Al-Tanja army.
	var colors=[Color(0.55,0.22,0.16),Color(0.18,0.34,0.55),Color(0.58,0.48,0.16),Color(0.42,0.25,0.52),Color(0.18,0.48,0.43)]
	var faction_z=[-30.0,-15.0,0.0,15.0,30.0]
	for team in range(5):
		var x := 23.0 + (team%2)*7.0
		var z := faction_z[team]
		_make_building(Vector3(x,0,z),Vector3(7,2.8,7),colors[team],"")
		for j in range(2):
			_make_tank(Vector3(x-4+j*3.0,0,z+7),colors[team],team+1)

func _build_hud() -> void:
	hud=CanvasLayer.new()
	add_child(hud)
	var panel=PanelContainer.new()
	panel.position=Vector2(18,16)
	panel.size=Vector2(410,90)
	hud.add_child(panel)
	var col=VBoxContainer.new()
	panel.add_child(col)
	var title=Label.new()
	title.text="قبيلة ال طنجة  |  القيادة والسيطرة"
	title.add_theme_font_size_override("font_size",25)
	col.add_child(title)
	status_label=Label.new()
	status_label.text="الموارد: 5000  |  الطاقة: 100%  |  الجيش: جاهز"
	col.add_child(status_label)
	var hint=Label.new()
	hint.text="اسحب بإصبعك لتحريك الكاميرا • المس دبابة لتحديدها"
	hint.position=Vector2(20,112)
	hint.add_theme_font_size_override("font_size",18)
	hud.add_child(hint)
	var flag=Label.new()
	flag.text="🏴  معتصم الموالي"
	flag.position=Vector2(20,150)
	flag.add_theme_font_size_override("font_size",24)
	hud.add_child(flag)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			drag_start=event.position
			dragging=true
		else:
			if dragging and event.position.distance_to(drag_start)<18:
				_select_at(event.position)
			dragging=false
	elif event is InputEventScreenDrag and dragging:
		_pan(event.relative)
	elif event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom=max(18.0,zoom-2.5); _update_camera()
		elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom=min(55.0,zoom+2.5); _update_camera()
		elif event.button_index==MOUSE_BUTTON_LEFT:
			if event.pressed: drag_start=event.position; dragging=true
			else:
				if dragging and event.position.distance_to(drag_start)<8: _select_at(event.position)
				dragging=false
	elif event is InputEventMouseMotion and dragging:
		_pan(event.relative)

func _pan(delta: Vector2) -> void:
	camera.position.x-=delta.x*0.055
	camera.position.z-=delta.y*0.055
	camera.position.x=clamp(camera.position.x,-55,55)
	camera.position.z=clamp(camera.position.z,-55,55)
	camera.look_at(Vector3(camera.position.x,0,camera.position.z-zoom*0.45),Vector3.UP)

func _update_camera() -> void:
	camera.position.y=zoom
	camera.position.z=zoom*0.85
	camera.look_at(Vector3(camera.position.x,0,camera.position.z-zoom*0.45),Vector3.UP)

func _select_at(screen_pos: Vector2) -> void:
	var from=camera.project_ray_origin(screen_pos)
	var to=from+camera.project_ray_normal(screen_pos)*250.0
	var query=PhysicsRayQueryParameters3D.create(from,to)
	var space=get_world_3d().direct_space_state
	var hit=space.intersect_ray(query)
	if hit:
		var n=hit.collider
		while n and not n.has_meta("team"):
			n=n.get_parent()
		if n and n.has_meta("team"):
			selected=n
			status_label.text="تم تحديد وحدة من جيش ال طنجة • اسحب الشاشة لتحريك الكاميرا"
