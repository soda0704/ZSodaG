"""Read-only asset inventory. Equal hashes are candidates, not permission to delete.

Run: python tools/audit_project_assets.py --output tools/.local/asset-audit.json
No third-party Python packages are required.
"""
import argparse
import hashlib
import json
import struct
from collections import defaultdict
from pathlib import Path


def audit(root):
    extensions = defaultdict(lambda: {"files": 0, "bytes": 0})
    hashes = defaultdict(list)
    largest = []
    oversized = []
    for path in sorted((root / "assets").rglob("*")):
        if not path.is_file():
            continue
        size = path.stat().st_size
        relative = path.relative_to(root).as_posix()
        extensions[path.suffix]["files"] += 1
        extensions[path.suffix]["bytes"] += size
        largest.append({"path": relative, "bytes": size})
        if path.suffix not in (".import", ".uid") and size >= 100_000:
            with path.open("rb") as stream:
                digest = hashlib.file_digest(stream, "sha256").hexdigest()
            hashes[digest].append({"path": relative, "bytes": size})
        if path.suffix.lower() == ".png":
            with path.open("rb") as stream:
                header = stream.read(24)
            if header[:8] == b"\x89PNG\r\n\x1a\n":
                width, height = struct.unpack(">II", header[16:24])
                if max(width, height) > 4096:
                    oversized.append({"path": relative, "width": width, "height": height})
    duplicates = [items for items in hashes.values() if len(items) > 1]
    return {
        "extensions": dict(extensions),
        "total_bytes": sum(value["bytes"] for value in extensions.values()),
        "largest": sorted(largest, key=lambda item: item["bytes"], reverse=True)[:30],
        "png_over_4k": oversized,
        "exact_duplicates": duplicates,
        "duplicate_candidate_bytes": sum(group[0]["bytes"] * (len(group) - 1) for group in duplicates),
        "warning": "Imported models, binary resources, editor sources and dynamic loads may reference duplicate files. Do not delete based on this report alone.",
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    report = audit(root)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Assets: {report['total_bytes'] / 2**20:.1f} MiB; duplicate candidates: {report['duplicate_candidate_bytes'] / 2**20:.1f} MiB; PNG >4K: {len(report['png_over_4k'])}")
