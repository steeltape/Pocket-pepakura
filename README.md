# Pocket Pepakura v5 — paper-first Android PDO viewer

This revision is built for Godot 4.6+ (GDScript, Compatibility renderer). It keeps the original PDO paper layout, uses the PDO's embedded RGB textures and UV coordinates, and offers a full-size 3D model view.

## Start here (Android Godot editor or desktop)

1. Extract this ZIP to a normal folder. Do not open it inside the ZIP.
2. In Godot, **Import** `project.godot`. Re-open the imported project if prompted.
3. Press **Run Project** (F5 on desktop; Run in the Android Godot editor).
4. Press **Open PDO** and select your `.pdo` file; for example `Rem bust.pdo` from your existing archive.
5. The status should say `Embedded textures: 16 decoded, 0 failed` for the provided Rem PDO. If it says 0 decoded, report the status and Debugger error.
6. In **Paper**, tap a piece. Use **Locate in 3D** or **3D Model** for the large model view. Drag to rotate, pinch to zoom; **Fit 3D** resets.
7. Rotate a sufficiently wide tablet into landscape to enable **Split view**. If the device still stays portrait, enable auto-rotate in Android settings.

**Note:** the ZIP does not include the original Rem PDO file. Load that file separately from local storage. The included JSON demo is only a test of drawing/touch controls, *not a PDO sample*.

## What changed from v4.1

- Critical fix: PDO textures are **complete zlib streams**, including 2-byte header and 4-byte Adler-32 checksum. Godot's `COMPRESSION_DEFLATE` expects that wrapper. v4.1 incorrectly stripped it and all 16 textures failed.
- Texture success/failure counts are visible at the bottom so the result can be diagnosed.
- Original paper positions and paper margins are preserved; no automatic rearrangement.
- Paper, 3D Model, and wide-screen Split view modes. Tablet orientation = Sensor rather than forced portrait; `stretch/aspect="expand"` allows the viewport to adapt.
- 3D Fit and zoom buttons; drag to orbit and pinch to zoom.
- The PDO material record stores ambient RGBA first, then diffuse RGBA; the original code incorrectly used ambient gray. The renderer now uses diffuse colors for 3D, and paper-specific colors in 2D for untextured faces.
- A selected paper piece retains its printed texture, and its related 3D faces get a translucent cyan highlight instead of an opaque covering.
- UTF-16 metadata strings are decoded as 16-bit code units rather than the previous single-byte truncation.

## Structure

```text
PocketPepakura_v5/
├── project.godot             Godot settings: portrait + landscape, Compatibility renderer
├── main.tscn                Main Control scene
├── scripts/
│   ├── main.gd              UI, mode switching, model mesh building, camera/touch controls
│   ├── page_canvas.gd       Paper page drawing, texture UVs, clipping and selection
│   └── pdo_reader.gd        PDO 4/5/6 parser, layout data and zlib texture decoding
└── samples/
    └── demo_pages.json      Demonstration paper geometry; no PDO textures
```

## Technical notes

- Each PDO face carries its own polygon indices and UVs. Both 2D and 3D views use these original UVs; they do not stretch an entire image across the part bounding box.
- Godot's `PackedByteArray.decompress(expected_bytes, FileAccess.COMPRESSION_DEFLATE)` is passed the **full** PDO compressed texture blob.
- Textures are `Image.FORMAT_RGB8` with an expected decompressed length of `width * height * 3` bytes. Some PDO UVs lie outside the 0..1 square, so both 2D and 3D enable texture repeat.
- The 3D model groups triangles by `(paper_part_index, material_id)` so picking a paper part can highlight its associated 3D faces.
- The 3D selection overlay uses alpha transparency. It does not replace the original textured base material.
- `Split view` appears only when the display is sufficiently wide.

## Known limitations

- PDO is proprietary. This is an experimental reader, not a finished Pepakura Designer/Viewer clone.
- Matching edge IDs, glue tabs, edge name labels, fold styles and printable/PDF output are **not yet complete**.
- Some source PDO materials intentionally have no texture; those faces display their material color.
- Locked, encrypted or unsupported PDO variants cannot be opened.
- Full compatibility with other PDO files and all Android GPUs has not been verified.
- This version has not been executed in a Godot runtime in the development environment; please test in your editor and send the texture count + a screenshot if it fails.

## Useful debugging

**2D correct but 3D plain gray:** check the bottom text. `16 decoded, 0 failed` means image decompression worked. If the count is 0, check the output panel for `PDO texture failed to decompress` warnings.

**Split view missing:** rotate the tablet to landscape, ensure Android auto-rotate is enabled, and make the window wide enough.

**Objects too small/large:** press **Fit 3D**, then pinch to adjust. The camera calculates both horizontal and vertical fit for portrait screens.
