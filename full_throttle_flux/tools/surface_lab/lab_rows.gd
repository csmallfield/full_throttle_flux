extends VBoxContainer
## Surface Lab: a column of labelled value rows, built from property-list style
## dictionaries, so new shader uniforms and rule fields appear by themselves.
## Each row reads and writes through callables and refreshes from them, so undo
## and compare only need refresh().
##
## add_row() takes {name, type, hint, hint_string} plus get / set callables and,
## optionally, badge (text beside the name), badge_warn, tooltip.

var rows: Array[Dictionary] = []
var filter_text := ""
var _group_box: VBoxContainer = self
var _updating := false


func clear_rows() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	rows.clear()
	_group_box = self


## Starts a collapsible section; following rows go in it.
func add_group(title: String, open := false) -> void:
	var head := Button.new()
	head.text = ("▾ " if open else "▸ ") + title
	head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.flat = true
	head.add_theme_font_size_override("font_size", 15)
	add_child(head)
	var box := VBoxContainer.new()
	box.visible = open
	add_child(box)
	head.pressed.connect(func():
		box.visible = not box.visible
		head.text = ("▾ " if box.visible else "▸ ") + title)
	_group_box = box


func add_row(spec: Dictionary) -> void:
	var row := {spec = spec, box = null, set_ui = Callable()}
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var head := HBoxContainer.new()
	var label := Label.new()
	label.text = String(spec.name).replace("_", " ")
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	label.tooltip_text = String(spec.get("tooltip", spec.name))
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	head.add_child(label)
	if spec.has("override"):
		head.add_child(_override_box(spec, row))
	if spec.has("badge"):
		var badge := Label.new()
		badge.text = spec.badge
		badge.add_theme_font_size_override("font_size", 11)
		badge.add_theme_color_override("font_color",
				Color(1.0, 0.72, 0.3) if spec.get("badge_warn", false) else Color(0.55, 0.85, 0.75))
		head.add_child(badge)
		row.badge = badge
	box.add_child(head)
	row.set_ui = _editor(spec, box, head)
	row.box = box
	_group_box.add_child(box)
	rows.append(row)
	_refresh_row(row)


## "This track" tick for a parameter a variation can override.
func _override_box(spec: Dictionary, row: Dictionary) -> CheckBox:
	var check := CheckBox.new()
	check.text = "track"
	check.tooltip_text = "On: this value belongs to the variation (this track only)."
	check.add_theme_font_size_override("font_size", 11)
	check.toggled.connect(func(on: bool):
		if not _updating:
			(spec.override as Callable).call(on)
			_refresh_row(row))
	row.check = check
	return check


## Builds the value control; returns a callable that shows a value in it.
func _editor(spec: Dictionary, box: VBoxContainer, head: HBoxContainer) -> Callable:
	var t: int = spec.type
	var hint: int = spec.get("hint", PROPERTY_HINT_NONE)
	var hs := String(spec.get("hint_string", ""))
	if t == TYPE_COLOR:
		var pick := ColorPickerButton.new()
		pick.custom_minimum_size = Vector2(64, 22)
		pick.edit_alpha = false
		head.add_child(pick)
		pick.color_changed.connect(func(c: Color): _write(spec, c))
		return func(v: Variant): pick.color = _to_color(v)
	if t == TYPE_BOOL:
		var check := CheckBox.new()
		head.add_child(check)
		check.toggled.connect(func(on: bool): _write(spec, on))
		return func(v: Variant): check.set_pressed_no_signal(bool(v))
	if hint == PROPERTY_HINT_ENUM or spec.has("choices"):
		return _enum_editor(spec, head, hs, t)
	if t == TYPE_STRING:
		var edit := LineEdit.new()
		edit.custom_minimum_size = Vector2(150, 0)
		head.add_child(edit)
		edit.text_changed.connect(func(s: String): _write(spec, s))
		return func(v: Variant):
			if edit.text != str(v):
				edit.text = str(v)
	if t == TYPE_VECTOR2 or t == TYPE_VECTOR3:
		return _vector_editor(spec, head, 2 if t == TYPE_VECTOR2 else 3)
	return _number_editor(spec, box, head, t, hint, hs)


func _enum_editor(spec: Dictionary, head: HBoxContainer, hs: String, t: int) -> Callable:
	var opt := OptionButton.new()
	var names: Array = spec.get("choices", Array(hs.split(",")))
	for n in names:
		opt.add_item(str(n).get_slice(":", 0))
	opt.fit_to_longest_item = false
	opt.clip_text = true
	opt.custom_minimum_size = Vector2(150, 0)
	head.add_child(opt)
	opt.item_selected.connect(func(i: int):
		_write(spec, i if t == TYPE_INT else names[i]))
	return func(v: Variant):
		opt.select(int(v) if t == TYPE_INT else names.find(v))


