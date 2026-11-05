extends RefCounted
## Read-only PDO 4/5/6 parser based on the published pdo-tools structure.
## Original PDO layout, geometry, and embedded RGB textures. Edge numbers remain pending.
## Bounded input and count checks protect Android memory and reject malformed files.
const MAX_BYTES := 80 * 1024 * 1024
const MAX_OBJECTS := 300
const MAX_VERTICES := 300000
const MAX_FACES := 300000
const MAX_PARTS := 10000
const MAX_LINES := 300000
const MAX_STRING := 1024 * 1024
var stream: StreamPeerBuffer
var limit := 0
var failed := false
var reason := ""
var format_version := 0
var multi := false
var shift := 0
var objects: Array = []
var materials: Array = []
var texture_count := 0
var texture_failures := 0

func read_geometry(path: String) -> Dictionary:
    var f := FileAccess.open(path, FileAccess.READ)
    if f == null:
        return {"error": "Cannot read selected file."}
    var length := f.get_length()
    if length < 64 or length > MAX_BYTES:
        f.close()
        return {"error": "Invalid PDO size or file above 80 MB."}
    var bytes := f.get_buffer(length)
    f.close()
    stream = StreamPeerBuffer.new()
    stream.big_endian = false
    stream.data_array = bytes
    limit = bytes.size()
    failed = false
    reason = ""
    objects = []
    materials = []
    texture_count = 0
    texture_failures = 0
    if _take(10).get_string_from_ascii() != "version 3\n":
        return {"error": "This is not a recognized Pepakura PDO header."}
    format_version = _u32()
    if format_version < 4 or format_version > 6:
        return {"error": "Unsupported PDO binary format: " + str(format_version)}
    multi = _u32() == 1
    _u32() # application build marker
    var designer := ""
    if format_version > 4:
        designer = _string(0)
        shift = _u32()
    else:
        shift = 0
    _string(shift) # locale
    _string(shift) # code page
    _u32() # texture lock metadata
    var password_flag := 0
    if format_version == 6:
        _u8() # startup message flag
        password_flag = _u8()
    _string(shift) # key field (do not attempt to unlock)
    if format_version == 6:
        var block_count := _count(4096)
        _skip(block_count * 8)
    elif format_version == 5:
        _u8() # startup message flag
        password_flag = _u8()
    _skip(8 + 24) # model height and origin
    if failed:
        return _error()
    if password_flag != 0:
        return {"error": "This password-protected PDO variant isn't supported."}
    var count := _count(MAX_OBJECTS)
    var geometry: Array = []
    for oi in count:
        if failed: break
        var obj_name := _string(shift)
        _u8() # visible flag
        var nv := _count(MAX_VERTICES)
        var vertices: Array = []
        for vi in nv:
            vertices.append(Vector3(_f64(), _f64(), _f64()))
            if failed: break
        var nf := _count(MAX_FACES)
        var faces: Array = []
        var render_faces: Array = []
        for fi in nf:
            if failed: break
            var material_id := _u32() # material
            var part_index := _u32()
            _skip(32) # face plane
            var np := _count(100)
            var indices := PackedInt32Array()
            var coords: Array = []
            var vertex_ids: Array = []
            var uv_coords: Array = []
            for pi in np:
                var vertex_id := _u32()
                var x := _f64()
                var y := _f64()
                var u := _f64()
                var v := _f64()
                uv_coords.append([u, v])
                _u8() # flap flag
                _skip(48) # flap geometry and fold data
                indices.append(vertex_id)
                vertex_ids.append(vertex_id)
                coords.append([x, y])
            faces.append({"part": part_index, "ids": vertex_ids, "coords": coords, "uv": uv_coords, "material": material_id})
            if np >= 3:
                render_faces.append({"indices": indices, "part": part_index, "uv": uv_coords, "material": material_id})
        var ne := _count(MAX_LINES)
        _skip(ne * 22)
        objects.append({"name": obj_name, "faces": faces})
        geometry.append({"name": obj_name, "vertices": vertices, "faces": render_faces})
    if failed: return _error()
    # Decode compressed material textures and retain both 2D/3D colors.
    var material_count := _count(4096)
    for mi in material_count:
        if failed: break
        var mat_name := _string(shift)
        var colors: Array = []
        for ci in 16:
            colors.append(_f32())
        var paper_colors: Array = []
        for ci in 4:
            paper_colors.append(_f32())
        var textured := _u8()
        var tex: Texture2D = null
        if textured == 1:
            var tw := _u32()
            var th := _u32()
            var wrapped_size := _u32()
            if tw <= 0 or th <= 0 or tw > 4096 or th > 4096 or wrapped_size < 6 or wrapped_size > MAX_BYTES:
                _fail("Invalid texture dimensions or data length")
                break
            var blob := _take(wrapped_size)
            if not failed:
                tex = _decode_texture(blob, tw, th)
                if tex != null:
                    texture_count += 1
                else:
                    texture_failures += 1
        elif textured != 0:
            _fail("Invalid texture flag")
        # PDO stores ambient RGBA in 0..3 and *diffuse* RGBA in 4..7.
        # Earlier versions used ambient (usually 0.5 gray) for every face.
        materials.append({"name": mat_name, "texture": tex,
                          "color": Color(colors[4], colors[5], colors[6], 1.0),
                          "paper_color": Color(paper_colors[1], paper_colors[2], paper_colors[3], 1.0)})
    if failed: return _error()
    var has_unfold := _u8()
    if has_unfold == 0:
        return {"geometry": geometry, "materials": materials, "pages": [], "format": format_version, "designer": designer, "notice": "PDO has no unfolded layout.", "textures_ok": texture_count, "textures_failed": texture_failures}
    if has_unfold != 1:
        return {"error": "Unknown unfolding section."}
    _f64() # unfold scale
    _u8() # padding
    _skip(32) # layout bounds
    var part_count := _count(MAX_PARTS)
    var parts: Array = []
    for pi in part_count:
        if failed: break
        var obj_id := _u32()
        var left := _f64()
        var top := _f64()
        var width := _f64()
        var height := _f64()
        var part_name := "Part " + str(pi + 1)
        if format_version > 4:
            var value := _string(shift)
            if not value.is_empty(): part_name = value
        var nl := _count(MAX_LINES)
        var lines: Array = []
        for li in nl:
            var hidden := _u8()
            var kind := _u32()
            _u8() # other flag
            var face_id := _u32()
            var vertex_id := _u32()
            var linked := _u8()
            if linked == 1:
                _skip(8)
            elif linked != 0:
                _fail("Unknown line type")
            lines.append({"hidden": hidden, "kind": kind, "face": face_id, "vertex": vertex_id})
        parts.append({"object": obj_id, "name": part_name, "bbox": [left, top, width, height], "lines": lines})
    if failed: return _error()
    # Text and embedded images: parse sizes only, no rendering in this milestone.
    var text_count := _count(10000)
    for i in text_count:
        _skip(32 + 8 + 4 + 4)
        _string(shift)
        var line_count := _count(10000)
        for j in line_count:
            _string(shift)
    for block in 2:
        var image_count := _count(10000)
        for i in image_count:
            _skip(32 + 8)
            var data_size := _u32()
            if data_size < 6 or data_size > MAX_BYTES:
                _fail("Invalid embedded image size")
                break
            _skip(data_size)
    if failed: return _error()
    # PDO 6 introduces a variable-length unknown settings prefix.
    if format_version == 6 and part_count > 0:
        var unknown_count := _count(10000)
        for i in unknown_count:
            var words := _count(10000)
            _skip(words * 4)
    _skip(4 + 1 + 4 + 1 + 16) # display and line style flags
    var page_type := _u32()
    var pw := 210.0
    var ph := 297.0
    var dims := [[210.0,297.0],[297.0,420.0],[420.0,594.0],[594.0,841.0],[176.0,250.0],[250.0,353.0],[353.0,500.0],[500.0,707.0],[707.0,1000.0],[215.9,279.4],[215.9,355.6]]
    if page_type >= 0 and page_type < dims.size():
        pw = dims[page_type][0]
        ph = dims[page_type][1]
    elif page_type == 11:
        pw = _f64()
        ph = _f64()
    else:
        return {"error": "Unrecognized paper size."}
    var orientation := _u32()
    var margin_side := float(_u32())
    var margin_top := float(_u32())
    if orientation == 1:
        var temp := pw
        pw = ph
        ph = temp
    if failed or pw <= 0 or ph <= 0: return _error()
    var pages := _make_pages(parts, pw, ph, margin_side, margin_top)
    return {"geometry": geometry, "materials": materials, "pages": pages, "format": format_version, "designer": designer, "parts": parts.size(), "notice": "Original part placement (paper margins honored); edge labels not supported.", "textures_ok": texture_count, "textures_failed": texture_failures}

