"""Renders every object in the Export collection of hearing_aid.blend, the worn ones on the
matching vanilla head, so you can check the fit without starting the game:

    blender -b --factory-startup art/models/hearing_aid.blend -P art/models/preview.py

Writes <object>_<view>.png to PREVIEWS (default $TMPDIR/hearing-aid-previews) and prints the folder.
"""
import math
import os
import sys
import tempfile

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vanilla_heads  # noqa: E402

OUT = os.environ.get("PREVIEWS", os.path.join(tempfile.gettempdir(), "hearing-aid-previews"))


def setup():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "TEXTURE"
    scene.render.resolution_x = scene.render.resolution_y = 512
    scene.render.film_transparent = False
    world = bpy.data.worlds.new("Preview")
    world.color = (0.3, 0.3, 0.3)
    scene.world = world
    camera = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
    camera.data.type = "ORTHO"
    scene.collection.objects.link(camera)
    scene.camera = camera
    return camera


def render(camera, target, direction, size, path):
    """An orthographic view of `size` across, looking along `direction` at `target`."""
    direction = Vector(direction).normalized()
    camera.location = target - direction
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    camera.data.ortho_scale = size
    camera.data.clip_start, camera.data.clip_end = 0.01, 10
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def centre(obj):
    points = [obj.matrix_world @ v.co for v in obj.data.vertices]
    return sum(points, Vector()) / len(points)


def main():
    os.makedirs(OUT, exist_ok=True)
    heads = vanilla_heads.load()
    camera = setup()
    shown = list(bpy.data.collections["Export"].objects) + list(heads.objects)
    for obj in bpy.data.collections["Export"].objects:
        for other in shown:
            other.hide_render = other is not obj
        if obj.name == "HearingAid_Ground":
            target = centre(obj)
            render(camera, target, (-1, 1, -math.tan(math.radians(30)) * math.sqrt(2)), 0.12, f"{OUT}/{obj.name}_iso.png")
            render(camera, target, (0, 0, -1), 0.12, f"{OUT}/{obj.name}_top.png")
            continue
        heads.objects[("Female" if obj.name.startswith("F_") else "Male") + "Head"].hide_render = False
        target = centre(obj)
        outward = 1 if target.x > 0 else -1
        render(camera, target, (-outward, 0, 0), 0.06, f"{OUT}/{obj.name}_side.png")
        render(camera, target, (0, -1, 0), 0.06, f"{OUT}/{obj.name}_back.png")
        render(camera, target, (0, 0, -1), 0.06, f"{OUT}/{obj.name}_top.png")
        render(camera, Vector((0, 0, target.z)), (0, 1, 0), 0.2, f"{OUT}/{obj.name}_front.png")
    print("previews:", OUT)


main()
