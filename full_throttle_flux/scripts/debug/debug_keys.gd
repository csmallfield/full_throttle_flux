extends Node
## Debug hotkeys (autoload "DebugKeys"). Debug builds only.
##
## Every debug key goes through here, so there is one list (F1 shows it in
## game, DEBUG_KEYS.md on disk) and a clash is an error when it is bound
## instead of two features quietly firing on one press. Features keep their
## own logic and register a key:
##
##   DebugKeys.bind(KEY_F7, "Anti-aliasing", _cycle_aa, func(): return AA_NAMES[aa])
##   DebugKeys.bind(KEY_F4, "Weather back", _back, Callable(), self, DebugKeys.CTRL)
##
## `value` (optional) is shown in the F1 list and as a toast after each press.
## `owner` (optional) unbinds the key when that node leaves the tree, for
## per-race features. Keys match by physical position, so keyboard layouts
## don't move them. Keys that only mean something inside one feature (the
## spectator's letters while spectating) stay with that feature.

const SHIFT := 1
const CTRL := 2
const ALT := 4

const TOAST_SECONDS := 2.0
const HELP_REFRESH := 0.25

var _binds := {}   # "key:mods" -> {key, mods, label, action, value, owner}
var _active := false
var _font: SystemFont
var _toast: Label
var _toast_t := 0.0
var _help: PanelContainer
var _help_label: Label
var _help_t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_active = OS.is_debug_build()
	set_process_input(_active)
	if _active:
		_build_ui()
		bind(KEY_F1, "This list", _toggle_help)


func bind(key: Key, label: String, action: Callable, value := Callable(),
		owner: Node = null, mods := 0) -> void:
	if not _active:
		return
	var id := _id(key, mods)
	var old: Dictionary = _binds.get(id, {})
	# The same feature may rebind its own key; anyone else is a clash, unless
	# the old owner is on its way out (scene change), which gives way quietly.
	if not old.is_empty() and old.source != action.get_object() and _owner_alive(old):
		push_error("DebugKeys: %s is already '%s'; not binding '%s'" % [
			key_name(key, mods), old.label, label])
		return
	_binds[id] = {key = key, mods = mods, label = label, action = action,
		value = value, owner = owner, source = action.get_object()}
	if owner and not owner.tree_exiting.is_connected(_on_owner_exiting):
		owner.tree_exiting.connect(_on_owner_exiting.bind(owner))


func unbind(key: Key, mods := 0) -> void:
	_binds.erase(_id(key, mods))


## Short message at the top of the screen, also printed to the log.
func toast(text: String) -> void:
	print("DebugKeys: " + text)
	if _toast == null:
		return
	_toast.text = text
	_toast.visible = true
	_toast_t = TOAST_SECONDS


static func key_name(key: Key, mods := 0) -> String:
	var s := ""
	if mods & CTRL:
		s += "Ctrl+"
	if mods & ALT:
		s += "Alt+"
	if mods & SHIFT:
		s += "Shift+"
	return s + OS.get_keycode_string(key)


## _input rather than _unhandled_input so a focused Control (HUD, results
## screen, pause menu) can't swallow debug keys. Only bound keys are consumed.
func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
	var mods := (SHIFT if k.shift_pressed else 0) | (CTRL if k.ctrl_pressed else 0) \
		| (ALT if k.alt_pressed else 0)
	var b: Dictionary = _binds.get(_id(code, mods), {})
	if b.is_empty():
		return
	get_viewport().set_input_as_handled()
	b.action.call()
	if b.value.is_valid():
		toast("%s: %s" % [b.label, str(b.value.call())])
	if _help.visible:
		_refresh_help()


func _process(delta: float) -> void:
	if _toast and _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t * 2.0, 0.0, 1.0)
		if _toast_t <= 0.0:
			_toast.visible = false
	if _help and _help.visible:
		_help_t -= delta
		if _help_t <= 0.0:
			_refresh_help()


func _toggle_help() -> void:
	_help.visible = not _help.visible
	if _help.visible:
		_refresh_help()


func _refresh_help() -> void:
	_help_t = HELP_REFRESH
	var rows := _binds.values()
	rows.sort_custom(func(a, b):
		return a.key < b.key if a.key != b.key else a.mods < b.mods)
	var lines: Array[String] = ["DEBUG KEYS   (F1 closes)"]
	for b in rows:
		var line := "%-10s %-24s" % [key_name(b.key, b.mods), b.label]
		if b.value.is_valid():
			line += " " + str(b.value.call())
		lines.append(line.strip_edges(false, true))
	_help_label.text = "\n".join(lines)


func _id(key: int, mods: int) -> String:
	return "%d:%d" % [key, mods]


func _owner_alive(b: Dictionary) -> bool:
	var o: Node = b.owner
	return o == null or (is_instance_valid(o) and o.is_inside_tree() and not o.is_queued_for_deletion())


func _on_owner_exiting(owner: Node) -> void:
	for id in _binds.keys():
		if _binds[id].owner == owner:
			_binds.erase(id)


func _build_ui() -> void:
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Consolas", "DejaVu Sans Mono", "Courier New", "monospace"])
	var layer := CanvasLayer.new()
	layer.layer = 110
	add_child(layer)

	_toast = Label.new()
	_toast.anchor_right = 1.0
	_toast.offset_top = 24.0
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 22)
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.visible = false
	layer.add_child(_toast)

	_help = PanelContainer.new()
	_help.anchor_left = 0.5
	_help.anchor_right = 0.5
	_help.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_help.offset_top = 70.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.75)
	sb.set_content_margin_all(14.0)
	sb.set_corner_radius_all(6)
	_help.add_theme_stylebox_override("panel", sb)
	_help.visible = false
	layer.add_child(_help)
	_help_label = Label.new()
	_help_label.add_theme_font_override("font", _font)
	_help_label.add_theme_font_size_override("font_size", 16)
	_help.add_child(_help_label)
