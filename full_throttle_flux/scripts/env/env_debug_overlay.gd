extends CanvasLayer
class_name EnvDebugOverlay
## Debug readout for the environment FX foundation (v35). Debug builds only;
## EnvironmentState adds it.
##
##   F3         show / hide (hidden by default)
##   F4         next weather, blended as it would be mid-race
##   Shift+F4   next weather, instantly
##   Ctrl+F4    previous weather, instantly
##
## Shows the global weather / surface values and the probe of the ship the
## camera is following (so it follows the AI spectator too), and draws the
## probe in the world: ground point (green), wall rays (orange = left,
## cyan = right), last wall hit (red cross).

const UPDATE_INTERVAL := 0.1

var env: EnvironmentState
var _label: Label
var _panel: PanelContainer
var _lines: MeshInstance3D
var _mesh: ImmediateMesh
var _timer: float = 0.0


func _ready() -> void:
	layer = 90
	env = get_parent() as EnvironmentState
	_build_ui()
	_build_lines()
	_set_shown(false)


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -440.0
	_panel.offset_right = -20.0
	_panel.offset_top = 20.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	sb.set_content_margin_all(10.0)
	sb.set_corner_radius_all(6)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_panel.add_child(_label)


func _build_lines() -> void:
	_mesh = ImmediateMesh.new()
	_lines = MeshInstance3D.new()
	_lines.mesh = _mesh
	_lines.top_level = true
	_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.render_priority = 10
	_lines.material_override = mat
	add_child(_lines)


func _set_shown(v: bool) -> void:
	visible = v
	_panel.visible = v
	_lines.visible = v
	if not v:
		_mesh.clear_surfaces()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.physical_keycode:
		KEY_F3:
			_set_shown(not visible)
			get_viewport().set_input_as_handled()
		KEY_F4:
			if not visible or env == null:
				return
			if k.ctrl_pressed:
				env.cycle_weather(-1, true)
			else:
				env.cycle_weather(1, k.shift_pressed)
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible or env == null:
		return
	var probe := _camera_probe()
	_draw_probe(probe)
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = UPDATE_INTERVAL
	_label.text = _text(probe)


func _camera_probe() -> ShipEnvProbe:
	var cam := get_viewport().get_camera_3d()
	if cam == null or not ("ship" in cam):
		return null
	return ShipEnvProbe.of(cam.get("ship") as Node)


