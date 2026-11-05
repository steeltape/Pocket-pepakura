extends Control
signal selection_changed(piece_id: String)
var pages: Array = []
var textures: Array = []
var page_index := 0
var zoom := 1.0
var offset := Vector2.ZERO
var selected_id := ""
var touches: Dictionary = {}
var last_pinch := -1.0
const PAPER := Color("fdfcf8")
const CUT := Color("252d39")
const FOLD := Color("5382b1")

func _ready() -> void:
    # Some original PDO UVs lie outside 0..1; let the image repeat as specified.
    texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
    texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

func set_materials(value: Array) -> void:
    textures = value
    queue_redraw()

func set_pages(value: Array) -> void:
    pages = value
    page_index = 0
    selected_id = ""
    reset_view()

func set_page(index: int) -> void:
    page_index = clampi(index, 0, maxi(0, pages.size() - 1))
    reset_view()

func highlight(id: String) -> void:
    selected_id = id
    queue_redraw()

func reset_view() -> void:
    zoom = 1.0
    offset = Vector2.ZERO
    queue_redraw()

func _bounds() -> Vector2:
    if pages.is_empty(): return Vector2(210,297)
    return Vector2(float(pages[page_index].get("width",210)), float(pages[page_index].get("height",297)))

func _scale() -> float:
    var dim := _bounds()
    return maxf(0.001,minf((size.x-36)/dim.x,(size.y-36)/dim.y)) * zoom

func _to_screen(v: Vector2) -> Vector2:
    return (v - _bounds()*0.5)*_scale() + size*0.5 + offset

func _to_page(v: Vector2) -> Vector2:
    return (v-size*0.5-offset)/_scale()+_bounds()*0.5

func _v(a: Variant) -> Vector2:
    return Vector2(float(a[0]),float(a[1]))

# Clip textured polygons against the printable sheet, keeping UVs in sync.
# This prevents textures and shapes drawing outside the page border.
func _clip(poly: Array, axis: int, bound: float, inside_less: bool) -> Array:
    if poly.is_empty(): return []
    var output: Array = []
    var previous: Dictionary = poly.back()
    var prev_coord: float = previous["p"].x if axis == 0 else previous["p"].y
    var prev_inside: bool = prev_coord <= bound if inside_less else prev_coord >= bound
    for current in poly:
        var coord: float = current["p"].x if axis == 0 else current["p"].y
        var in_current: bool = coord <= bound if inside_less else coord >= bound
        if in_current != prev_inside:
            var t: float = (bound-prev_coord)/(coord-prev_coord)
            output.append({"p":previous["p"].lerp(current["p"],t),"uv":previous["uv"].lerp(current["uv"],t)})
        if in_current: output.append(current)
        previous = current
        prev_coord = coord
        prev_inside = in_current
    return output

func _clip_page(poly: Array) -> Array:
    var dim := _bounds()
    var out := _clip(poly,0,0.0,false)
    out = _clip(out,0,dim.x,true)
    out = _clip(out,1,0.0,false)
    out = _clip(out,1,dim.y,true)
    return out

