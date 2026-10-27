"""Plan/rewrite project file paths. Binary resources are handled by native tools.

Default/--plan is read-only apart from the ignored JSON report. Application is
called by normalize_project_resources.gd after backup and native resource loading.
"""
from pathlib import Path, PurePosixPath
from urllib.parse import quote, unquote
import argparse
import collections
import hashlib
import json
import os
import re
import struct
import subprocess
import time
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PLAN = ROOT / "tools/.local/path_normalization_plan.json"
TEXT = {".gd", ".tscn", ".tres", ".gdshader", ".gdshaderinc", ".godot", ".cfg", ".import", ".uid",
        ".py", ".ps1", ".cmd", ".bat", ".cjs", ".js", ".ts", ".json", ".md", ".txt", ".toml",
        ".xml", ".yml", ".yaml", ".gdextension", ".svg", ".vdf", ".html", ".css", ".ini", ".obj", ".mtl"}


def files():
    raw = subprocess.check_output(["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"], cwd=ROOT)
    return sorted({p for p in raw.decode("utf-8").split("\0") if p and (ROOT / p).is_file()})


def normalize(part):
    # Terrain3DUtil.filename_to_location decodes these signs as coordinates.
    if re.fullmatch(r"terrain3d[-_]\d+[-_]\d+\.res", part):
        return part
    part = part.replace("Terrain3D", "terrain_3d").replace("terrain_3D", "terrain_3d").replace("M4A1", "m4a1")
    part = re.sub(r"([A-Z]+)([A-Z][a-z])", r"\1_\2", part)
    part = re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", part)
    return re.sub(r"[\s-]+", "_", part).lower()


def make_plan():
    paths = files()
    mapping = {p: "/".join(normalize(c) for c in p.split("/")) for p in paths}
    incoming = collections.defaultdict(list)
    for old, new in mapping.items(): incoming[new.casefold()].append(old)
    collisions = {k: v for k, v in incoming.items() if len(v) > 1}
    directories = {}
    for old, new in mapping.items():
        a, b = PurePosixPath(old).parent, PurePosixPath(new).parent
        while str(a) != ".":
            if a != b: directories[str(a)] = str(b)
            a, b = a.parent, b.parent
    changed = {p: q for p, q in mapping.items() if p != q}
    graph_file = ROOT / "tools/.local/runtime_resource_graph.json"
    graph = json.loads(graph_file.read_text(encoding="utf-8-sig")) if graph_file.exists() else {}
    native = []
    for old in paths:
        if Path(old).suffix not in {".res", ".scn"}: continue
        deps = graph.get("res://" + old, [])
        if old in changed or any(d.removeprefix("res://").split("::")[0] in changed for d in deps):
            native.append(old)
    plan = {"root": str(ROOT), "files": paths, "mapping": changed, "directories": directories,
            "collisions": collisions, "native": native, "created": time.time()}
    PLAN.parent.mkdir(parents=True, exist_ok=True)
    PLAN.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"files": len(paths), "renames": len(changed), "native_resources": len(native),
                      "collisions": collisions}, ensure_ascii=False, indent=2))
    return plan


def backup(plan, directory):
    directory.mkdir(parents=True, exist_ok=True)
    target = directory / ("zsodag_before_naming_" + time.strftime("%Y%m%d_%H%M%S") + ".zip")
    with zipfile.ZipFile(target, "w", compression=zipfile.ZIP_STORED, allowZip64=True) as archive:
        for name in plan["files"]: archive.write(ROOT / name, name)
        archive.writestr("_snapshot/git_status.txt", subprocess.check_output(["git", "status", "--short"], cwd=ROOT))
        archive.writestr("_snapshot/path_plan.json", json.dumps(plan, ensure_ascii=False, indent=2))
        archive.writestr('_snapshot/git_index', (ROOT / '.git/index').read_bytes())
    plan["backup"] = str(target)
    plan["backup_size"] = target.stat().st_size
    plan['index_sha256'] = hashlib.sha256((ROOT / '.git/index').read_bytes()).hexdigest()
    plan['index_entries'] = [x.decode('utf-8') for x in subprocess.check_output(['git', 'ls-files', '--stage', '-z'], cwd=ROOT).split(b'\0') if x]
    with zipfile.ZipFile(target) as archive:
        if archive.testzip(): raise RuntimeError('Backup CRC verification failed')
    plan['backup_verified'] = True
    PLAN.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("BACKUP", target, target.stat().st_size, flush=True)


