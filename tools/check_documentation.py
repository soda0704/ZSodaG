"""Validate first-party Markdown links, file references and basic structure.

Run from the repository root: python tools/check_documentation.py
Only reads README.md and docs/**/*.md. Does not inspect third-party licenses.
"""
import re
import sys
from pathlib import Path
from urllib.parse import unquote


ROOT = Path(__file__).resolve().parents[1]
LINK = re.compile(r"!?\[[^\]\n]*\]\(([^)\n]+)\)")
CODE = re.compile(r"`([^`\n]+)`")
TEST = re.compile(r"\b([A-Za-z0-9_]+(?:_regression|_test)\.gd)\b")
LOCAL_PREFIXES = ("assets/", "scenes/", "scripts/", "tools/", "docs/", "addons/")
FILE_EXTENSIONS = {".gd", ".tscn", ".tres", ".res", ".json", ".png", ".exr", ".gltf", ".glb", ".txt", ".md"}


def prose(text):
    # Code fences may contain illustrative shell paths or command arguments.
    return re.sub(r"^```[^\n]*\n.*?^```\s*$", "", text, flags=re.M | re.S)


def check(path):
    errors = []
    text = path.read_text(encoding="utf-8")
    body = prose(text)
    title_count = len(re.findall(r"^# [^\n]+$", body, re.M))
    if title_count != 1:
        errors.append(f"expected one H1, found {title_count}")
    if not text.endswith("\n"):
        errors.append("missing final newline")
    if text.startswith("\ufeff"):
        errors.append("unexpected UTF-8 BOM")
    for match in LINK.finditer(body):
        target = match.group(1).strip()
        if target.startswith("<") and ">" in target:
            target = target[1:target.index(">")]
        else:
            target = target.split(' "', 1)[0]
        if re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*:", target) or target.startswith("#"):
            continue
        local = unquote(target.split("#", 1)[0].split("?", 1)[0])
        if local and not (path.parent / local).exists():
            errors.append(f"missing link target: {target}")
    for value in CODE.findall(body):
        value = value.removeprefix("res://")
        if not value.startswith(LOCAL_PREFIXES) or any(c in value for c in ("*", "{", "}", " ")):
            continue
        if value.endswith("/") or Path(value).suffix in FILE_EXTENSIONS:
            if not (ROOT / value).exists():
                errors.append(f"missing referenced file/directory: {value}")
    for name in sorted(set(TEST.findall(body))):
        if not (ROOT / "tools/tests" / name).exists():
            errors.append(f"missing test: {name}")
    return errors


def main():
    documents = [ROOT / "README.md", *sorted((ROOT / "docs").rglob("*.md"))]
    failures = 0
    for path in documents:
        for error in check(path):
            failures += 1
            print(f"FAIL {path.relative_to(ROOT).as_posix()}: {error}")
    index = ROOT / "docs/README.md"
    if index.exists():
        linked = {
            match.group(1).split("#", 1)[0]
            for match in LINK.finditer(prose(index.read_text(encoding="utf-8")))
        }
        for path in documents:
            if path.parent == ROOT or path == index:
                continue
            relative = path.relative_to(ROOT / "docs").as_posix()
            if relative not in linked:
                failures += 1
                print(f"FAIL docs/README.md: document not listed: {relative}")
    print(f"Documents: {len(documents)}; errors: {failures}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
