"""Remove only the detached below-ground rebar island from prepared joist 1.

Preserves the concrete, UVs, normals, materials and all useful reinforcement.
The supplied archive and alternate joist are not modified. Safe to rerun.
"""
from pathlib import Path
import json
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
SIZES = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}
DTYPES = {5120: 'i1', 5121: 'u1', 5122: '<i2', 5123: '<u2', 5125: '<u4', 5126: '<f4'}


def clean():
    path = ROOT / 'assets/models/heavy_props/concrete_joist_1.gltf'
    doc = json.loads(path.read_text(encoding='utf8'))
    binary_path = path.parent / doc['buffers'][0]['uri']
    binary = binary_path.read_bytes()
    arrays = []
    for accessor in doc['accessors']:
        view = doc['bufferViews'][accessor['bufferView']]
        dtype = np.dtype(DTYPES[accessor['componentType']])
        columns = SIZES[accessor['type']]
        arrays.append(np.ndarray((accessor['count'], columns), dtype=dtype, buffer=binary,
                                 offset=view.get('byteOffset', 0) + accessor.get('byteOffset', 0),
                                 strides=(view.get('byteStride', columns * dtype.itemsize), dtype.itemsize)).copy())
    removed = 0
    for primitive in doc['meshes'][0]['primitives']:
        if doc['materials'][primitive['material']]['name'] != 'roxory_ok':
            continue
        pos = arrays[primitive['attributes']['POSITION']]
        faces = arrays[primitive['indices']].reshape(-1, 3)
        below = pos[:, 1] < -.05
        # No triangle may connect the detached island to useful reinforcement.
        assert np.all(below[faces].all(1) == below[faces].any(1))
        keep = ~below[faces].all(1)
        removed += int((~keep).sum())
        if keep.all():
            continue
        faces = faces[keep]
        used, indices = np.unique(faces, return_inverse=True)
        for index in primitive['attributes'].values():
            arrays[index] = arrays[index][used]
        arrays[primitive['indices']] = indices.astype(arrays[primitive['indices']].dtype).reshape(-1, 1)
    if not removed:
        print('No detached below-ground rebar remains.')
        return 0
    packed = bytearray()
    views = []
    for index, (accessor, data) in enumerate(zip(doc['accessors'], arrays)):
        packed.extend(b'\0' * (-len(packed) % 4))
        view = {'buffer': 0, 'byteOffset': len(packed), 'byteLength': data.nbytes}
        previous = doc['bufferViews'][accessor['bufferView']]
        if 'target' in previous:
            view['target'] = previous['target']
        views.append(view)
        packed.extend(data.tobytes())
        accessor['bufferView'] = index
        accessor.pop('byteOffset', None)
        accessor['count'] = len(data)
        if 'min' in accessor:
            accessor['min'] = data.min(0).tolist()
            accessor['max'] = data.max(0).tolist()
    doc['bufferViews'] = views
    doc['buffers'][0]['byteLength'] = len(packed)
    binary_path.write_bytes(packed)
    path.write_text(json.dumps(doc), encoding='utf8')
    print(f'Removed {removed} detached rebar triangles; useful geometry unchanged.')
    return removed


if __name__ == '__main__':
    clean()
