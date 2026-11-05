extends Control
## Pocket Pepakura v5 — paper-first, with separate 3D and optional tablet split view.
const PageCanvasScript = preload("res://scripts/page_canvas.gd")
const PdoReaderScript = preload("res://scripts/pdo_reader.gd")
enum ViewMode { PAPER, MODEL, SPLIT }

var view_mode: ViewMode = ViewMode.PAPER
var canvas: Control
var status_label: Label
var page_label: Label
var selection_label: Label
var texture_label: Label
var paper_panel: VBoxContainer
var model_panel: VBoxContainer
var workspace: HBoxContainer
var preview: SubViewportContainer
var preview_view: SubViewport
var model_root: Node3D
var camera: Camera3D
var picker: FileDialog
var paper_button: Button
var model_button: Button
var split_button: Button
var selection_button: Button
var pages: Array = []
var active_page := 0
var part_meshes: Dictionary = {}
var selected_part := -1
var camera_distance := 5.0
var fit_half_width := 1.6
var fit_half_height := 1.6
var dragging_mouse := false
var touch_points: Dictionary = {}
var last_pinch_distance := -1.0

func _ready() -> void:
    _build_ui()
    resized.connect(_refresh_layout)
    _load_demo()
    call_deferred("_refresh_layout")

func _make_button(parent: Node, caption: String, callback: Callable) -> Button:
    var b := Button.new()
    b.text = caption
    b.custom_minimum_size = Vector2(0, 48)
    b.pressed.connect(callback)
    parent.add_child(b)
    return b

func _build_ui() -> void:
    var root := VBoxContainer.new()
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.add_theme_constant_override("separation", 5)
    add_child(root)

    # Two short rows fit phones without squashing the drawing area.
    var header := HBoxContainer.new()
    header.add_theme_constant_override("separation", 8)
    root.add_child(header)
    var brand := Label.new()
    brand.text = "POCKET PEPAKURA"
    brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    brand.add_theme_font_size_override("font_size", 18)
    header.add_child(brand)
    _make_button(header, "Open PDO", _open_file)
    _make_button(header, "Demo", _load_demo)

    var modes := HBoxContainer.new()
    modes.add_theme_constant_override("separation", 5)
    root.add_child(modes)
    paper_button = _make_button(modes, "Paper", func() -> void: _set_mode(ViewMode.PAPER))
    model_button = _make_button(modes, "3D Model", func() -> void: _set_mode(ViewMode.MODEL))
    split_button = _make_button(modes, "Split view", func() -> void: _set_mode(ViewMode.SPLIT))
    for button in [paper_button, model_button, split_button]:
        button.toggle_mode = true
        button.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    status_label = Label.new()
    status_label.text = "Ready"
    status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    status_label.add_theme_font_size_override("font_size", 13)
    root.add_child(status_label)

    workspace = HBoxContainer.new()
    workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
    workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    workspace.add_theme_constant_override("separation", 6)
    root.add_child(workspace)

    paper_panel = VBoxContainer.new()
    paper_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
    paper_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    workspace.add_child(paper_panel)
    var nav := HBoxContainer.new()
    paper_panel.add_child(nav)
    _make_button(nav, "‹", _previous)
    page_label = Label.new()
    page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    nav.add_child(page_label)
    _make_button(nav, "›", _next)
    _make_button(nav, "Fit paper", _reset_view)

    canvas = PageCanvasScript.new()
    canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
    canvas.custom_minimum_size = Vector2(0, 210)
    canvas.selection_changed.connect(_on_selection)
    paper_panel.add_child(canvas)

    model_panel = VBoxContainer.new()
    model_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    model_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
    workspace.add_child(model_panel)
    var model_bar := HBoxContainer.new()
    model_panel.add_child(model_bar)
    var orbit_help := Label.new()
    orbit_help.text = "Drag: rotate  •  Pinch: zoom"
    orbit_help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    orbit_help.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    orbit_help.add_theme_font_size_override("font_size", 12)
    model_bar.add_child(orbit_help)
    _make_button(model_bar, "−", func() -> void: _change_zoom(1.18))
    _make_button(model_bar, "+", func() -> void: _change_zoom(0.85))
    _make_button(model_bar, "Fit 3D", _reset_3d)

    preview = SubViewportContainer.new()
    preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
    preview.custom_minimum_size = Vector2(0, 210)
    preview.stretch = true
    model_panel.add_child(preview)
    preview_view = SubViewport.new()
    preview_view.size = Vector2i(768, 768)
    preview_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    preview.add_child(preview_view)
    var world := Node3D.new()
    preview_view.add_child(world)
    model_root = Node3D.new()
    world.add_child(model_root)
    camera = Camera3D.new()
    camera.fov = 55.0
    camera.current = true
    camera.position = Vector3(0, 0, camera_distance)
    world.add_child(camera)
    var light := DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-30, -35, 0)
    light.light_energy = 1.25
    world.add_child(light)
    var environment := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color("1f2935")
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color.WHITE
    env.ambient_light_energy = 1.0
    environment.environment = env
    world.add_child(environment)
    preview.gui_input.connect(_preview_input)
    preview.resized.connect(_fit_camera)

    var footer := HBoxContainer.new()
    footer.add_theme_constant_override("separation", 6)
    root.add_child(footer)
    selection_label = Label.new()
    selection_label.text = "Tap a paper piece to locate it on the 3D model"
    selection_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    selection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    selection_label.add_theme_font_size_override("font_size", 13)
    footer.add_child(selection_label)
    selection_button = _make_button(footer, "Locate in 3D", func() -> void: _set_mode(ViewMode.MODEL))
    selection_button.disabled = true
    texture_label = Label.new()
    texture_label.text = "Textures: —"
    texture_label.add_theme_font_size_override("font_size", 12)
    root.add_child(texture_label)

    picker = FileDialog.new()
    picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
    picker.access = FileDialog.ACCESS_FILESYSTEM
    picker.use_native_dialog = true
    picker.add_filter("*.pdo,*.json", "PDO / paper JSON", "application/octet-stream,application/json")
    picker.file_selected.connect(_file_chosen)
    add_child(picker)

