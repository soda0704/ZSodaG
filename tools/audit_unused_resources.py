"""Conservative read-only resource audit. Requires Godot dependency graph JSON.
Never deletes files. Relative glTF URIs and external importer overrides are counted.
The result is a review list, not proof that authoring sources are disposable.
"""
import argparse, json, re
from collections import defaultdict
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[1]
TEXT = {'.gd', '.tscn', '.tres', '.gltf', '.import', '.gdshader', '.cfg', '.godot'}

def audit(graph_path):
    graph = json.loads(graph_path.read_text(encoding='utf-8'))
    incoming = defaultdict(set)
    for source, dependencies in graph.items():
        for target in dependencies:
            incoming[target].add(source)
    for folder in ['assets', 'scenes', 'scripts']:
        for path in (ROOT / folder).rglob('*'):
            if not path.is_file() or path.suffix not in TEXT:
                continue
            source = 'res://' + path.relative_to(ROOT).as_posix()
            if path.suffix == '.import':
                source = source.removesuffix('.import')
            text = path.read_text(encoding='utf-8-sig', errors='replace')
            for target in re.findall(r'res://[^\s"\'\)\],;]+', text):
                if target != source and not target.startswith('res://.godot/'):
                    incoming[target].add(source)
            if path.suffix == '.gltf':
                data = json.loads(text)
                for entry in data.get('images', []) + data.get('buffers', []):
                    uri = entry.get('uri', '')
                    if uri and not uri.startswith('data:'):
                        target = (path.parent / unquote(uri)).resolve()
                        if target.is_relative_to(ROOT):
                            incoming['res://' + target.relative_to(ROOT).as_posix()].add(source)
    candidates = []
    for path in (ROOT / 'assets').rglob('*'):
        if not path.is_file() or path.suffix in {'.import', '.uid', '.md', '.txt'}:
            continue
        uri = 'res://' + path.relative_to(ROOT).as_posix()
        if not incoming[uri]:
            candidates.append({'path': uri[6:], 'bytes': path.stat().st_size})
    candidates.sort(key=lambda row: row['bytes'], reverse=True)
    return {'warning': 'No incoming resource links does not exclude authoring use or constructed dynamic paths. Do not delete automatically.',
            'resource_count': len(graph), 'no_incoming_candidates': candidates}

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--graph', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    report = audit(args.graph)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(f"Resources: {report['resource_count']}; candidates requiring review: {len(report['no_incoming_candidates'])}")
