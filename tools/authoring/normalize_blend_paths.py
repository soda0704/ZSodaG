"""Stage Blender source files with remapped dependencies; do not edit originals."""
import bpy
import hashlib
import json
import os
from pathlib import Path
import sys

root = Path(sys.argv[sys.argv.index("--") + 1]).resolve()
plan = json.loads((root / "tools/.local/path_normalization_plan.json").read_text(encoding="utf-8"))
mapping = {os.path.normcase(str(root / old)): root / new for old, new in plan["mapping"].items()}
directories = {os.path.normcase(str(root / old)): root / new for old, new in plan["directories"].items()}
staged = root / "tools/.local/path_migration_blends"
staged.mkdir(parents=True, exist_ok=True)
report = {"files": [], "errors": []}


def signature():
    data = {"objects": sorted((o.name, o.type, tuple(o.location), tuple(o.rotation_euler), tuple(o.scale)) for o in bpy.data.objects),
            "meshes": sorted((m.name, len(m.vertices), len(m.polygons)) for m in bpy.data.meshes),
            "materials": sorted(m.name for m in bpy.data.materials),
            "armatures": sorted((a.name, len(a.bones)) for a in bpy.data.armatures)}
    return hashlib.sha256(json.dumps(data, sort_keys=True).encode()).hexdigest()


def replacement(value, original, final):
    if not value or value.startswith('<'): return value
    absolute = os.path.normpath(bpy.path.abspath(value, start=str(original.parent)))
    target = mapping.get(os.path.normcase(absolute), directories.get(os.path.normcase(absolute)))
    if target is None: return value
    return "//" + os.path.relpath(target, final.parent).replace('\\', '/') if value.startswith('//') else str(target)


for old in plan["files"]:
    if not __import__('re').search(r'\.blend\d*$', old): continue
    original = root / old
    new = plan["mapping"].get(old, old)
    final = root / new
    try:
        bpy.ops.wm.open_mainfile(filepath=str(original), load_ui=False, use_scripts=False)
        before = signature()
        changed = 0
        containers = ['images', 'libraries', 'fonts', 'sounds', 'movieclips', 'cache_files', 'volumes']
        for collection in containers:
            for item in getattr(bpy.data, collection, []):
                if item.library is not None and collection != 'libraries': continue
                value = getattr(item, 'filepath', None)
                if value is None: continue
                updated = replacement(value, original, final)
                if updated != value:
                    item.filepath = updated
                    changed += 1
        entry = {"old": old, "new": new, "references_changed": changed, "signature": before,
                 "version": list(getattr(bpy.data, 'version', []))}
        if changed:
            destination = staged / (hashlib.sha256(old.encode()).hexdigest() + '.blend')
            bpy.context.preferences.filepaths.save_version = 0
            bpy.ops.wm.save_as_mainfile(filepath=str(destination), check_existing=False, relative_remap=False, compress=True)
            bpy.ops.wm.open_mainfile(filepath=str(destination), load_ui=False, use_scripts=False)
            if signature() != before: raise RuntimeError('Scene geometry/transform signature changed')
            entry['staged'] = str(destination)
        report['files'].append(entry)
        print('BLEND PREPARED', old, changed, flush=True)
    except Exception as error:
        report['errors'].append({"path": old, "error": str(error)})
    (root / 'tools/.local/blend_path_migration.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print('BLEND MIGRATION', len(report['files']), 'errors', report['errors'], flush=True)
if report['errors']: raise SystemExit(1)