func _refresh_layout() -> void:
    if split_button == null:
        return
    var can_split: bool = size.x >= 1050.0 and size.x > size.y
    split_button.visible = can_split
    if view_mode == ViewMode.SPLIT and not can_split:
        view_mode = ViewMode.PAPER
    paper_panel.visible = view_mode != ViewMode.MODEL
    model_panel.visible = view_mode != ViewMode.PAPER
    paper_button.button_pressed = view_mode == ViewMode.PAPER
    model_button.button_pressed = view_mode == ViewMode.MODEL
    split_button.button_pressed = view_mode == ViewMode.SPLIT
    call_deferred("_fit_camera")

func _set_mode(mode: ViewMode) -> void:
    view_mode = mode
    _refresh_layout()

func _open_file() -> void:
    picker.popup_centered_ratio(0.9)

func _file_chosen(path: String) -> void:
    var ext := path.get_extension().to_lower()
    if ext == "pdo":
        _load_pdo(path)
    elif ext == "json":
        _load_json(path)
    else:
        # Android SAF sometimes gives a content URI rather than a normal filename.
        var f := FileAccess.open(path, FileAccess.READ)
        if f == null:
            _status("Could not open that file.")
            return
        var header := f.get_buffer(10).get_string_from_ascii()
        f.close()
        if header == "version 3\n":
            _load_pdo(path)
        else:
            _load_json(path)

func _load_json(path: String) -> void:
    var f := FileAccess.open(path, FileAccess.READ)
    if f == null:
        _status("Could not read page JSON.")
        return
    var parsed: Variant = JSON.parse_string(f.get_as_text())
    f.close()
    if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("pages")) != TYPE_ARRAY:
        _status("JSON needs a 'pages' array.")
        return
    var new_pages: Array = parsed["pages"]
    if new_pages.is_empty():
        _status("The JSON has no pages.")
        return
    pages = new_pages
    active_page = 0
    canvas.set_materials([])
    canvas.set_pages(pages)
    _clear_model()
    _update_nav()
    _set_mode(ViewMode.PAPER)
    texture_label.text = "Textures: demo pages only"
    _status("Demo pages — no PDO model loaded.")

func _load_demo() -> void:
    _load_json("res://samples/demo_pages.json")