func _vector_editor(spec: Dictionary, head: HBoxContainer, n: int) -> Callable:
	var spins: Array[SpinBox] = []
	for i in n:
		var sp := SpinBox.new()
		sp.step = 0.01
		sp.allow_greater = true
		sp.allow_lesser = true
		sp.min_value = -1000.0
		sp.max_value = 1000.0
		sp.custom_minimum_size = Vector2(66, 0)
		sp.get_line_edit().add_theme_font_size_override("font_size", 12)
		head.add_child(sp)
		spins.append(sp)
		sp.value_changed.connect(func(_x: float):
			if _updating:
				return
			_write(spec, Vector2(spins[0].value, spins[1].value) if n == 2
					else Vector3(spins[0].value, spins[1].value, spins[2].value)))
	return func(v: Variant):
		var vec: Variant = v if v != null else (Vector2.ZERO if n == 2 else Vector3.ZERO)
		spins[0].value = vec.x
		spins[1].value = vec.y
		if n == 3:
			spins[2].value = vec.z


func _number_editor(spec: Dictionary, box: VBoxContainer, head: HBoxContainer, t: int, hint: int,
		hs: String) -> Callable:
	var lo := 0.0
	var hi := 1.0
	var step := 1.0 if t == TYPE_INT else 0.01
	var ranged := hint == PROPERTY_HINT_RANGE and hs != ""
	if ranged:
		var parts := hs.split(",")
		lo = float(parts[0])
		hi = float(parts[1])
		if parts.size() > 2 and parts[2].is_valid_float():
			step = float(parts[2])
		else:
			step = maxf((hi - lo) / 400.0, 0.001) if t != TYPE_INT else 1.0
	var spin := SpinBox.new()
	spin.step = step
	spin.custom_minimum_size = Vector2(84, 0)
	spin.get_line_edit().add_theme_font_size_override("font_size", 12)
	if ranged:
		spin.min_value = lo
		spin.max_value = hi
	else:
		spin.min_value = -100000.0
		spin.max_value = 100000.0
		spin.step = 1.0 if t == TYPE_INT else 0.05
	head.add_child(spin)
	var slider: HSlider = null
	if ranged:
		slider = HSlider.new()
		slider.min_value = lo
		slider.max_value = hi
		slider.step = step
		slider.focus_mode = Control.FOCUS_NONE
		box.add_child(slider)
		slider.value_changed.connect(func(x: float):
			if not _updating:
				spin.set_value_no_signal(x)
				_write(spec, int(x) if t == TYPE_INT else x))
	spin.value_changed.connect(func(x: float):
		if not _updating:
			if slider:
				slider.set_value_no_signal(x)
			_write(spec, int(x) if t == TYPE_INT else x))
	return func(v: Variant):
		var x := float(v) if v != null else 0.0
		spin.set_value_no_signal(x)
		spin.get_line_edit().text = str(snappedf(x, spin.step))
		if slider:
			slider.set_value_no_signal(x)


func _write(spec: Dictionary, v: Variant) -> void:
	if _updating:
		return
	(spec.set as Callable).call(v)


## Shows every row's current value.
func refresh() -> void:
	for r in rows:
		_refresh_row(r)


func _refresh_row(r: Dictionary) -> void:
	_updating = true
	var spec: Dictionary = r.spec
	r.set_ui.call(spec.get.call())
	if r.has("check"):
		(r.check as CheckBox).set_pressed_no_signal(bool((spec.is_override as Callable).call()))
	if r.has("badge") and spec.has("badge_fn"):
		var b: Array = (spec.badge_fn as Callable).call()
		(r.badge as Label).text = b[0]
		(r.badge as Label).add_theme_color_override("font_color",
				Color(1.0, 0.72, 0.3) if b[1] else Color(0.55, 0.85, 0.75))
	_updating = false


## Shows only rows whose name contains `text`, and opens their groups.
func set_filter(text: String) -> void:
	filter_text = text.to_lower().replace(" ", "_")
	for r in rows:
		var on: bool = filter_text == "" or String(r.spec.name).to_lower().contains(filter_text)
		(r.box as Control).visible = on
		var parent := (r.box as Control).get_parent() as Control
		if parent != self and filter_text != "" and on:
			parent.visible = true


static func _to_color(v: Variant) -> Color:
	if v is Color:
		return v
	if v is Vector3:
		return Color((v as Vector3).x, (v as Vector3).y, (v as Vector3).z)
	return Color.BLACK
