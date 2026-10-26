"""Exercise real host/client heavy carry RPCs using native players and isolated logs."""
from pathlib import Path
import socket
import subprocess
import time
import sys

root = Path(__file__).resolve().parents[2]
output = root / "tools/.local"
with socket.socket() as probe:
    probe.bind(("127.0.0.1", 0))
    port = probe.getsockname()[1]
command = [str(output / "godotsteam-editor/godot.exe"), "--headless", "--path", str(root), "--script", "tools/tests/run_heavy_carry_multiplayer.gd", "--", f"--port={port}"] + sys.argv[1:]
processes, streams = [], []
try:
    for side in ("host", "client"):
        stream = (output / f"heavy_carry-network-{side}.log").open("wb")
        streams.append(stream)
        processes.append(subprocess.Popen(command + (["--host"] if side == "host" else []), cwd=root, stdout=stream, stderr=stream))
        if side == "host":
            deadline = time.monotonic() + 30
            while time.monotonic() < deadline:
                text = (output / "heavy_carry-network-host.log").read_text(encoding="utf-8", errors="replace")
                if "HOST_READY_HEAVY" in text:
                    break
                if processes[0].poll() is not None or "SCRIPT ERROR" in text:
                    raise RuntimeError(text)
                time.sleep(.1)
            else:
                raise TimeoutError("Host startup")
    for process in processes:
        process.wait(timeout=50)
    for stream in streams:
        stream.close()
    success = all(p.returncode == 0 for p in processes)
    for side in ("host", "client"):
        text = (output / f"heavy_carry-network-{side}.log").read_text(encoding="utf-8", errors="replace")
        success &= "HEAVY NETWORK CHECKS" in text and "FAIL " not in text and "ERROR:" not in text
        print(side, text[-1200:])
    raise SystemExit(0 if success else 1)
finally:
    for process in processes:
        if process.poll() is None:
            process.kill()
            process.wait()
    for stream in streams:
        stream.close()
