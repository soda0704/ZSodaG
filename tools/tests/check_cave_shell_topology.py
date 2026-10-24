"""Check the native mesh snapshot written by cave_shell_regression.gd.

Requires numpy and scipy. Every open edge must belong to the shaft rim or the
actual exterior mouth; terrain coverage is not used to excuse interior holes.
"""
from pathlib import Path
import json
import numpy as np
from scipy.spatial import cKDTree

root = Path(__file__).resolve().parents[2]
source = np.fromfile(root / "tools/.local/cave-shell-faces.bin", dtype="<f4").reshape(-1, 3)
vertices, remap = np.unique(np.round(source, 4), axis=0, return_inverse=True)
parent = np.arange(len(vertices))
for a, b in cKDTree(vertices).query_pairs(.00016, output_type="ndarray"):
    while parent[a] != a:
        a = parent[a]
    while parent[b] != b:
        b = parent[b]
    parent[max(a, b)] = min(a, b)
for i in range(len(parent)):
    while parent[i] != parent[parent[i]]:
        parent[i] = parent[parent[i]]
faces = parent[remap].reshape(-1, 3)
faces = faces[(faces[:, 0] != faces[:, 1]) & (faces[:, 1] != faces[:, 2]) & (faces[:, 0] != faces[:, 2])]
edges = np.concatenate([faces[:, [0, 1]], faces[:, [1, 2]], faces[:, [2, 0]]])
edges.sort(axis=1)
edges, counts = np.unique(edges, axis=0, return_counts=True)
boundary = edges[counts == 1]
mid = vertices[boundary].mean(axis=1)
shaft = (mid[:, 1] > -90.5) & (np.abs(mid[:, 0] + 33.5) < 3.3) & (np.abs(mid[:, 2] + 21) < 3.3)
mouth = (mid[:, 0] > 337) & (mid[:, 1] < -150) & (mid[:, 2] > -5) & (mid[:, 2] < 10)
unexpected = mid[~(shaft | mouth)]
report = {"shaft_rim_edges": int(shaft.sum()), "mouth_edges": int(mouth.sum()), "unexpected_open_edges": len(unexpected), "unexpected_samples": unexpected[:20].tolist()}
(root / "tools/.local/cave-shell-topology-report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
print("PASS" if not len(unexpected) else "FAIL", "cave topology", report)
raise SystemExit(1 if len(unexpected) else 0)
