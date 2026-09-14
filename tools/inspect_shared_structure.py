"""Read-only audit of the artist's Blender source; never saves the .blend."""
import bpy
from mathutils import Vector

for obj in bpy.data.objects:
    if obj.type == 'MESH':
        points = [obj.matrix_world @ Vector(p) for p in obj.bound_box]
        print('ART_MESH', obj.name, 'min', tuple(min(p[i] for p in points) for i in range(3)),
              'max', tuple(max(p[i] for p in points) for i in range(3)),
              'materials', [m.name for m in obj.data.materials if m])
for image in bpy.data.images:
    print('ART_IMAGE', image.name, image.filepath, 'packed', bool(image.packed_file))