func _load_pdo(path: String) -> void:
    var reader = PdoReaderScript.new()
    var result: Dictionary = reader.read_geometry(path)
    if result.has("error"):
        _status("PDO read error: " + str(result["error"]))
        return
    var mats: Array = result.get("materials", [])
    pages = result.get("pages", [])
    active_page = 0
    canvas.set_materials(mats)
    canvas.set_pages(pages)
    _update_nav()
    _clear_model()
    var face_count := _build_geometry(result.get("geometry", []), mats)
    var tex_ok: int = int(result.get("textures_ok", 0))
    var tex_bad: int = int(result.get("textures_failed", 0))
    texture_label.text = "Embedded textures: %d decoded, %d failed | 3D faces: %d" % [tex_ok, tex_bad, face_count]
    _set_mode(ViewMode.PAPER)
    _reset_3d()
    if pages.is_empty():
        _status("PDO has 3D geometry but no unfolded paper pages.")
    elif tex_ok == 0 and tex_bad > 0:
        _status("Texture decoding failed. See Debugger; the paper geometry still loaded.")
    else:
        _status("PDO format %s • %d parts • %d occupied sheets • original paper positions" % [str(result.get("format", 0)), int(result.get("parts", 0)), pages.size()])

func _clear_model() -> void:
    for child in model_root.get_children():
        child.queue_free()
    model_root.rotation = Vector3.ZERO
    part_meshes.clear()
    selected_part = -1
    selection_button.disabled = true
    selection_label.text = "Tap a paper piece to locate it on the 3D model"

func _build_geometry(geometries: Array, materials: Array) -> int:
    var groups: Dictionary = {}
    var bounds_points := PackedVector3Array()
    var face_count := 0
    for geometry in geometries:
        var verts: Array = geometry.get("vertices", [])
        for face in geometry.get("faces", []):
            var ids: PackedInt32Array = face.get("indices", PackedInt32Array())
            var uv: Array = face.get("uv", [])
            if ids.size() < 3:
                continue
            var valid := true
            for idx in ids:
                if idx < 0 or idx >= verts.size():
                    valid = false
                    break
            if not valid:
                continue
            var part_id: int = int(face.get("part", 0))
            var material_id: int = int(face.get("material", 0))
            var key := str(part_id) + ":" + str(material_id)
            if not groups.has(key):
                groups[key] = {"part": part_id, "material": material_id, "v": PackedVector3Array(), "uv": PackedVector2Array()}
            var group: Dictionary = groups[key]
            var triangles: PackedVector3Array = group["v"]
            var coords: PackedVector2Array = group["uv"]
            # A triangulated fan preserves every PDO face's original UV coordinates.
            for k in range(1, ids.size() - 1):
                for j in [0, k, k + 1]:
                    triangles.append(verts[ids[j]])
                    if j < uv.size():
                        coords.append(Vector2(float(uv[j][0]), float(uv[j][1])))
                    else:
                        coords.append(Vector2.ZERO)
                    bounds_points.append(verts[ids[j]])
            group["v"] = triangles
            group["uv"] = coords
            groups[key] = group
            face_count += 1
    if bounds_points.is_empty():
        return 0
    var bbox := AABB(bounds_points[0], Vector3.ZERO)
    for pos in bounds_points:
        bbox = bbox.expand(pos)
    var max_extent := maxf(maxf(bbox.size.x, bbox.size.y), bbox.size.z)
    var factor := 3.4 / maxf(max_extent, 0.0001)
    var center := bbox.position + bbox.size * 0.5
    fit_half_width = bbox.size.x * factor * 0.5
    fit_half_height = bbox.size.y * factor * 0.5
    for key in groups.keys():
        var group: Dictionary = groups[key]
        var st := SurfaceTool.new()
        st.begin(Mesh.PRIMITIVE_TRIANGLES)
        var vertices: PackedVector3Array = group["v"]
        var uv_list: PackedVector2Array = group["uv"]
        for i in vertices.size():
            st.set_uv(uv_list[i])
            st.add_vertex((vertices[i] - center) * factor)
        st.generate_normals()
        var instance := MeshInstance3D.new()
        instance.mesh = st.commit()
        var mat := StandardMaterial3D.new()
        mat.albedo_color = Color("d9dcdf")
        mat.cull_mode = BaseMaterial3D.CULL_DISABLED
        mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
        var material_id: int = int(group["material"])
        if material_id >= 0 and material_id < materials.size():
            var source: Dictionary = materials[material_id]
            var tex: Texture2D = source.get("texture")
            if tex != null:
                mat.albedo_texture = tex
                mat.albedo_color = Color.WHITE
                # PDO UVs may extend beyond 0..1. Preserve their repeating behavior.
                mat.set_flag(BaseMaterial3D.FLAG_USE_TEXTURE_REPEAT, true)
                mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
            else:
                mat.albedo_color = source.get("color", Color("d9dcdf"))
        instance.material_override = mat
        model_root.add_child(instance)
        var part_id: int = int(group["part"])
        if not part_meshes.has(part_id):
            part_meshes[part_id] = []
        part_meshes[part_id].append(instance)
    return face_count

