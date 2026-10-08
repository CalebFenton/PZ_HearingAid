"""Builds art/models/hearing_aid.blend and paints the four textures in common/media/textures/clothes.

    blender -b --factory-startup -P art/models/build.py

The aid is a behind-the-ear hearing aid: a curved shell behind the ear, an ear hook over its top
and an ear mold in the ear canal, coloured like the icons. It's modelled once for the right ear
of the male head. The Export collection holds linked duplicates that place that one mesh on each
ear of each head and on the ground; export.py writes them to FBX.

Units are the game's: the head bone's frame, where the head is about 0.16 tall. The scene uses
Blender's usual orientation: up is +Z, the character faces -Y and their right ear is at -X.
"""
import math
import os
import struct
import zlib

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
TEXTURES = os.path.join(REPO, "Contents/mods/HearingAid/common/media/textures/clothes")
TEXTURE_SIZE = 256


def head(up, lateral, forward):
    """A point given as height, sideways offset (negative is the character's right) and forward
    offset in the head bone's frame, the way the ear positions below were measured."""
    return Vector((lateral, -forward, up))


# Measured on the vanilla MaleBody.x and FemaleBody.x heads: the average of the top and the back
# of each head's right ear. The female ear sits lower, further in and further forward.
MALE_EAR = head(0.0774, -0.0609, -0.0167)
FEMALE_EAR = head(0.0754, -0.0569, -0.0129)
FEMALE_SCALE = 0.92

# Shell, bottom (battery end) to top, between the back of the ear and the skull.
SHELL_PATH = [
    head(0.0600, -0.0570, -0.0280),
    head(0.0670, -0.0572, -0.0292),
    head(0.0740, -0.0573, -0.0285),
    head(0.0805, -0.0573, -0.0262),
    head(0.0860, -0.0572, -0.0225),
    head(0.0898, -0.0570, -0.0178),
    head(0.0915, -0.0568, -0.0128),
]
SHELL_WIDTH = 0.0060  # sideways
SHELL_DEPTH = [0.0086, 0.0088, 0.0086, 0.0082, 0.0076, 0.0070, 0.0062]

# Ear hook from the top of the shell, over the top of the ear and down its front into the mold.
HOOK_PATH = [
    head(0.0912, -0.0568, -0.0135),
    head(0.0942, -0.0574, -0.0085),
    head(0.0955, -0.0583, -0.0032),
    head(0.0942, -0.0589, 0.0012),
    head(0.0905, -0.0590, 0.0042),
    head(0.0852, -0.0586, 0.0057),
    head(0.0790, -0.0581, 0.0057),
    head(0.0738, -0.0578, 0.0047),
]
HOOK_RADIUS = 0.0016

MOLD_CENTER = head(0.0698, -0.0573, 0.0036)
MOLD_RADII = (0.0042, 0.0028, 0.0038)  # up, sideways, forward

# UV rectangles (u0, v0, u1, v1) of each part in the texture.
SHELL_UV = (0.0, 0.52, 1.0, 1.0)
SHELL_CAP_UV = ((0.02, 0.38, 0.14, 0.50), (0.16, 0.38, 0.28, 0.50))
HOOK_UV = (0.0, 0.26, 1.0, 0.36)
HOOK_CAP_UV = ((0.30, 0.38, 0.36, 0.44), (0.38, 0.38, 0.44, 0.44))
MOLD_UV = (0.0, 0.0, 0.5, 0.24)

# Sampled from the item icons, so the model matches them.
WORKING = {"hook": ("#7b7088", "#beaed2", "#dcd2e6"), "mold": ("#988da9", "#c4bead", "#dedad0"),
           "led": "#35ea21", "marker": "#ddc400"}
BROKEN = {"hook": ("#5b5b5b", "#7c7c7c", "#9a9a9a"), "mold": ("#747474", "#9d9d9d", "#b4b4b4"),
          "led": "#752825", "marker": "#aea286"}