def path_rewriter(plan):
    substitutions = {}
    for old, new in plan["mapping"].items():
        substitutions[old] = new
        substitutions[old.replace("/", "\\")] = new.replace("/", "\\")
        substitutions[old.replace("/", "\\\\")] = new.replace("/", "\\\\")
    for old, new in plan['directories'].items():
        substitutions[old + '/'] = new + '/'
        substitutions[old.replace('/', '\\') + '\\'] = new.replace('/', '\\') + '\\'
        substitutions[old.replace('/', '\\\\') + '\\\\'] = new.replace('/', '\\\\') + '\\\\'
        substitutions['res://' + old] = 'res://' + new
    # Filenames in constructed paths also change, without touching node names.
    for old, new in plan["mapping"].items():
        a, b = PurePosixPath(old).name, PurePosixPath(new).name
        if a != b:
            if a in substitutions and substitutions[a] != b: raise RuntimeError("Ambiguous filename: " + a)
            substitutions[a] = b
    expression = re.compile("|".join(re.escape(x) for x in sorted(substitutions, key=len, reverse=True)))
    return lambda value: expression.sub(lambda m: substitutions[m[0]], value)


def rewrite_embedded_images(data, old, new, mapping):
    for image in data.get('images', []):
        if 'bufferView' in image and image.get('name'):
            extracted = str(PurePosixPath(old).parent / (PurePosixPath(old).stem + '_' + image['name']))
            candidates = [extracted] if extracted in mapping else []
            if not PurePosixPath(image['name']).suffix:
                extensions = {'image/jpeg': ['.jpg', '.jpeg'], 'image/png': ['.png'],
                              'image/webp': ['.webp']}.get(image.get('mimeType'), [])
                candidates += [extracted + ext for ext in extensions if extracted + ext in mapping]
            if len(candidates) > 1:
                raise RuntimeError('Ambiguous extracted image: ' + extracted)
            if candidates:
                prefix = PurePosixPath(new).stem + '_'
                image['name'] = PurePosixPath(mapping[candidates[0]]).name.removeprefix(prefix)
    return data


def rewrite_gltf(data, old, new, mapping):
    rewrite_embedded_images(data, old, new, mapping)
    for group in ("images", "buffers"):
        for entry in data.get(group, []):
            uri = entry.get("uri", "")
            if not uri or uri.startswith("data:") or '://' in uri: continue
            absolute = os.path.normpath(str(PurePosixPath(old).parent / unquote(uri))).replace("\\", "/")
            replacement = mapping.get(absolute, absolute)
            relative = os.path.relpath(replacement, str(PurePosixPath(new).parent)).replace("\\", "/")
            entry["uri"] = quote(relative, safe="/._-~")
    return data


def rewrite_markdown(text, old, new, mapping):
    def replace(match):
        target = match[2]
        if "://" in target or target.startswith(("#", "mailto:")): return match[0]
        clean, separator, fragment = target.partition("#")
        absolute = os.path.normpath(str(PurePosixPath(old).parent / unquote(clean))).replace("\\", "/")
        replacement = mapping.get(absolute, absolute)
        relative = os.path.relpath(replacement, str(PurePosixPath(new).parent)).replace("\\", "/")
        return match[1] + relative + (separator + fragment if separator else "") + ")"
    return re.sub(r"(!?\[[^\]\n]*\]\()([^\n)]+)\)", replace, text)