func _text(p: ShipEnvProbe) -> String:
	var w := env.weather
	var wind_deg := fposmod(rad_to_deg(atan2(env.wind_direction.x, -env.wind_direction.y)), 360.0)
	var s := "ENVIRONMENT   [F4 next  Shift+F4 instant  Ctrl+F4 back]\n"
	s += "weather   %s  (intensity %.2f)\n" % [w.display_name if w else "-", w.intensity if w else 0.0]
	s += "global    wet %.2f  frost %.2f  dust %.2f  precip %.2f\n" % [
		env.wetness, env.frost, env.dust, env.precipitation]
	s += "wind      %3.0f deg  %.1f m/s\n" % [wind_deg, env.wind_speed]
	s += "track     %d zones  spline %.0f m  sky %s\n" % [
		env.zones.size(), env.spline_length, "yes" if env.sky else "no"]
	var wfx := WeatherFx.of(env)
	var we := env.world_env
	s += "sky/road  line glow %.2f  SSR %s  surfaces %d mats  zone mask %s  falling %.2f%s\n" % [
		env.line_glow, "on" if we and we.environment and we.environment.ssr_enabled else "off",
		env.surfaces.materials if env.surfaces else 0, "yes" if env.track_mask else "no",
		wfx.shown if wfx else 0.0, "  (cut: covered)" if wfx and wfx.covered > 0.5 else ""]
	s += "humidity  %.2f   fx cpu %.2f ms (ribbons %.2f + driving/dust %.2f, all ships)\n" % [
		env.humidity, (TrailRibbon.frame_usec + ShipFx.frame_usec) / 1000.0,
		TrailRibbon.frame_usec / 1000.0, ShipFx.frame_usec / 1000.0]
	if p == null:
		return s + "\n(no probe on the camera target)"
	if not p.active:
		return s + "\nprobe idle"
	var sh := p.ship
	s += "\nSHIP      %s   %.0f u/s\n" % [sh.name, sh.get_speed()]
	s += "ground    %s\n" % (("%.2f m" % p.ground_distance) if p.has_ground else "airborne")
	s += "walls     L %s   R %s\n" % [_m(p.wall_left), _m(p.wall_right)]
	s += "spline    %s\n" % (("%.1f m" % p.spline_distance) if p.spline_distance >= 0.0 else "-")
	var z := p.zone
	s += "zone      w %.2f  dust x%.2f  covered %.2f  water %.2f  drift %.2f\n" % [
		z.weight, z.dust_scale, z.covered, z.standing_water, z.snow_drift]
	s += "local     wet %.2f  frost %.2f  dust %.2f  precip %.2f\n" % [
		p.wetness, p.frost, p.dust, p.precipitation]
	var fx := ShipFx.of(sh)
	if fx and fx.active:
		s += "fx        lod %s  thrust %d x %d pts  air L %d R %d pts\n" % [
			FxSettings.Lod.keys()[fx.lod], fx.thrust.size(),
			fx.thrust[0].point_count() if not fx.thrust.is_empty() else 0,
			fx.air_left.point_count() if fx.air_left else 0,
			fx.air_right.point_count() if fx.air_right else 0]
		if fx.dust:
			var rt := fx.dust.rates
			s += "dust      %s  ground %.0f  wall L %.0f R %.0f  brake L %.0f R %.0f /s\n" % [
				FxPools.Kind.keys()[fx.dust.kind], rt["ground"], rt["wall_l"], rt["wall_r"],
				rt["brake_l"], rt["brake_r"]]
			var pools := FxPools.for_env(env)
			s += "carriers  dust %d  spray %d  powder %d this frame (~30 puffs each)\n" % [
				pools.frame_count(0), pools.frame_count(1), pools.frame_count(2)]
	var since := p.seconds_since_hit()
	if since < 30.0:
		s += "wall hit  %.1f s ago  closing %.0f u/s%s\n" % [
			since, p.last_hit_closing, "   SCRAPING" if p.scraping else ""]
	var imp := env.get_node_or_null(FxImpacts.NODE_NAME) as FxImpacts
	if imp:
		s += "impacts   sparks %d  marks %d  flashes %d (race totals)\n" % [
			imp.sparks_total, imp.marks_total, imp.flashes_total]
	return s


static func _m(v: float) -> String:
	return "-" if v == INF else "%.1f m" % v


var _verts := PackedVector3Array()
var _colors := PackedColorArray()


func _draw_probe(p: ShipEnvProbe) -> void:
	_mesh.clear_surfaces()
	if p == null or not p.active:
		return
	_verts.clear()
	_colors.clear()
	var o := p.ship.global_position
	if p.has_ground:
		_line(o, p.ground_point, Color(0.3, 1.0, 0.4))
		_cross(p.ground_point, 0.6, Color(0.3, 1.0, 0.4))
	if p.wall_left != INF:
		_line(o, p.wall_left_point, Color(1.0, 0.6, 0.1))
	if p.wall_right != INF:
		_line(o, p.wall_right_point, Color(0.2, 0.9, 1.0))
	if p.seconds_since_hit() < 3.0:
		_cross(p.last_hit_point, 1.2, Color(1.0, 0.15, 0.15))
	if _verts.is_empty():
		return   # an empty ImmediateMesh surface is an error
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in _verts.size():
		_mesh.surface_set_color(_colors[i])
		_mesh.surface_add_vertex(_verts[i])
	_mesh.surface_end()


func _line(a: Vector3, b: Vector3, c: Color) -> void:
	_verts.append(a)
	_colors.append(c)
	_verts.append(b)
	_colors.append(c)


func _cross(p: Vector3, r: float, c: Color) -> void:
	_line(p - Vector3(r, 0, 0), p + Vector3(r, 0, 0), c)
	_line(p - Vector3(0, r, 0), p + Vector3(0, r, 0), c)
	_line(p - Vector3(0, 0, r), p + Vector3(0, 0, r), c)
