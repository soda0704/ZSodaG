"""Build a verified Windows release payload, then its installer and portable ZIP.

Run from any directory with Python 3: python tools/build_playtest.py
Requires the matching Godot release template and Inno Setup 7 compiler.
Existing developer builds are never replaced. Failed audits stop packaging.
"""
from __future__ import annotations

import argparse
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parent.parent


def run(args: list[str], name: str, timeout: int = 300) -> None:
    print(name, flush=True)
    result = subprocess.run(args, cwd=ROOT, capture_output=True, timeout=timeout)
    logs = ROOT / "tools/.local/playtest-build"
    logs.mkdir(parents=True, exist_ok=True)
    (logs / f"{name}.stdout.log").write_bytes(result.stdout)
    (logs / f"{name}.stderr.log").write_bytes(result.stderr)
    output = (result.stdout + result.stderr).decode("utf-8", "replace")
    if result.returncode or re.search(r"(?m)^(?:SCRIPT ERROR:|ERROR:|FAIL |Unicode parsing error)", output):
        raise RuntimeError(f"{name} failed ({result.returncode}); see {logs}")


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, default=ROOT / "tools/.local/godotsteam-editor/godot.exe")
    parser.add_argument("--iscc", type=Path, default=ROOT / "tools/.local/inno-setup/ISCC.exe")
    parser.add_argument("--package-only", action="store_true", help="Repackage an already audited payload")
    parser.add_argument("--verify-existing", action="store_true", help="Rerun every audit on an existing candidate before packaging")
    args = parser.parse_args()
    version = re.search(r'config/version="([^"]+)"', (ROOT / "project.godot").read_text(encoding="utf-8"))[1]
    if not re.fullmatch(r"\d+(?:\.\d+){0,3}", version):
        raise ValueError("The manually configured version must be numeric")
    stamp = datetime.now().strftime("%Y.%m.%d")
    name = f"NorthernLab-Playtest-{version}-{stamp}-win64"
    payload = ROOT / "build/windows-playtest"
    output = ROOT / "build/distribution"
    payload.mkdir(parents=True, exist_ok=True)
    output.mkdir(parents=True, exist_ok=True)
    exe = payload / "NorthernLab.exe"
    godot = str(args.godot.resolve())
    if not args.package_only:
        if exe.exists() and not args.verify_existing:
            raise RuntimeError("Candidate folder already contains a build. Preserve or move it before rebuilding.")
        if not args.verify_existing:
            run([godot, "--headless", "--editor", "--path", str(ROOT), "--import"], "import")
            run([godot, "--headless", "--path", str(ROOT), "--script", "tools/prepare_export_resources.gd"], "resources")
            run([godot, "--headless", "--path", str(ROOT), "--script", "tools/write_build_identity.gd"], "identity")
            run([godot, "--headless", "--path", str(ROOT), "--export-release", "Windows Playtest", str(exe)], "export", 600)
        (payload / "steam_appid.txt").write_text("480\n", encoding="ascii")
        shutil.copy2(ROOT / "game_actions_480.vdf", payload / "game_actions_480.vdf")
        run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(ROOT / "tools/tests/run_export_regressions.ps1"), "-Executable", str(exe)], "package-audit", 2400)
        run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(ROOT / "tools/tests/run_export_regressions.ps1"), "-Executable", str(exe), "-Graphical"], "graphical-audit", 900)
        smoke_data = ROOT / "tools/.local/playtest-build/startup-userdata"
        smoke_data.mkdir(parents=True, exist_ok=True)
        previous = {key: os.environ.get(key) for key in ("APPDATA", "LOCALAPPDATA")}
        try:
            os.environ.update(APPDATA=str(smoke_data), LOCALAPPDATA=str(smoke_data))
            run([str(exe), "--headless", "--", "--startup-check"], "release-startup", 60)
        finally:
            for key, value in previous.items():
                if value is None:
                    os.environ.pop(key, None)
                else:
                    os.environ[key] = value
        (payload / ".audited.json").write_text(json.dumps({"exe_sha256": digest(exe)}, indent=2))
    marker = payload / ".audited.json"
    if not marker.exists() or json.loads(marker.read_text())["exe_sha256"] != digest(exe):
        raise RuntimeError("Payload was not audited or its executable changed")
    shutil.copy2(ROOT / "tools/distribution/START_HERE.txt", payload / "START_HERE.txt")
    licenses = payload / "Licenses"
    for base in (ROOT / "assets", ROOT / "addons"):
        for source in base.rglob("*"):
            if source.is_file() and source.suffix.lower() in (".txt", ".md") and any(word in source.stem.lower() for word in ("license", "attribution", "credits", "ofl")):
                dest = licenses / source.relative_to(ROOT)
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, dest)
    shutil.copy2(ROOT / "assets/models/crafting/README.md", licenses / "Crafting-Attribution.md")
    godot_license = ROOT / "tools/distribution/Godot-LICENSE.txt"
    if not godot_license.exists():
        raise RuntimeError("Godot license text is required")
    shutil.copy2(godot_license, licenses / godot_license.name)
    shutil.copy2(ROOT / "tools/distribution/Godot-COPYRIGHT.txt", licenses / "Godot-COPYRIGHT.txt")
    identity = (ROOT / "network_build.cfg").read_text(encoding="utf-8")
    info = {"product": "NorthernLab Playtest", "version": version, "date": stamp, "platform": "Windows 10/11 x64", "configuration": "release", "steam_app_id": 480, "network_identity": re.search(r'identity="([^"]+)"', identity)[1], "files": {p.relative_to(payload).as_posix(): digest(p) for p in sorted(payload.rglob("*")) if p.is_file() and p.name not in ("BUILD_INFO.json", ".audited.json")}}
    (payload / "BUILD_INFO.json").write_text(json.dumps(info, ensure_ascii=False, indent=2), encoding="utf-8")
    run([str(args.iscc.resolve()), f"/DGameVersion={version}", f"/DPackageName={name}", f"/DPayloadDir={payload}", f"/DOutputDir={output}", str(ROOT / "tools/distribution/playtest.iss")], "installer", 600)
    archive = output / f"{name}-Portable.zip"
    print("portable", flush=True)
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as target:
        for source in sorted(payload.rglob("*")):
            if source.is_file() and source.name != ".audited.json":
                target.write(source, Path("NorthernLab Playtest") / source.relative_to(payload))
    files = [output / f"{name}-Setup.exe", archive]
    (output / f"{name}-SHA256.txt").write_text("".join(f"{digest(p)}  {p.name}\n" for p in files), encoding="utf-8")
    for path in files:
        print(f"READY {path} ({path.stat().st_size:,} bytes)")


if __name__ == "__main__":
    main()