def apply(plan):
    if plan["collisions"]: raise RuntimeError("Unresolved filename collisions")
    if not Path(plan.get("backup", "__missing__")).is_file(): raise RuntimeError("Verified backup required")
    if not plan.get("backup_verified"): raise RuntimeError("Backup CRC verification required")
    if hashlib.sha256((ROOT / '.git/index').read_bytes()).hexdigest() != plan.get('index_sha256'):
        raise RuntimeError('Git index changed after preparation')
    for old, new in (plan['directories'] | plan['mapping']).items():
        source, destination = ROOT / old, ROOT / new
        if destination.exists() and not destination.samefile(source):
            raise RuntimeError('Destination already exists: ' + new)
    rewrite = path_rewriter(plan)
    mapping = plan["mapping"]
    prepared_file = ROOT / 'tools/.local/staged_path_updates.json'
    if prepared_file.exists():
        digest_file = ROOT / 'tools/.local/staged_path_mapping.sha256'
        digest = hashlib.sha256(json.dumps(plan['mapping'], sort_keys=True).encode()).hexdigest()
        if not digest_file.exists() or digest_file.read_text().strip() != digest:
            raise RuntimeError('Prepared reference updates belong to a different map')
    changes = json.loads(prepared_file.read_text(encoding='utf-8')) if prepared_file.exists() else []
    changes = [entry for entry in changes if entry[0] != 'tools/normalize_project_paths.py']
    staged = ROOT / "tools/.local/path_migration_staged"
    staged.mkdir(parents=True, exist_ok=True)
    # Prepare all rewritten bytes before touching source names.
    for old in ([] if prepared_file.exists() else plan["files"]):
        p = ROOT / old
        if not p.exists(): raise RuntimeError("Source disappeared: " + old)
        new = mapping.get(old, old)
        suffix = p.suffix.lower()
        content = p.read_bytes()
        result = content
        if suffix == ".gltf":
            data = json.loads(content.decode("utf-8-sig"))
            result = (json.dumps(rewrite_gltf(data, old, new, mapping), ensure_ascii=False, indent=2) + "\n").encode("utf-8")
        elif suffix == ".glb":
            magic, version, length = struct.unpack_from("<III", content)
            if magic != 0x46546C67 or length != len(content): raise RuntimeError("Invalid GLB: " + old)
            chunks, offset = [], 12
            while offset < len(content):
                size, kind = struct.unpack_from("<II", content, offset)
                payload = content[offset + 8:offset + 8 + size]
                if kind == 0x4E4F534A:
                    data = rewrite_gltf(json.loads(payload.decode("utf-8")), old, new, mapping)
                    payload = json.dumps(data, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
                    payload += b" " * ((-len(payload)) % 4)
                chunks.append(struct.pack("<II", len(payload), kind) + payload)
                offset += 8 + size
            result = struct.pack("<III", magic, version, 12 + sum(map(len, chunks))) + b"".join(chunks)
        elif suffix in TEXT or p.name in {".gitignore", ".gitattributes", ".editorconfig", ".gdignore"}:
            try: text = content.decode("utf-8-sig")
            except UnicodeDecodeError: continue
            if suffix == ".md": text = rewrite_markdown(text, old, new, mapping)
            cached = []
            external = []
            def protect_external(match):
                external.append(match[0])
                return '__naming_external_url_%d__' % (len(external) - 1)
            text = re.sub(r'(?:https?|plugin|app)://[^\s\"\'\)\]>]+', protect_external, text)
            if suffix == '.import':
                def protect(match):
                    cached.append(match[0])
                    return '__naming_cache_path_%d__' % (len(cached) - 1)
                text = re.sub(r'res://\.godot/[^\"\r\n]+', protect, text)
            text = rewrite(text)
            for index, original in enumerate(cached):
                text = text.replace('__naming_cache_path_%d__' % index, original)
            for index, original in enumerate(external):
                text = text.replace('__naming_external_url_%d__' % index, original)
            # Root source-directory names used as exact path components.
            if suffix in {'.gd', '.py', '.ps1', '.cjs', '.js'}:
                text = text.replace('"Blender"', '"blender"').replace("'Blender'", "'blender'")
            result = text.encode("utf-8")
        if result != content:
            file = staged / (hashlib.sha256(old.encode()).hexdigest() + ".data")
            file.write_bytes(result)
            changes.append((new, str(file)))
    blend_report = ROOT / "tools/.local/blend_path_migration.json"
    if not blend_report.exists(): raise RuntimeError("Blender dependency report required")
    blend = json.loads(blend_report.read_text(encoding="utf-8"))
    if blend.get("errors"): raise RuntimeError(str(blend["errors"]))
    # Rename files through temporary names so case-only changes work on NTFS.
    for old, new in mapping.items():
        source = ROOT / old
        name = PurePosixPath(new).name
        if source.name != name:
            temporary = source.with_name(source.name + ".naming_migration_tmp")
            if temporary.exists(): raise RuntimeError("Temporary target exists: " + str(temporary))
            retry(lambda: source.rename(temporary))
            retry(lambda: temporary.rename(source.with_name(name)))
    # Children first, before any parent directory changes its spelling.
    for old, new in sorted(plan["directories"].items(), key=lambda pair: pair[0].count("/"), reverse=True):
        source = ROOT / old
        name = PurePosixPath(new).name
        if source.name == name: continue
        temporary = source.with_name(source.name + ".naming_migration_tmp")
        if temporary.exists(): raise RuntimeError("Temporary target exists")
        retry(lambda: source.rename(temporary))
        retry(lambda: temporary.rename(source.with_name(name)))
    deferred = []
    for new, file in changes:
        if new in {'project.godot', 'export_presets.cfg'}:
            deferred.append([new, file])
            continue
        data = Path(file).read_bytes()
        retry(lambda: (ROOT / new).write_bytes(data))
    for item in blend["files"]:
        if item.get("staged"): (ROOT / item["new"]).write_bytes(Path(item["staged"]).read_bytes())
    plan["applied"] = time.time()
    plan["text_or_glb_updates"] = len(changes)
    plan['deferred_updates'] = deferred
    PLAN.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("APPLIED", len(mapping), "renames;", len(changes), "reference updates", flush=True)


def retry(action):
    for attempt in range(30):
        try: return action()
        except OSError:
            if attempt == 29: raise
            time.sleep(.25)


def finalize(plan):
    if not plan.get('native_complete'): raise RuntimeError('Native resource pass is not complete')
    for new, staged in plan.get('deferred_updates', []):
        data = Path(staged).read_bytes()
        if (ROOT / new).read_bytes() != data:
            retry(lambda: (ROOT / new).write_bytes(data))
    # Like git mv, preserve index blobs, including partial/pre-existing edits.
    removals, additions = bytearray(), bytearray()
    for record in plan['index_entries']:
        header, old = record.split('\t', 1)
        mode, object_id, stage = header.split()
        if stage != '0': raise RuntimeError('Unmerged Git index entry')
        if old not in plan['mapping']: continue
        removals.extend(('0 ' + '0' * 40 + '\t' + old + '\0').encode('utf-8'))
        additions.extend((mode + ' ' + object_id + '\t' + plan['mapping'][old] + '\0').encode('utf-8'))
    current = [r.decode('utf-8') for r in subprocess.check_output(['git', 'ls-files', '--stage', '-z'], cwd=ROOT).split(b'\0') if r]
    if current != plan['index_entries']: raise RuntimeError('Staged user content changed; do not overwrite it')
    original_index = (ROOT / '.git/index').read_bytes()
    scratch = ROOT / 'tools/.local/path_migration_index'
    scratch.write_bytes(original_index)
    environment = os.environ.copy()
    environment['GIT_INDEX_FILE'] = str(scratch)
    result = subprocess.run(['git', '-c', 'core.ignorecase=false', 'update-index', '-z', '--index-info'],
                            input=bytes(removals + additions), cwd=ROOT, env=environment, capture_output=True, timeout=30)
    if result.returncode: raise RuntimeError(result.stderr.decode('utf-8', errors='replace'))
    expected = sorted(header + '\t' + plan['mapping'].get(old, old)
                      for header, old in (row.split('\t', 1) for row in plan['index_entries']))
    actual = sorted(r.decode('utf-8') for r in subprocess.check_output(['git', 'ls-files', '--stage', '-z'], cwd=ROOT, env=environment).split(b'\0') if r)
    if actual != expected: raise RuntimeError('Prepared Git index differs from the rename map')
    lock = ROOT / '.git/index.lock'
    descriptor = os.open(lock, os.O_WRONLY | os.O_CREAT | os.O_EXCL)
    with os.fdopen(descriptor, 'wb') as stream:
        stream.write(scratch.read_bytes())
        stream.flush()
        os.fsync(stream.fileno())
    if (ROOT / '.git/index').read_bytes() != original_index: raise RuntimeError('Git index changed during preparation')
    retry(lambda: os.replace(lock, ROOT / '.git/index'))
    plan['finalized'] = time.time()
    PLAN.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print('FINALIZED', len(plan['mapping']), 'renames', flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan", action="store_true")
    parser.add_argument('--check', action='store_true')
    parser.add_argument("--backup", action="store_true")
    parser.add_argument("--apply-native-stage", action="store_true")
    parser.add_argument('--finalize', action='store_true')
    parser.add_argument('--backup-dir', type=Path, default=ROOT.parent / 'zsodag_backups')
    args = parser.parse_args()
    if args.finalize:
        finalize(json.loads(PLAN.read_text(encoding='utf-8')))
    elif args.apply_native_stage:
        apply(json.loads(PLAN.read_text(encoding="utf-8")))
    else:
        plan = make_plan()
        if args.backup: backup(plan, args.backup_dir)
        if args.check and (plan['mapping'] or plan['collisions']): raise SystemExit(1)