TIERS = {
    "Basic": dict(WORKING, shell=("#77723a", "#9b954e", "#c6c496")),
    "Efficient": dict(WORKING, shell=("#3a5d76", "#4e7b9b", "#96b2c6")),
    "Boosted": dict(WORKING, shell=("#702626", "#933434", "#bc8181")),
    "Broken": dict(BROKEN, shell=("#575757", "#737373", "#9d9d9d"), cracked=True),
}

# Linked duplicates in the Export collection, named after the files they become.
GROUND_SCALE = 2.0  # small world items are drawn larger than life


def mesh_placements():
    female = Matrix.Translation(FEMALE_EAR) @ Matrix.Scale(FEMALE_SCALE, 4) @ Matrix.Translation(-MALE_EAR)
    mirror = Matrix.Scale(-1, 4, (1, 0, 0))
    return {
        "M_HearingAid_Right": Matrix.Identity(4),
        "M_HearingAid_Left": mirror,
        "F_HearingAid_Right": female,
        "F_HearingAid_Left": mirror @ female,
    }


# Geometry -----------------------------------------------------------------------------------------


def set_uv(face, uv_layer, coords):
    for loop, coord in zip(face.loops, coords):
        loop[uv_layer].uv = coord


def sweep(bm, uv_layer, points, widths, depths, sides, rect, cap_rects):
    """A closed tube along points. Each ring is an ellipse `widths[i]` across sideways and
    `depths[i]` across in the other direction; ring vertex 0 faces the head. U runs along the tube
    and V around it, starting at the side that faces the head."""
    lengths = [0.0]
    for a, b in zip(points, points[1:]):
        lengths.append(lengths[-1] + (b - a).length)
    toward_head = Vector((1, 0, 0))
    rings, tangents = [], []
    for i, point in enumerate(points):
        tangent = (points[min(i + 1, len(points) - 1)] - points[max(i - 1, 0)]).normalized()
        across = (toward_head - tangent * toward_head.dot(tangent)).normalized()
        other = tangent.cross(across)
        rings.append([
            bm.verts.new(point + across * (widths[i] / 2 * math.cos(angle)) + other * (depths[i] / 2 * math.sin(angle)))
            for angle in (2 * math.pi * k / sides for k in range(sides))
        ])
        tangents.append(tangent)
    u0, v0, u1, v1 = rect
    for i in range(len(points) - 1):
        for k in range(sides):
            face = bm.faces.new((rings[i][k], rings[i][(k + 1) % sides], rings[i + 1][(k + 1) % sides], rings[i + 1][k]))
            set_uv(face, uv_layer, [
                (u0 + (u1 - u0) * lengths[i] / lengths[-1], v0 + (v1 - v0) * k / sides),
                (u0 + (u1 - u0) * lengths[i] / lengths[-1], v0 + (v1 - v0) * (k + 1) / sides),
                (u0 + (u1 - u0) * lengths[i + 1] / lengths[-1], v0 + (v1 - v0) * (k + 1) / sides),
                (u0 + (u1 - u0) * lengths[i + 1] / lengths[-1], v0 + (v1 - v0) * k / sides),
            ])
    # Slightly domed end caps.
    for i, cap, outward in ((0, cap_rects[0], -1), (-1, cap_rects[1], 1)):
        ring = rings[i]
        center = bm.verts.new(points[i] + tangents[i] * outward * min(widths[i], depths[i]) * 0.3)
        cu, cv, radius = (cap[0] + cap[2]) / 2, (cap[1] + cap[3]) / 2, (cap[2] - cap[0]) / 2
        for k in range(sides):
            face = bm.faces.new((center, ring[(k + 1) % sides], ring[k]))
            set_uv(face, uv_layer, [
                (cu, cv),
                (cu + radius * math.cos(2 * math.pi * (k + 1) / sides), cv + radius * math.sin(2 * math.pi * (k + 1) / sides)),
                (cu + radius * math.cos(2 * math.pi * k / sides), cv + radius * math.sin(2 * math.pi * k / sides)),
            ])


