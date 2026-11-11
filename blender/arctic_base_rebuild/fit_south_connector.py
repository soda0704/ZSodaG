"""Keep all four roof bridges above the modular rooms' ceilings.

Run on arctic_base_rebuild.blend with Blender --background --python.
The eight isolated side sheets at the hub/wing junctions are shortened.
Their upper roof connection remains a closed solid; materials and UVs survive.
"""
import bpy
import bmesh
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/models/architecture/arctic_base_rebuild'
def fit(ob):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    seen = set()
    parts = []
    for seed in bm.verts:
        if seed in seen:
            continue
        stack, part = [seed], []
        seen.add(seed)
        while stack:
            vertex = stack.pop()
            part.append(vertex)
            for edge in vertex.link_edges:
                other = edge.other_vert(vertex)
                if other not in seen:
                    seen.add(other)
                    stack.append(other)
        lo = [min(v.co[k] for v in part) for k in range(3)]
        hi = [max(v.co[k] for v in part) for k in range(3)]
        # Blender Z is Godot Y. Match the disconnected bridge solids in both
        # horizontal axes; never cut the wing walls or the closed roof caps.
        bridge = False
        for along, across in [(0, 1), (1, 0)]:
            negative = abs(lo[along] + 10.6) < .02 and abs(hi[along] + 7.6) < .02
            positive = abs(lo[along] - 7.6) < .02 and abs(hi[along] - 10.6) < .02
            bridge |= ((negative or positive) and
                       .14 < hi[across] - lo[across] < .18 and
                       2.7 < abs((lo[across] + hi[across]) / 2) < 3.0)
        if bridge and lo[2] < 5.21:
            parts.append(part)
    if len(parts) != 8:
        raise RuntimeError(f'Expected eight bridge sheets, found {len(parts)}')
    for part in parts:
        if min(v.co.z for v in part) >= 5.19:
            continue
        edges = set(e for v in part for e in v.link_edges)
        faces = set(f for v in part for f in v.link_faces)
        result = bmesh.ops.bisect_plane(bm, geom=part + list(edges) + list(faces),
                                       dist=0.00001, plane_co=(0, 0, 5.2),
                                       plane_no=(0, 0, 1), clear_inner=True,
                                       clear_outer=False)
        cut = [edge for edge in result['geom_cut'] if isinstance(edge, bmesh.types.BMEdge) and edge.is_boundary]
        caps = bmesh.ops.holes_fill(bm, edges=cut, sides=0)['faces']
        for face in caps:
            face.material_index = 0
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.update()
    
for name in ['Base_ExteriorShell_Mesh', 'ShellCollisionProxy']:
    fit(bpy.data.objects[name])
ob = bpy.data.objects['Base_ExteriorShell_Mesh']
for item in bpy.context.scene.objects:
    item.select_set(False)
exported = []
for item in bpy.context.scene.objects:
    if item.type == 'MESH' and item.name != 'Garage_Insulated_Shutter':
        item.hide_set(False)
        item.select_set(True)
        exported.append(item)
bpy.context.view_layer.objects.active = ob
bpy.ops.export_scene.gltf(filepath=str(OUT / 'arctic_base_rebuild.glb'),
                          export_format='GLB', use_selection=True,
                          use_active_scene=True, export_vertex_color='ACTIVE',
                          export_texcoords=True, export_normals=True,
                          export_materials='EXPORT', export_apply=True)
bpy.data.objects['ShellCollisionProxy'].hide_set(True)
bpy.data.objects['ShellCollisionProxy'].hide_render = True
bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
print('ALL CONNECTORS FIT: 8 side sheets and collision above 5.2 m; closed roofs retained', flush=True)

