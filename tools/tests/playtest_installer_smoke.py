"""Install the playtest into an isolated workspace folder, verify and uninstall.

Refuses to touch an existing installation registered for this app. Requires Windows.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time
import winreg


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("installer", type=Path)
    options = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    key_name = r"Software\Microsoft\Windows\CurrentVersion\Uninstall\{D9F859C5-5658-498B-9794-19C15B3B8B2C}_is1"
    for view in (winreg.KEY_WOW64_64KEY, winreg.KEY_WOW64_32KEY):
        try:
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, key_name, 0, winreg.KEY_READ | view):
                raise RuntimeError("Existing playtest installation found; refusing installation smoke test")
        except FileNotFoundError:
            pass
    work = root / "build" / ("installer-smoke-" + time.strftime("%Y%m%d-%H%M%S"))
    app = work / "app"
    userdata = work / "userdata"
    userdata.mkdir(parents=True)
    save = userdata / "Godot/app_userdata/NorthernLab/smoke-save-marker.txt"
    save.parent.mkdir(parents=True)
    save.write_text("preserve this progress", encoding="utf-8")
    subprocess.run([str(options.installer.resolve()), "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/NOICONS", "/TASKS=", f"/DIR={app}", f"/LOG={work / 'install.log'}"], check=True, timeout=180)
    info = json.loads((app / "BUILD_INFO.json").read_text(encoding="utf-8"))
    for name, expected in info["files"].items():
        with (app / name).open("rb") as stream:
            actual = hashlib.file_digest(stream, "sha256").hexdigest()
        if expected != actual:
            raise RuntimeError("Installed file differs: " + name)
    print("PASS all installed payload hashes match", flush=True)
    for mode, arguments in (("headless", ["--headless"]), ("graphical", ["--windowed", "--resolution", "1280x720"])):
        result = subprocess.run([str(app / "NorthernLab.exe"), *arguments, "--", "--startup-check"], cwd=app, env={**os.environ, "APPDATA": str(userdata), "LOCALAPPDATA": str(userdata)}, capture_output=True, timeout=60)
        (work / f"startup-{mode}.log").write_bytes(result.stdout + result.stderr)
        if result.returncode or b"PASS packaged executable" not in result.stdout:
            raise RuntimeError("Installed release startup failed; inspect " + str(work))
        print(f"PASS installed release menu and music startup ({mode})", flush=True)
    subprocess.run([str(app / "unins000.exe"), "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", f"/LOG={work / 'uninstall.log'}"], cwd=work, check=True, timeout=120)
    deadline = time.monotonic() + 30
    while (app / "NorthernLab.exe").exists() and time.monotonic() < deadline:
        time.sleep(.2)
    if (app / "NorthernLab.exe").exists() or save.read_text(encoding="utf-8") != "preserve this progress":
        raise RuntimeError("Uninstall did not remove game or changed external progress")
    print("PASS uninstall removes game and preserves external progress", flush=True)
    print("Installer smoke logs:", work)


if __name__ == "__main__":
    main()