def ellipsoid(bm, uv_layer, center, radii, segments, rings, rect):
    """U goes around and V from the bottom pole to the top one."""
    up, sideways, forward = radii
    u0, v0, u1, v1 = rect

    def point(ring, segment):
        latitude = math.pi * ring / rings - math.pi / 2
        longitude = 2 * math.pi * segment / segments
        return center + Vector((math.cos(latitude) * math.cos(longitude) * sideways,
                                -math.cos(latitude) * math.sin(longitude) * forward,
                                math.sin(latitude) * up))

    grid = [[bm.verts.new(point(r, s)) for s in range(segments)] for r in range(1, rings)]
    bottom, top = bm.verts.new(point(0, 0)), bm.verts.new(point(rings, 0))

    def uv(ring, segment):
        return (u0 + (u1 - u0) * segment / segments, v0 + (v1 - v0) * ring / rings)

    for s in range(segments):
        s2 = (s + 1) % segments
        set_uv(bm.faces.new((bottom, grid[0][s2], grid[0][s])), uv_layer, [uv(0, s + 0.5), uv(1, s + 1), uv(1, s)])
        set_uv(bm.faces.new((top, grid[-1][s], grid[-1][s2])), uv_layer, [uv(rings, s + 0.5), uv(rings - 1, s), uv(rings - 1, s + 1)])
        for r in range(len(grid) - 1):
            face = bm.faces.new((grid[r][s], grid[r][s2], grid[r + 1][s2], grid[r + 1][s]))
            set_uv(face, uv_layer, [uv(r + 1, s), uv(r + 1, s + 1), uv(r + 2, s + 1), uv(r + 2, s)])


def build_mesh():
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")
    sweep(bm, uv_layer, SHELL_PATH, [SHELL_WIDTH] * len(SHELL_PATH), SHELL_DEPTH, 8, SHELL_UV, SHELL_CAP_UV)
    hook = [HOOK_RADIUS * 2] * len(HOOK_PATH)
    sweep(bm, uv_layer, HOOK_PATH, hook, hook, 6, HOOK_UV, HOOK_CAP_UV)
    ellipsoid(bm, uv_layer, MOLD_CENTER, MOLD_RADII, 8, 5, MOLD_UV)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for face in bm.faces:
        face.smooth = True
    mesh = bpy.data.meshes.new("HearingAid")
    bm.to_mesh(mesh)
    bm.free()
    return mesh


# Textures -----------------------------------------------------------------------------------------


def rgb(hex_color):
    return np.array([int(hex_color[i:i + 2], 16) for i in (1, 3, 5)], dtype=float)


def tones(colors, light):
    """Blends dark, base and light tones; light 0 is fully shaded, 1 fully lit."""
    dark, base, bright = (rgb(c) for c in colors)
    light = light[..., None]
    low = dark + (base - dark) * np.clip(light / 0.6, 0, 1)
    return np.where(light < 0.6, low, base + (bright - base) * np.clip((light - 0.6) / 0.4, 0, 1) * 0.8)


def tube_light(t):
    """Light around a tube: V 0 faces the head and 0.5 faces away from it."""
    return 0.5 - 0.5 * np.cos(2 * math.pi * t)


def paint(image, rect, colour):
    """Fills a UV rectangle; colour(s, t) gets the coordinates inside it from 0 to 1."""
    size = image.shape[0]
    x0, y0, x1, y1 = (round(c * size) for c in rect)
    s, t = np.meshgrid((np.arange(x0, x1) + 0.5 - x0) / (x1 - x0), (np.arange(y0, y1) + 0.5 - y0) / (y1 - y0))
    image[y0:y1, x0:x1] = colour(s, t)


