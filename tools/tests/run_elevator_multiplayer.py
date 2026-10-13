"""Run real Godot peers with optional UDP latency, jitter and packet loss."""
import argparse
import heapq
from pathlib import Path
import random
import re
import socket
import subprocess
import threading
import time


class Proxy:
    def __init__(self, server_port, latency_ms, loss):
        self.server = ("127.0.0.1", server_port)
        self.delay = latency_ms / 1000
        self.loss = loss
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.socket.bind(("127.0.0.1", 0))
        self.socket.settimeout(0.005)
        self.port = self.socket.getsockname()[1]
        self.stop = threading.Event()
        self.thread = threading.Thread(target=self.run, daemon=True)
        self.thread.start()

    def run(self):
        rng = random.Random(424242)
        pending = []
        serial = 0
        client = None
        while not self.stop.is_set():
            now = time.monotonic()
            while pending and pending[0][0] <= now:
                _, _, data, destination = heapq.heappop(pending)
                self.socket.sendto(data, destination)
            try:
                data, address = self.socket.recvfrom(65535)
            # Windows reports ICMP "port unreachable" after a peer exits.
            except (socket.timeout, ConnectionResetError):
                continue
            if address == self.server:
                destination = client
            else:
                client = address
                destination = self.server
            if destination is None or rng.random() < self.loss:
                continue
            serial += 1
            jitter = rng.uniform(-self.delay * 0.25, self.delay * 0.25)
            heapq.heappush(pending, (time.monotonic() + self.delay + jitter,
                                   serial, data, destination))

    def close(self):
        self.stop.set()
        self.thread.join(timeout=1)
        self.socket.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--latency-ms", type=float, default=0,
                        help="one-way delay; jitter is +/-25%%")
    parser.add_argument("--loss", type=float, default=0,
                        help="datagram loss fraction, e.g. 0.05")
    parser.add_argument("--client-fps", type=int, default=60)
    args = parser.parse_args()
    if args.latency_ms < 0 or not 0 <= args.loss < 1 or args.client_fps <= 0:
        parser.error("invalid delay, loss or frame rate")
    project = Path(__file__).resolve().parents[2]
    output = project / "tools/.local"
    output.mkdir(exist_ok=True)
    # Ask the OS for an unused port rather than colliding with a game session.
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as temporary:
        temporary.bind(("127.0.0.1", 0))
        port = temporary.getsockname()[1]
    proxy = Proxy(port, args.latency_ms, args.loss)
    command = [str(project / "tools/.local/godotsteam-editor/godot.exe"),
               "--headless", "--path", str(project), "--script",
               "res://tools/tests/run_elevator_multiplayer.gd", "--"]
    processes = []
    label = "impaired" if args.latency_ms or args.loss else "local"
    logs = [output / f"elevator-network-{label}-{side}.log"
            for side in ("host", "client")]
    try:
        with logs[0].open("w", encoding="utf-8") as host_log, \
                logs[1].open("w", encoding="utf-8") as client_log:
            host = subprocess.Popen(command + ["--host", f"--port={port}"],
                                    stdout=host_log, stderr=subprocess.STDOUT)
            processes.append(host)
            deadline = time.monotonic() + 15
            while "HOST_READY_FOR_LATE_JOIN" not in logs[0].read_text(encoding="utf-8", errors="replace"):
                if host.poll() is not None or time.monotonic() > deadline:
                    raise RuntimeError("host did not start elevator test")
                time.sleep(0.05)
            time.sleep(1.0)
            client = subprocess.Popen(command + [f"--port={proxy.port}",
                                      f"--fps={args.client_fps}"],
                                      stdout=client_log, stderr=subprocess.STDOUT)
            processes.append(client)
            host.wait(timeout=90)
            client.wait(timeout=10)
        failed = any(process.returncode for process in processes)
        for log in logs:
            print(log.name)
            for line in log.read_text(encoding="utf-8", errors="replace").splitlines():
                if line.startswith("FAIL ") or re.search(r"RESULT FAILURES [1-9]", line) or "SCRIPT ERROR" in line or "Parse Error" in line:
                    failed = True
                    print(line)
                elif "METRICS" in line or "CHECKS" in line:
                    print(line)
                elif line.startswith("ERROR:") and not any(
                        known in line for known in ("RID allocations", "resources still in use at exit")):
                    failed = True
                    print(line)
        print("TRANSPORT", f"delay={args.latency_ms}ms loss={args.loss} client_fps={args.client_fps}")
        print("EXIT", [process.returncode for process in processes])
        return 1 if failed else 0
    finally:
        for process in processes:
            if process.poll() is None:
                process.kill()
                process.wait()
        proxy.close()


if __name__ == "__main__":
    raise SystemExit(main())
