"""Offline authoring of the supplied breaker parts and fixed cable routes.

Run after extracting mechanical_door_controls.zip into its model folder.
Outputs ordinary editable OBJ resources; gameplay never generates meshes.
"""
from pathlib import Path
import json
import math
import struct
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
MODEL = ROOT / 'assets/models/electrical/mechanical_door_controls'
WIRES = ROOT / 'assets/models/electrical/wires'


def write_obj(path, positions, normals, uvs, triangles):
    lines = ['# Authored offline; imported by Godot as a standard mesh.']
    lines += ['v ' + ' '.join(f'{v:.8f}' for v in p) for p in positions]
    lines += ['vt ' + ' '.join(f'{v:.8f}' for v in uv) for uv in uvs]
    lines += ['vn ' + ' '.join(f'{v:.8f}' for v in n) for n in normals]
    lines += ['f ' + ' '.join(f'{i+1}/{i+1}/{i+1}' for i in tri) for tri in triangles]
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text('\n'.join(lines) + '\n', encoding='utf-8')


def prepare_controls():
    gltf = json.loads((MODEL / 'scene.gltf').read_text())
    binary = (MODEL / 'scene.bin').read_bytes()

    def accessor(index):
        item = gltf['accessors'][index]
        view = gltf['bufferViews'][item['bufferView']]
        count = {'VEC3': 3, 'VEC2': 2, 'SCALAR': 1}[item['type']]
        fmt = '<' + {5126: 'f', 5123: 'H', 5125: 'I'}[item['componentType']] * count
        stride = view.get('byteStride', struct.calcsize(fmt))
        offset = view.get('byteOffset', 0) + item.get('byteOffset', 0)
        return np.array([struct.unpack_from(fmt, binary, offset + j*stride) for j in range(item['count'])])

    part = gltf['meshes'][1]['primitives'][0]  # Assembled model, not the exploded example.
    vertices = accessor(part['attributes']['POSITION'])
    normals = accessor(part['attributes']['NORMAL'])
    uvs = accessor(part['attributes']['TEXCOORD_0'])
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
    for j, point in enumerate(vertices):
        key = tuple(np.round(point, 5))
        if key in welded:
            join(j, welded[key])
        else:
            welded[key] = j
    for a, b, c in triangles:
        join(a, b)
        join(a, c)
    groups = {}
    for j in range(len(vertices)):
        groups.setdefault(root(j), []).append(j)
    moving = set()
    for indices in groups.values():
        lo, hi = vertices[indices].min(axis=0), vertices[indices].max(axis=0)
        # Stem and upper crossbar move about the fixed lower bearing.
        stem = lo[2] > .20 and hi[2] < .37 and 1.99 < lo[1] and hi[1] < 2.4
        crossbar = lo[1] > 2.37 and hi[1] < 2.59 and lo[0] < -.13 and hi[0] > 0
        if stem or crossbar:
            moving.update(indices)
    assert len(moving) == 751, 'Source geometry changed: inspect the handle selection.'
    rotation = np.array([[0, 0, 1], [0, 1, 0], [-1, 0, 0]])
    positions = vertices @ rotation.T * .9
    positions[:, 1] -= 2.313945 * .9
    normals = normals @ rotation.T
    pivot = np.array([.287*.9, (2.02-2.313945)*.9, .066*.9])
    for name, predicate, offset in [
        ('housing', lambda tri: int(tri[0]) not in moving, np.zeros(3)),
        ('handle', lambda tri: int(tri[0]) in moving, pivot),
    ]:
        chosen = [tri for tri in triangles if predicate(tri)]
        unique = sorted(set(int(i) for tri in chosen for i in tri))
        mapping = {i: j for j, i in enumerate(unique)}
        faces = [[mapping[int(i)] for i in tri] for tri in chosen]
        write_obj(MODEL / f'{name}.obj', positions[unique]-offset, normals[unique],
                  np.column_stack([uvs[unique, 0], 1-uvs[unique, 1]]), faces)
    print('Prepared original housing and movable handle; pivot', pivot.tolist())


def prepare_cables():
    rows = [.30, .10, -.10, -.30]
    for source in range(4):
        for destination in range(-1, 4):
            start = np.array([-.285, rows[source], .07])
            end = np.array([-.08, rows[source]-.07, .15]) if destination < 0 else np.array([.285, rows[destination], .07])
            control1 = start + np.array([.15, -.025, .07 + source*.012])
            control2 = end + np.array([-.12, -.045, .09 + source*.012])
            positions, normals, uvs, triangles = [], [], [], []
            for ring in range(33):
                t = ring / 32
                center = (1-t)**3*start + 3*(1-t)**2*t*control1 + 3*(1-t)*t*t*control2 + t**3*end
                tangent = 3*(1-t)**2*(control1-start) + 6*(1-t)*t*(control2-control1) + 3*t*t*(end-control2)
                tangent /= np.linalg.norm(tangent)
                side = np.cross(tangent, [0, 0, 1])
                side /= np.linalg.norm(side)
                up = np.cross(side, tangent)
                for edge in range(10):
                    normal = math.cos(edge*math.tau/10)*side + math.sin(edge*math.tau/10)*up
                    positions.append(center + normal*.0048)
                    normals.append(normal)
                    uvs.append([edge/10, t])
                    if ring < 32:
                        a, b = ring*10+edge, ring*10+(edge+1)%10
                        triangles.extend([[a, b, a+10], [b, b+10, a+10]])
            name = f'loose_{source}' if destination < 0 else f'route_{source}_{destination}'
            write_obj(WIRES / f'{name}.obj', positions, normals, uvs, triangles)
    print('Prepared four loose cables and sixteen fixed routes.')


if __name__ == '__main__':
    prepare_controls()
    prepare_cables()
