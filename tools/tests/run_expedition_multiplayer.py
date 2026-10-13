"""Test production expedition resume with two real ENet peers and isolated saves."""
from pathlib import Path
import argparse
import re
import socket
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--terminal", action="store_true", help="test terminals and shared quest key")
    parser.add_argument("--wiring", action="store_true", help="test physical breaker wiring and concurrent repair")
    options = parser.parse_args()
    label = "terminal" if options.terminal else "expedition"
    driver = "run_terminal_multiplayer.gd" if options.terminal else "run_expedition_multiplayer.gd"
    ready_marker = "HOST_READY_FOR_TERMINAL_CLIENT" if options.terminal else "HOST_READY_FOR_RESUME_CLIENT"
    result_marker = "TERMINAL COOP CHECKS" if options.terminal else "COOP SAVE CHECKS"
    if options.wiring:
        label = "wiring"
        driver = "run_wiring_multiplayer.gd"
        ready_marker = "HOST_READY_FOR_WIRING_CLIENT"
        result_marker = "WIRING COOP CHECKS"
    project = Path(__file__).resolve().parents[2]
    output = project / "tools/.local"
    output.mkdir(exist_ok=True)
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as temporary:
        temporary.bind(("127.0.0.1", 0))
        port = temporary.getsockname()[1]
    command = [str(output / "godotsteam-editor/godot.exe"), "--headless",
               "--path", str(project), "--script",
               "res://tools/tests/" + driver]
    logs = [output / f"{label}-coop-{side}.log" for side in ("host", "client")]
    for path in logs:
        path.unlink(missing_ok=True)
    processes = []
    try:
        host = subprocess.Popen(command + ["--log-file", str(logs[0]), "--",
                                "--host", f"--port={port}",
                                f"--save-root=user://{label}_coop_host_test"])
        processes.append(host)
        deadline = time.monotonic() + 35
        while time.monotonic() < deadline:
            text = logs[0].read_text(encoding="utf-8", errors="replace") if logs[0].exists() else ""
            if "SCRIPT ERROR:" in text or host.poll() is not None:
                raise RuntimeError(text)
            if ready_marker in text:
                break
            time.sleep(0.15)
        else:
            raise TimeoutError("host failed to resume")
        client = subprocess.Popen(command + ["--log-file", str(logs[1]), "--",
                                  f"--port={port}",
                                  f"--save-root=user://{label}_coop_client_test"])
        processes.append(client)
        for process in processes:
            process.wait(timeout=50)
        success = all(process.returncode == 0 for process in processes)
        for path in logs:
            text = path.read_text(encoding="utf-8", errors="replace")
            reports = re.findall(result_marker + r" \d+ FAILURES 0", text)
            errors = [line for line in text.splitlines() if line.startswith("ERROR:")
                      and "RID allocations" not in line and "resources still in use" not in line]
            success &= bool(reports) and "SCRIPT ERROR:" not in text and not errors and "FAIL " not in text
            print(path.name, reports[-1] if reports else text[-5000:])
            if errors:
                print("\n".join(errors))
        return 0 if success else 1
    finally:
        for process in processes:
            if process.poll() is None:
                process.kill()
                process.wait()


if __name__ == "__main__":
    raise SystemExit(main())