func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO,size),Color("dbe0e6"))
    if pages.is_empty(): return
    var top_left := _to_screen(Vector2.ZERO)
    var paper_size := _bounds()*_scale()
    draw_rect(Rect2(top_left+Vector2(4,5),paper_size),Color(0,0,0,0.13))
    draw_rect(Rect2(top_left,paper_size),PAPER)
    var page: Dictionary = pages[page_index]
    for item in page.get("pieces",[]):
        var piece: Dictionary = item
        var selected: bool = str(piece.get("id","")) == selected_id
        if piece.has("faces"):
            for face in piece.get("faces",[]):
                var pts_data: Array = face.get("points",[]) if typeof(face) == TYPE_DICTIONARY else face
                var uv_data: Array = face.get("uv",[]) if typeof(face) == TYPE_DICTIONARY else []
                var material_id: int = int(face.get("material",-1)) if typeof(face) == TYPE_DICTIONARY else -1
                if pts_data.size() < 3: continue
                var vertices: Array = []
                for j in pts_data.size():
                    var uv := _v(uv_data[j]) if j < uv_data.size() else Vector2.ZERO
                    vertices.append({"p":_v(pts_data[j]),"uv":uv})
                # Fan triangulation first, then clip each triangle to page.
                for j in range(1,vertices.size()-1):
                    var clipped := _clip_page([vertices[0],vertices[j],vertices[j+1]])
                    if clipped.size() < 3: continue
                    var points := PackedVector2Array()
                    var uvs := PackedVector2Array()
                    for vertex in clipped:
                        points.append(_to_screen(vertex["p"]))
                        uvs.append(vertex["uv"])
                    var tex: Texture2D = null
                    if material_id >= 0 and material_id < textures.size():
                        tex = textures[material_id].get("texture")
                    if tex != null:
                        draw_polygon(points, PackedColorArray([Color.WHITE]), uvs, tex)
                    else:
                        var paper_color := Color("f5f1e7")
                        if material_id >= 0 and material_id < textures.size():
                            paper_color = textures[material_id].get("paper_color", paper_color)
                        draw_colored_polygon(points, paper_color)
                    # Translucent selection preserves the original printed artwork.
                    if selected:
                        draw_colored_polygon(points, Color(0.08, 0.62, 1.0, 0.18))
                # Borders come from PDO line records, not every triangle edge.
            for line in piece.get("lines",[]):
                var seg := _clip_segment(_v(line["a"]),_v(line["b"]))
                if seg.size() == 2:
                    var a := _to_screen(seg[0])
                    var b := _to_screen(seg[1])
                    if int(line.get("kind",0)) == 0: draw_line(a,b,CUT,1.3)
                    else: _dashed(a,b)
        else:
            var vertices := PackedVector2Array()
            for pt in piece.get("points",[]):vertices.append(_to_screen(_v(pt)))
            if vertices.size() >= 3:
                draw_colored_polygon(vertices, Color("f7f2e6"))
                if selected:
                    draw_colored_polygon(vertices, Color(0.08, 0.62, 1.0, 0.18))
                for j in vertices.size():draw_line(vertices[j],vertices[(j+1)%vertices.size()],CUT,1.3)
                for line in piece.get("folds",[]):_dashed(_to_screen(_v(line[0])),_to_screen(_v(line[1])))
    draw_rect(Rect2(top_left,paper_size),Color("88929c"),false,1.5)

# Liang-Barsky segment clipping for cut/fold lines.
func _clip_segment(a: Vector2,b: Vector2) -> Array:
    var dim := _bounds()
    var d := b-a
    var t0 := 0.0
    var t1 := 1.0
    var pp := [-d.x,d.x,-d.y,d.y]
    var qq := [a.x,dim.x-a.x,a.y,dim.y-a.y]
    for i in 4:
        var p: float = pp[i]
        var q: float = qq[i]
        if absf(p) < 0.000001:
            if q < 0.0:return []
        else:
            var t := q/p
            if p < 0.0:t0=maxf(t0,t)
            else:t1=minf(t1,t)
            if t0 > t1:return []
    return [a+d*t0,a+d*t1]

func _dashed(a: Vector2,b: Vector2) -> void:
    var length := a.distance_to(b)
    if length < 1.0:return
    var direction := (b-a)/length
    var t := 0.0
    while t < length:
        draw_line(a+direction*t,a+direction*minf(t+6.0,length),FOLD,1.3)
        t+=10.0

func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:zoom=clampf(zoom*1.1,0.25,10.0);queue_redraw()
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:zoom=clampf(zoom/1.1,0.25,10.0);queue_redraw()
        elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:_pick(event.position)
    elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and touches.is_empty():
        offset+=event.relative;queue_redraw()
    elif event is InputEventScreenTouch:
        if event.pressed:
            touches[event.index]=event.position
            if touches.size()==1:_pick(event.position)
        else:
            touches.erase(event.index);last_pinch=-1
    elif event is InputEventScreenDrag:
        touches[event.index]=event.position
        if touches.size()==1:offset+=event.relative
        elif touches.size()==2:
            var positions := touches.values()
            var distance: float = (positions[0] as Vector2).distance_to(positions[1] as Vector2)
            if last_pinch>0:zoom=clampf(zoom*distance/last_pinch,0.25,10.0)
            last_pinch=distance
        queue_redraw()
    accept_event()

func _pick(screen: Vector2) -> void:
    if pages.is_empty():return
    var p := _to_page(screen)
    var pieces: Array = pages[page_index].get("pieces",[])
    for i in range(pieces.size()-1,-1,-1):
        var piece: Dictionary = pieces[i]
        var faces: Array = piece.get("faces",[]) if piece.has("faces") else [piece.get("points",[])]
        for face in faces:
            var raw_points: Array = face.get("points",[]) if typeof(face)==TYPE_DICTIONARY else face
            var poly := PackedVector2Array()
            for point in raw_points:poly.append(_v(point))
            if poly.size()>=3 and Geometry2D.is_point_in_polygon(p,poly):
                selected_id=str(piece.get("id",""))
                selection_changed.emit(selected_id)
                queue_redraw()
                return
