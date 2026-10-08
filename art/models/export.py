"""Exports every object in the Export collection of hearing_aid.blend to the mod's models_X folder.

    blender -b --factory-startup art/models/hearing_aid.blend -P art/models/export.py

Worn meshes go to Static/Clothes and HearingAid_Ground to WorldItems, each named after its object.
Transforms are baked into the vertices, so every node transform in the files is the identity.
"""
import os

import bpy
from mathutils import Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
MODELS = os.path.join(os.path.dirname(os.path.dirname(HERE)), "Contents/mods/HearingAid/common/media/models_X")

# The FBX exporter writes Blender's (x, y, z) as (x, z, -y). In the head bone's frame as the game
# sees an FBX file, x is up, y is toward the character's left and z points backward; the game
# loads meshes with assimp's MakeLeftHanded, which turns the vanilla .X heads' forward z around
# for FBX files. So worn meshes get up and sideways swapped and forward negated, a rotation.
TO_HEAD_BONE = Matrix(((0, 0, 1, 0), (0, -1, 0, 0), (1, 0, 0, 0), (0, 0, 0, 1)))


def export(obj, path, matrix):
    mesh = obj.data.copy()
    mesh.name = obj.name
    mesh.transform(matrix)
    if matrix.determinant() < 0:
        mesh.flip_normals()
    baked = bpy.data.objects.new(obj.name + "_export", mesh)
    bpy.context.scene.collection.objects.link(baked)
    bpy.ops.object.select_all(action="DESELECT")
    baked.select_set(True)
    bpy.context.view_layer.objects.active = baked
    bpy.ops.export_scene.fbx(filepath=path, use_selection=True, object_types={"MESH"}, bake_space_transform=True,
                             apply_scale_options="FBX_SCALE_ALL", add_leaf_bones=False, path_mode="STRIP")
    bpy.data.objects.remove(baked)
    bpy.data.meshes.remove(mesh)


for obj in bpy.data.collections["Export"].objects:
    if obj.name == "HearingAid_Ground":
        export(obj, os.path.join(MODELS, "WorldItems", obj.name + ".fbx"), obj.matrix_world)
    else:
        export(obj, os.path.join(MODELS, "Static/Clothes", obj.name + ".fbx"), TO_HEAD_BONE @ obj.matrix_world)