func _make_pages(parts: Array, pw: float, ph: float, side_margin: float, top_margin: float) -> Array:
    # PDO stores each face's unfolded XY relative to its OWN part bounding box.
    # The part bbox supplies its position in the ORIGINAL unfolded grid.
    # Crucially: grid cells are PRINTABLE areas, not full A4 sheet sizes.
    var pitch_x := pw - side_margin * 2.0
    var pitch_y := ph - top_margin * 2.0
    if pitch_x <= 0.0 or pitch_y <= 0.0:
        return []
    var by_page: Dictionary = {}
    for pi in parts.size():
        var part: Dictionary = parts[pi]
        var obj_id: int = int(part["object"])
        if obj_id < 0 or obj_id >= objects.size():
            continue
        var bbox: Array = part["bbox"]
        var left: float = float(bbox[0])
        var top: float = float(bbox[1])
        # Source file determines placement. NEVER split or rearrange a part.
        var col := maxi(0, int(floor((left + 0.00001) / pitch_x)))
        var row := maxi(0, int(floor((top + 0.00001) / pitch_y)))
        var key := str(row) + ":" + str(col)
        if not by_page.has(key):
            by_page[key] = []
        var placement := Vector2(left - col * pitch_x + side_margin,
                                 top - row * pitch_y + top_margin)
        var faces_out: Array = []
        var face_by_id: Dictionary = {}
        var obj_faces: Array = objects[obj_id]["faces"]
        for fi in obj_faces.size():
            var face: Dictionary = obj_faces[fi]
            if int(face["part"]) != pi:
                continue
            var coords: Array = face["coords"]
            var pts: Array = []
            for xy in coords:
                pts.append([float(xy[0]) + placement.x, float(xy[1]) + placement.y])
            if pts.size() >= 3:
                faces_out.append({"points": pts, "uv": face["uv"], "material": face["material"]})
                face_by_id[fi] = face
        if faces_out.is_empty():
            continue
        var lines_out: Array = []
        for line in part["lines"]:
            if int(line["hidden"]) != 0:
                continue
            var fi: int = int(line["face"])
            if not face_by_id.has(fi):
                continue
            var face: Dictionary = face_by_id[fi]
            var ids: Array = face["ids"]
            var idx := ids.find(int(line["vertex"]))
            if idx < 0 or ids.size() < 2:
                continue
            var a: Array = face["coords"][idx]
            var b: Array = face["coords"][(idx + 1) % ids.size()]
            lines_out.append({"a": [float(a[0]) + placement.x, float(a[1]) + placement.y],
                              "b": [float(b[0]) + placement.x, float(b[1]) + placement.y],
                              "kind": line["kind"]})
        by_page[key].append({"id": "P" + str(pi + 1), "part_index": pi,
                             "object_index": obj_id, "faces": faces_out, "lines": lines_out})
    var keys: Array = by_page.keys()
    keys.sort_custom(func(a: Variant, b: Variant) -> bool:
        var aa: PackedStringArray = str(a).split(":")
        var bb: PackedStringArray = str(b).split(":")
        return int(aa[0]) < int(bb[0]) or (int(aa[0]) == int(bb[0]) and int(aa[1]) < int(bb[1]))
    )
    var pages: Array = []
    for key in keys:
        pages.append({"width": pw, "height": ph, "pieces": by_page[key],
                      "sheet_id": key, "margin_x": side_margin, "margin_y": top_margin})
    return pages

