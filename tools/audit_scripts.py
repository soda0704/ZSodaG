"""Read-only script reference audit, including global GDScript class names.

Tools and editor plugins are entry points, not unused gameplay scripts.
Candidates need human review because constructed paths cannot be proven statically.
"""
import argparse
import json
import os
import re
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TEXT_TYPES = {'.gd', '.tscn', '.tres', '.godot', '.cfg', '.py', '.ps1', '.cs', '.json'}


def audit(root=ROOT):
    texts = {}
    for folder in ('scripts', 'scenes', 'tools', 'addons', 'assets/config'):
        for directory, subdirs, files in os.walk(root / folder):
            subdirs[:] = [name for name in subdirs if name not in {'.local', '__pycache__', 'node_modules'}]
            for name in files:
                path = Path(directory) / name
                if path.suffix in TEXT_TYPES:
                    texts[path.relative_to(root).as_posix()] = path.read_text(encoding='utf-8-sig', errors='replace')
    texts['project.godot'] = (root / 'project.godot').read_text(encoding='utf-8-sig')
    scripts = {path: text for path, text in texts.items() if path.startswith('scripts/') and path.endswith('.gd')}
    incoming = defaultdict(set)
    missing = []
    for source, text in texts.items():
        for reference in re.findall(r'''res://[^\s"'\)\],;]+\.gd\b''', text):
            target = reference[6:]
            if target in scripts and target != source:
                incoming[target].add(source)
            elif not (root / target).is_file() and '%' not in target:
                missing.append({'source': source, 'target': target})
    classes = {}
    for target, text in scripts.items():
        match = re.search(r'^class_name\s+(\w+)', text, re.M)
        if match:
            classes[match[1]] = target
    for source, content in texts.items():
        for name in set(re.findall(r'\b[A-Za-z_]\w*\b', content)).intersection(classes):
            target = classes[name]
            if source != target:
                incoming[target].add(source)
    return {
        'script_count': len(scripts),
        'no_incoming_candidates': sorted(path for path in scripts if not incoming[path]),
        'missing_literal_script_paths': missing,
        'incoming': {path: sorted(incoming[path]) for path in sorted(scripts)},
        'note': 'Includes tools, scenes and global class uses. Documentation alone does not prove use. No incoming link is a review candidate, not automatic deletion approval.',
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    report = audit()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({key: value for key, value in report.items() if key != 'incoming'}, ensure_ascii=False, indent=2))