func _highlight_model(part_id: int) -> void:
    for key in part_meshes.keys():
        for node in part_meshes[key]:
            if not is_instance_valid(node):
                continue
            if int(key) == part_id:
                # A transparent overlay highlights the part WITHOUT hiding its texture.
                var highlight := StandardMaterial3D.new()
                highlight.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
                highlight.albedo_color = Color(0.08, 0.7, 1.0, 0.3)
                highlight.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
                highlight.cull_mode = BaseMaterial3D.CULL_DISABLED
                node.material_overlay = highlight
            else:
                node.material_overlay = null

func _fit_camera() -> void:
    if camera == null or preview == null:
        return
    var aspect := maxf(0.3, preview.size.x / maxf(preview.size.y, 1.0))
    var half_tan := tan(deg_to_rad(camera.fov * 0.5))
    # Fit horizontally AND vertically, even in portrait orientation.
    camera_distance = clampf(maxf(fit_half_height / half_tan, fit_half_width / (half_tan * aspect)) * 1.35 + 0.8, 2.5, 25.0)
    camera.position = Vector3(0.0, 0.0, camera_distance)

func _reset_3d() -> void:
    model_root.rotation = Vector3.ZERO
    _fit_camera()

func _change_zoom(multiplier: float) -> void:
    camera_distance = clampf(camera_distance * multiplier, 1.8, 30.0)
    camera.position.z = camera_distance

func _preview_input(event: InputEvent) -> void:
    if event is InputEventScreenTouch:
        if event.pressed:
            touch_points[event.index] = event.position
        else:
            touch_points.erase(event.index)
        last_pinch_distance = -1.0
    elif event is InputEventScreenDrag:
        touch_points[event.index] = event.position
        if touch_points.size() == 1:
            model_root.rotate_y(event.relative.x * 0.008)
            model_root.rotate_x(event.relative.y * 0.008)
        elif touch_points.size() == 2:
            var pts: Array = touch_points.values()
            var distance: float = (pts[0] as Vector2).distance_to(pts[1] as Vector2)
            if last_pinch_distance > 0.0 and distance > 1.0:
                _change_zoom(last_pinch_distance / distance)
            last_pinch_distance = distance
    elif event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT:
            dragging_mouse = event.pressed
        elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
            _change_zoom(0.9)
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
            _change_zoom(1.1)
    elif event is InputEventMouseMotion and dragging_mouse and touch_points.is_empty():
        model_root.rotate_y(event.relative.x * 0.008)
        model_root.rotate_x(event.relative.y * 0.008)

func _previous() -> void:
    if pages.is_empty():
        return
    active_page = maxi(0, active_page - 1)
    canvas.set_page(active_page)
    _update_nav()

func _next() -> void:
    if pages.is_empty():
        return
    active_page = mini(pages.size() - 1, active_page + 1)
    canvas.set_page(active_page)
    _update_nav()

func _reset_view() -> void:
    canvas.reset_view()

func _on_selection(piece_id: String) -> void:
    selection_label.text = "Selected: %s  •  Open 3D to locate it" % piece_id
    if piece_id.begins_with("P") and piece_id.substr(1).is_valid_int():
        selected_part = int(piece_id.substr(1)) - 1
        _highlight_model(selected_part)
        selection_button.disabled = not part_meshes.has(selected_part)
    else:
        selection_button.disabled = true

func _update_nav() -> void:
    page_label.text = "Page %d of %d" % [(active_page + 1 if not pages.is_empty() else 0), pages.size()]

func _status(message: String) -> void:
    status_label.text = message