func _f32() -> float:
    if failed: return 0.0
    if stream.get_position() + 4 > limit:
        _fail("Unexpected end of file")
        return 0.0
    return stream.get_float()

func _decode_texture(blob: PackedByteArray, w: int, h: int) -> Texture2D:
    # Pepakura embeds a COMPLETE zlib stream (78 9C ... Adler32).
    # Godot COMPRESSION_DEFLATE uses zlib's inflateInit2(window_bits=15),
    # which REQUIRES this header and Adler32 checksum. Do not strip bytes.
    var expected: int = w * h * 3
    if blob.size() < 6 or expected <= 0 or expected > 64 * 1024 * 1024:
        return null
    var raw: PackedByteArray = blob.decompress(expected, FileAccess.COMPRESSION_DEFLATE)
    if raw.size() != expected:
        push_warning("PDO texture failed to decompress: %dx%d, got %d bytes" % [w, h, raw.size()])
        return null
    var picture: Image = Image.create_from_data(w, h, false, Image.FORMAT_RGB8, raw)
    if picture == null or picture.is_empty():
        return null
    return ImageTexture.create_from_image(picture)

func _fail(message: String) -> void:
    failed = true
    reason = message
func _error() -> Dictionary:
    return {"error": "PDO decode stopped: " + reason}
func _skip(n: int) -> void:
    if failed: return
    if n < 0 or stream.get_position() + n > limit:
        _fail("Unexpected end of file")
        return
    stream.seek(stream.get_position() + n)
func _take(n: int) -> PackedByteArray:
    if failed or n < 0 or stream.get_position() + n > limit:
        _fail("Unexpected end of file")
        return PackedByteArray()
    return stream.get_data(n)[1]
func _u8() -> int:
    if failed: return 0
    return _take(1)[0] if not failed else 0
func _u32() -> int:
    if failed: return 0
    if stream.get_position() + 4 > limit:
        _fail("Unexpected end of file")
        return 0
    return stream.get_u32()
func _f64() -> float:
    if failed: return 0.0
    if stream.get_position() + 8 > limit:
        _fail("Unexpected end of file")
        return 0.0
    return stream.get_double()
func _count(max_count: int) -> int:
    var n := _u32()
    if n > max_count:
        _fail("Implausible record count " + str(n))
        return 0
    return n
func _string(k: int) -> String:
    var n := _u32()
    if n > MAX_STRING or n > limit - stream.get_position():
        _fail("Invalid string length")
        return ""
    var bytes := _take(n)
    var result := ""
    if multi:
        if n % 2 != 0:
            _fail("Invalid UTF-16 field")
            return ""
        for i in range(0, n - 2, 2):
            var code: int = int(bytes[i]) + (int(bytes[i + 1]) << 8)
            result += char((code - k) & 65535)
    else:
        for i in maxi(0, n - 1):
            result += char((int(bytes[i]) - k) & 255)
    return result
