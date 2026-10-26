"""Save a live ENet team, close both processes, resume from disk in two new processes."""
from pathlib import Path
import socket
import subprocess
import time
import re


def main():
    project = Path(__file__).resolve().parents[2]
    output = project / "tools/.local"
    namespace = f"expedition_restart_{time.time_ns()}"
    command = [str(output / "godotsteam-editor/godot.exe"), "--headless", "--path", str(project),
               "--script", "res://tools/tests/run_expedition_restart_multiplayer.gd"]
    for phase in ("write", "read"):
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as temporary:
            temporary.bind(("127.0.0.1", 0))
            port = temporary.getsockname()[1]
        extra = ["--read-back"] if phase == "read" else []
        processes, streams, logs = [], [], []
        try:
            for side in ("host", "client"):
                log = output / f"restart-{phase}-{side}.log"
                std = output / f"restart-{phase}-{side}.stdio.log"
                log.unlink(missing_ok=True)
                logs.append(log)
                stream = std.open("w", encoding="utf-8")
                streams.append(stream)
                args = command + ["--log-file", str(log), "--", f"--port={port}",
                                  f"--save-root=user://{namespace}_{side}"] + extra
                if side == "host":
                    args.append("--host")
                processes.append(subprocess.Popen(args, stdout=stream, stderr=subprocess.STDOUT))
                if side == "host":
                    deadline = time.monotonic() + 45
                    while time.monotonic() < deadline:
                        text = log.read_text(encoding="utf-8", errors="replace") if log.exists() else ""
                        if "RESTART_HOST_READY" in text:
                            break
                        if "SCRIPT ERROR:" in text or processes[0].poll() is not None:
                            raise RuntimeError(text[-5000:] or std.read_text(encoding="utf-8", errors="replace"))
                        time.sleep(.15)
                    else:
                        raise TimeoutError("host did not finish loading")
            for process in processes:
                process.wait(timeout=65)
            for process, log in zip(processes, logs):
                text = log.read_text(encoding="utf-8", errors="replace")
                reports = re.findall(r"RESTART COOP CHECKS \d+ FAILURES 0", text)
                print(log.name, reports[-1] if reports else text[-6000:], flush=True)
                if process.returncode or not reports or "ERROR:" in text or "FAIL " in text:
                    raise RuntimeError(text[-6000:])
        finally:
            for process in processes:
                if process.poll() is None:
                    process.kill()
                    process.wait()
            for stream in streams:
                stream.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
