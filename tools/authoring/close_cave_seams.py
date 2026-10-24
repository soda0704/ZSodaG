"""Offline triangulation of accidental boundaries in the saved cave mesh.

Input comes from cave_shell_regression.gd, not from an old procedural bake.
The shaft entrance and the actual exterior mouth remain open. Godot imports the
result as an editable static mesh with matching collision; nothing runs in-game.
"""
from pathlib import Path
import json
import numpy as np
from scipy.spatial import cKDTree

ROOT = Path(__file__).resolve().parents[2]


def triangulate(points):
    _, _, axes = np.linalg.svd(points - points.mean(axis=0), full_matrices=False)
    flat = (points - points.mean(axis=0)) @ axes[:2].T
    cross = lambda a, b: float(a[0] * b[1] - a[1] * b[0])
    area = sum(cross(a, b) for a, b in zip(flat, np.roll(flat, -1, axis=0)))
    sign = 1 if area > 0 else -1
    remaining = list(range(len(points)))
    triangles = []
    while len(remaining) > 3:
        for i, b in enumerate(remaining):
            a, c = remaining[i - 1], remaining[(i + 1) % len(remaining)]
            if sign * cross(flat[b] - flat[a], flat[c] - flat[b]) <= 1e-12:
                continue
            contained = False
            for p in remaining:
                if p in (a, b, c):
                    continue
                if all(sign * cross(flat[y] - flat[x], flat[p] - flat[x]) >= -1e-12 for x, y in ((a, b), (b, c), (c, a))):
                    contained = True
                    break
            if not contained:
                triangles.append([a, b, c])
                remaining.pop(i)
                break
        else:
            raise ValueError("Non-simple boundary requires manual geometry repair")
    triangles.append(remaining)
    return triangles


def main():
    data = np.load(ROOT / "tools/.local/cave-shell-topology.npz")
    vertices, faces, edges = data["vertices"], data["faces"], data["boundary"]
    original = np.fromfile(ROOT / "tools/.local/cave-shell-faces.bin", dtype="<f4").reshape(-1, 3)
    exact = original[cKDTree(original).query(vertices)[1]]
    directed = {}
    for a, b, c in faces:
        for x, y in ((a, b), (b, c), (c, a)):
            directed[(min(x, y), max(x, y))] = (int(x), int(y))
    adjacent = {}
    for a, b in edges:
        adjacent.setdefault(int(a), set()).add(int(b))
        adjacent.setdefault(int(b), set()).add(int(a))
    loops = []
    while any(adjacent.values()):
        start = next(k for k, value in adjacent.items() if value)
        path, seen, previous = [start], {start: 0}, None
        while True:
            at = path[-1]
            following = min(adjacent[at] - ({previous} if previous is not None else set()))
            if following in seen:
                loop = path[seen[following]:]
                loops.append(loop)
                for a, b in zip(loop, loop[1:] + loop[:1]):
                    adjacent[a].remove(b)
                    adjacent[b].remove(a)
                break
            seen[following] = len(path)
            previous = at
            path.append(following)
    output, skipped = [], []
    for loop in loops:
        points = vertices[loop]
        shaft = np.all(points[:, 1] > -90.5)
        mouth = points[:, 0].min() > 337 and np.ptp(points[:, 2]) > 10
        if shaft or mouth:
            skipped.append({"type": "shaft" if shaft else "mouth", "edges": len(loop)})
            continue
        # New triangles must traverse each shared boundary opposite its old face.
        orientation = [directed[(min(a, b), max(a, b))] == (a, b) for a, b in zip(loop, loop[1:] + loop[:1])]
        assert all(orientation) or not any(orientation), "Inconsistent source winding"
        if all(orientation):
            loop.reverse()
        positions = exact[loop].astype(float)
        output.append({"vertices": positions.tolist(), "faces": triangulate(positions)})
    assert len(skipped) == 2, skipped
    result = {"holes": output, "intentional_openings": skipped, "triangles": sum(len(x["faces"]) for x in output)}
    destination = ROOT / "tools/authoring/cave_shell_repairs.json"
    destination.write_text(json.dumps(result, indent=2), encoding="utf-8")
    print("CAVE REPAIRS", len(output), "holes;", result["triangles"], "triangles; preserved", skipped)


if __name__ == "__main__":
    main()