def box(s, t, s0, s1, t0, t1):
    return (s >= s0) & (s <= s1) & (t >= t0) & (t <= t1)


def shell_colour(tier):
    def colour(s, t):
        c = tones(tier["shell"], 0.25 + 0.6 * tube_light(t) + 0.15 * s)
        seams = (np.abs(t - 0.25) < 0.025) | (np.abs(t - 0.75) < 0.025) | (np.abs(s - 0.2) < 0.012)
        c[seams] *= 0.78
        c[box(s, t, 0.05, 0.14, 0.58, 0.70)] = rgb(tier["marker"])
        c[box(s, t, 0.83, 0.93, 0.55, 0.69)] = rgb(tier["shell"][0]) * 0.6
        c[box(s, t, 0.85, 0.91, 0.57, 0.67)] = rgb(tier["led"])
        if tier.get("cracked"):
            crack = (np.abs(s - (0.48 + 0.035 * np.sin(t * 60))) < 0.01) & (t > 0.3) & (t < 0.7)
            c[crack] = rgb("#2e2e2e")
        return c
    return colour


def texture(tier):
    image = np.zeros((TEXTURE_SIZE, TEXTURE_SIZE, 3))
    image[:] = rgb(tier["shell"][1])
    paint(image, SHELL_UV, shell_colour(tier))
    for cap in SHELL_CAP_UV:
        paint(image, cap, lambda s, t: tones(tier["shell"], np.full(s.shape, 0.55)))
    paint(image, HOOK_UV, lambda s, t: tones(tier["hook"], 0.2 + 0.8 * tube_light(t)))
    for cap in HOOK_CAP_UV:
        paint(image, cap, lambda s, t: tones(tier["hook"], np.full(s.shape, 0.6)))
    paint(image, MOLD_UV, lambda s, t: tones(tier["mold"], 0.25 + 0.5 * t + 0.25 * tube_light(s)))
    return np.clip(image, 0, 255).astype(np.uint8)[::-1]  # rows from the top, as PNG stores them


def write_png(path, pixels):
    height, width, _ = pixels.shape
    raw = b"".join(b"\x00" + row.tobytes() for row in pixels)

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data))

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


# Scene --------------------------------------------------------------------------------------------


def textured_material():
    material = bpy.data.materials.new("HearingAid")
    if not material.node_tree:
        material.use_nodes = True
    nodes = material.node_tree.nodes
    image = nodes.new("ShaderNodeTexImage")
    image.image = bpy.data.images.load(os.path.join(TEXTURES, "HearingAid_Basic.png"))
    material.node_tree.links.new(image.outputs["Color"], nodes["Principled BSDF"].inputs["Base Color"])
    return material


def ground_matrix(mesh):
    """Lies the aid on its side with the outer face up, centred, resting on the ground."""
    turn = Matrix.Rotation(math.radians(90), 4, "Y") @ Matrix.Scale(GROUND_SCALE, 4)
    points = [turn @ v.co for v in mesh.vertices]
    low = Vector([min(p[i] for p in points) for i in range(3)])
    high = Vector([max(p[i] for p in points) for i in range(3)])
    return Matrix.Translation((-(low.x + high.x) / 2, -(low.y + high.y) / 2, -low.z)) @ turn


def main():
    for name, tier in TIERS.items():
        write_png(os.path.join(TEXTURES, f"HearingAid_{name}.png"), texture(tier))

    bpy.ops.wm.read_factory_settings(use_empty=True)
    mesh = build_mesh()
    mesh.materials.append(textured_material())
    export = bpy.data.collections.new("Export")
    bpy.context.scene.collection.children.link(export)
    placements = mesh_placements()
    placements["HearingAid_Ground"] = ground_matrix(mesh)
    for name, matrix in placements.items():
        obj = bpy.data.objects.new(name, mesh)
        obj.matrix_world = matrix
        export.objects.link(obj)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, "hearing_aid.blend"), relative_remap=True)


main()
