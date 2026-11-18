extends Node

var battlefield: Node3D
var layer: CanvasLayer

func _ready() -> void:
	battlefield = get_parent() as Node3D
	_build_controls.call_deferred()

func _build_controls() -> void:
	if not is_instance_valid(battlefield):
		return
	layer = CanvasLayer.new()
	layer.layer = 8
	add_child(layer)
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -178
	panel.offset_right = -14
	panel.offset_top = 112
	panel.offset_bottom = 352
	layer.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	_add_button(col, "⟲ تدوير يسار", -1)
	_add_button(col, "⟳ تدوير يمين", 1)
	_add_button(col, "＋ تقريب", 2)
	_add_button(col, "－ إبعاد", 3)
	var note := Label.new()
	note.text = "اسحب لتحريك\nالمشهد"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(note)

func _add_button(parent: VBoxContainer, caption: String, action: int) -> void:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size = Vector2(150, 48)
	button.add_theme_font_size_override("font_size", 17)
	button.pressed.connect(_perform.bind(action))
	parent.add_child(button)

func _perform(action: int) -> void:
	if not is_instance_valid(battlefield):
		return
	match action:
		-1:
			battlefield.orbit -= 0.22
		1:
			battlefield.orbit += 0.22
		2:
			battlefield.distance = maxf(18.0, battlefield.distance - 4.0)
		3:
			battlefield.distance = minf(85.0, battlefield.distance + 4.0)
	battlefield._update_camera()
