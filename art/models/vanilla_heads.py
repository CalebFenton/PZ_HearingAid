"""Loads the heads of the game's male and female characters into a Reference collection, in the
frame that build.py models in, to fit the aid against:

    blender art/models/hearing_aid.blend -P art/models/vanilla_heads.py

They come from the game install (PZ_APP overrides its Contents folder, as in dev/lib.sh), and
saving the .blend leaves them out, because they're the game's art.
"""
import os
import re

import bpy
from mathutils import Matrix, Vector

PZ_APP = os.environ.get("PZ_APP", os.path.expanduser(
    "~/Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app/Contents"))
COLLECTION = "Reference"
NUMBER = r"(-?\d+(?:\.\d+)?(?:e-?\d+)?)"


def read_head(sex):
    """The faces skinned mostly to Bip01_Head in <sex>Body.x, in the head bone's frame."""
    with open(os.path.join(PZ_APP, "Java/media/models_X/Skinned", sex + "Body.x"), encoding="latin-1") as f:
        text = f.read().replace("\r", "")
    mesh = re.search(r"\n\s*Mesh \w+ \{\s*(\d+);", text)
    vertex_count, pos = int(mesh.group(1)), mesh.end()
    vertices = []
    for match in re.compile(NUMBER + ";" + NUMBER + ";" + NUMBER + ";[,;]").finditer(text, pos):
        vertices.append(Vector([float(g) for g in match.groups()]))
        if len(vertices) == vertex_count:
            pos = match.end()
            break
    face_count = re.compile(r"\s*(\d+);").match(text, pos)
    faces = []
    for match in re.compile(r"(\d+);([\d,]+);[,;]").finditer(text, face_count.end()):
        faces.append([int(i) for i in match.group(2).split(",")])
        if len(faces) == int(face_count.group(1)):
            break
    weights = re.search(r'SkinWeights \{\s*"Bip01_Head";\s*(\d+);', text)
    count = int(weights.group(1))
    values = [v for v in re.split(r"[,;\s]+", text[weights.end():text.find("}", weights.end())]) if v]
    indices = [int(v) for v in values[:count]]
    head = {i for i, w in zip(indices, (float(v) for v in values[count:2 * count])) if w > 0.5}
    m = [float(v) for v in values[2 * count:2 * count + 16]]
    # DirectX stores row vectors: a point times the offset matrix is in the bone's frame.
    offset = Matrix((m[0:4], m[4:8], m[8:12], m[12:16])).transposed()
    return [offset @ v for v in vertices], [f for f in faces if all(i in head for i in f)]


def load():
    if COLLECTION in bpy.data.collections:
        return bpy.data.collections[COLLECTION]
    collection = bpy.data.collections.new(COLLECTION)
    bpy.context.scene.collection.children.link(collection)
    skin = bpy.data.materials.new("ReferenceSkin")
    skin.diffuse_color = (0.8, 0.62, 0.5, 1)
    for sex in ("Male", "Female"):
        vertices, faces = read_head(sex)
        # Bone frame: x up, y toward the character's left, z forward.
        points = [(v.y, -v.z, v.x) for v in vertices]
        mesh = bpy.data.meshes.new(sex + "Head")
        mesh.from_pydata(points, [], faces)
        mesh.materials.append(skin)
        collection.objects.link(bpy.data.objects.new(sex + "Head", mesh))
    return collection


@bpy.app.handlers.persistent
def leave_out(_):
    collection = bpy.data.collections.get(COLLECTION)
    if collection:
        for obj in list(collection.objects):
            mesh = obj.data
            bpy.data.objects.remove(obj)
            bpy.data.meshes.remove(mesh)
        bpy.data.collections.remove(collection)
    skin = bpy.data.materials.get("ReferenceSkin")
    if skin:
        bpy.data.materials.remove(skin)


if leave_out not in bpy.app.handlers.save_pre:
    bpy.app.handlers.save_pre.append(leave_out)

if __name__ == "__main__":
    load()
