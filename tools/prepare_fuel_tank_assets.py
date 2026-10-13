"""Separate the supplied tank's screw cap offline, preserving its native UVs.

The scene controls mounting and rotation; gameplay does not generate geometry.
"""
from pathlib import Path
import json
import struct
import numpy as np
from prepare_breaker_assets import write_obj

MODEL = Path(__file__).resolve().parents[1] / 'assets/models/electrical/fuel_tank'


def main():
    gltf = json.loads((MODEL / 'scene.gltf').read_text())
    binary = (MODEL / 'scene.bin').read_bytes()

    def accessor(index):
        item = gltf['accessors'][index]
        view = gltf['bufferViews'][item['bufferView']]
        count = {'VEC3': 3, 'VEC2': 2, 'SCALAR': 1}[item['type']]
        fmt = '<' + {5126: 'f', 5125: 'I'}[item['componentType']] * count
        stride = view.get('byteStride', struct.calcsize(fmt))
        offset = view.get('byteOffset', 0) + item.get('byteOffset', 0)
        return np.array([struct.unpack_from(fmt, binary, offset + j*stride)
                         for j in range(item['count'])])

    part = gltf['meshes'][0]['primitives'][0]
    vertices = accessor(part['attributes']['POSITION'])
    normals = accessor(part['attributes']['NORMAL'])
    uv = accessor(part['attributes']['TEXCOORD_0'])
    triangles = accessor(part['indices']).astype(int).reshape(-1, 3)
    parents = list(range(len(vertices)))

    def root(i):
        while parents[i] != i:
            parents[i] = parents[parents[i]]
            i = parents[i]
        return i

    def join(a, b):
        parents[root(a)] = root(b)

    welded = {}
    for i, point in enumerate(vertices):
        key = tuple(np.round(point, 5))
        if key in welded:
            join(i, welded[key])
        else:
            welded[key] = i
    for a, b, c in triangles:
        join(a, b)
        join(a, c)
    groups = {}
    for i in range(len(vertices)):
        groups.setdefault(root(i), []).append(i)
    cap = set()
    for indices in groups.values():
        lo, hi = vertices[indices].min(0), vertices[indices].max(0)
        if lo[1] > .92 and max(abs(lo[0]), abs(hi[0])) < .13:
            cap.update(indices)
    assert len(cap) == 690, 'Source cap geometry changed; inspect the part selection.'
    cap_center = (vertices[list(cap)].min(0) + vertices[list(cap)].max(0)) / 2
    source_scale = .5170583128929138
    for name, selected, offset in [('tank_body', False, np.zeros(3)),
                                   ('tank_cap', True, cap_center)]:
        faces = [tri for tri in triangles if (int(tri[0]) in cap) == selected]
        used = sorted(set(int(i) for tri in faces for i in tri))
        mapping = {i: j for j, i in enumerate(used)}
        write_obj(MODEL / (name + '.obj'), (vertices[used] - offset) * source_scale,
                  normals[used], np.column_stack([uv[used, 0], 1-uv[used, 1]]),
                  [[mapping[int(i)] for i in tri] for tri in faces])
    print('Prepared original tank body and independently mounted screw cap.')


if __name__ == '__main__':
    main()
