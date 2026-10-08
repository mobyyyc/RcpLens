#!/usr/bin/env python3
"""Record explicit fictional paper transitions, then restore ordinary launch."""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import time

ENV = {**os.environ, "DEVELOPER_DIR": "/Applications/Xcode.app/Contents/Developer"}
ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--simulator", default="50661E83-1F58-466B-99F0-9DC517D8EC82")
    parser.add_argument("--output-directory", type=Path, default=ROOT / "docs/evidence/t05-wallet-motion")
    args = parser.parse_args()
    args.output_directory.mkdir(parents=True, exist_ok=True)

    def command(parts):
        result = subprocess.run(parts, env=ENV, capture_output=True)
        if result.returncode: raise RuntimeError("synthetic_motion_tool_failed")
        return result.stdout.decode().strip()

    sim = args.simulator
    recorder = None
    try:
        # Enter an explicitly isolated fictional store before recording any pixels.
        container = Path(command(["xcrun", "simctl", "get_app_container", sim, "com.mobyyyc.RcpLens", "data"]))
        ready = container / "Library/Caches/t05-synthetic-preview.json"
        ready.unlink(missing_ok=True)
        command(["xcrun", "simctl", "launch", "--terminate-running-process", sim, "com.mobyyyc.RcpLens", "--t05-synthetic-preview", "wallet", "--t05-light"])
        for _ in range(300):
            if ready.exists(): break
            time.sleep(.1)
        if not ready.exists(): raise RuntimeError("synthetic_motion_not_ready")
        recorder = subprocess.Popen(["xcrun", "simctl", "io", sim, "recordVideo", "--codec=h264", "--force", str(args.output_directory / "paper-motion.mp4")], env=ENV, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(.5)
        ready.unlink(missing_ok=True)
        command(["xcrun", "simctl", "launch", "--terminate-running-process", sim, "com.mobyyyc.RcpLens", "--t05-synthetic-preview", "motion", "--t05-light"])
        for _ in range(300):
            if ready.exists(): break
            time.sleep(.1)
        if not ready.exists(): raise RuntimeError("synthetic_motion_not_ready")
        time.sleep(8)
        recorder.send_signal(signal.SIGINT)
        recorder.wait(timeout=15)
        recorder = None
        print(json.dumps({"fictionalMotionRecorded": True}))
    finally:
        if recorder:
            recorder.send_signal(signal.SIGINT)
            recorder.wait(timeout=15)
        command(["xcrun", "simctl", "launch", "--terminate-running-process", sim, "com.mobyyyc.RcpLens"])


if __name__ == "__main__":
    try: main()
    except Exception: raise SystemExit("Fictional motion capture failed; no receipt details printed")
