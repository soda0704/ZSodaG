"""Keep the negative-X half of Platform_X without stretching its atlas UVs."""
from pathlib import Path
import copy
import hashlib
import json
import re
import struct

ROOT = Path(__file__).resolve().parents[2]
FOLDER = ROOT / "assets/models/modular_scifi_megakit/models/platforms"


def main():
    source = FOLDER / "Platform_X.gltf"
    model = json.loads(source.read_text(encoding="utf-8"))
    binary = (FOLDER / model["buffers"][0]["uri"]).read_bytes()
    primitive = model["meshes"][0]["primitives"][0]

    def read_accessor(index):
        accessor = model["accessors"][index]
        view = model["bufferViews"][accessor["bufferView"]]
        components = {"VEC3": 3, "VEC2": 2, "SCALAR": 1}[accessor["type"]]
        code = {5126: "f", 5123: "H"}[accessor["componentType"]]
        start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
        return list(struct.iter_unpack("<" + code * components,
                                     binary[start:start + view["byteLength"]]))

    positions = read_accessor(primitive["attributes"]["POSITION"])
    indices = [value[0] for value in read_accessor(primitive["indices"])]
    kept = []
    for offset in range(0, len(indices), 3):
        triangle = indices[offset:offset + 3]
        xs = [positions[index][0] for index in triangle]
        # This source already has edges along X=0; never silently drop a crossing face.
        assert not (min(xs) < -1e-6 and max(xs) > 1e-6)
        if max(xs) <= 1e-6:
            kept.extend(triangle)
    assert len(kept) * 2 == len(indices)
    used = sorted(set(kept))
    remap = {old: new for new, old in enumerate(used)}
    result = copy.deepcopy(model)
    result["nodes"][0]["name"] = "Platform_X_Half"
    result["meshes"][0]["name"] = "Platform_X_Half"
    result["asset"]["extras"] = {"derived_from": "Platform_X", "cut": "X <= 0"}
    output = bytearray()
    for index, accessor in enumerate(result["accessors"]):
        values = ([(remap[value],) for value in kept] if index == primitive["indices"]
                  else [read_accessor(index)[vertex] for vertex in used])
        while len(output) % 4:
            output.append(0)
        view = result["bufferViews"][accessor["bufferView"]]
        view["byteOffset"] = len(output)
        code = {5126: "f", 5123: "H"}[accessor["componentType"]]
        for value in values:
            output.extend(struct.pack("<" + code * len(value), *value))
        view["byteLength"] = len(output) - view["byteOffset"]
        accessor["count"] = len(values)
        if "min" in accessor:
            accessor["min"] = [min(v[axis] for v in values) for axis in range(len(values[0]))]
            accessor["max"] = [max(v[axis] for v in values) for axis in range(len(values[0]))]
    result["buffers"] = [{"byteLength": len(output), "uri": "Platform_X_Half.bin"}]
    target = FOLDER / "Platform_X_Half.gltf"
    target.with_suffix(".bin").write_bytes(output)
    target.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    settings = target.with_suffix(".gltf.import")
    if not settings.exists():
        resource = "res://" + target.relative_to(ROOT).as_posix()
        imported = "res://.godot/imported/" + target.name + "-" + hashlib.md5(resource.encode()).hexdigest() + ".scn"
        text = source.with_suffix(".gltf.import").read_text(encoding="utf-8")
        text = re.sub(r'^uid=.*\n', '', text, flags=re.M)
        text = re.sub(r'^path=.*$', 'path="' + imported + '"', text, flags=re.M)
        text = re.sub(r'^source_file=.*$', 'source_file="' + resource + '"', text, flags=re.M)
        text = re.sub(r'^dest_files=.*$', 'dest_files=["' + imported + '"]', text, flags=re.M)
        settings.write_text(text, encoding="utf-8")
    print(f"Platform_X_Half: {len(used)} vertices, {len(kept) // 3} triangles; original UVs and pivot preserved")


if __name__ == "__main__":
    main()
