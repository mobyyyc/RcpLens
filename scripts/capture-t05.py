#!/usr/bin/env python3
"""Capture fictional native screens in the separate Debug preview store, then restore ordinary launch."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
ENV = {**os.environ, "DEVELOPER_DIR": "/Applications/Xcode.app/Contents/Developer"}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--simulator", default="50661E83-1F58-466B-99F0-9DC517D8EC82")
    parser.add_argument("--output-directory", type=Path, default=ROOT / "docs/evidence/t05")
    args = parser.parse_args()
    args.output_directory.mkdir(parents=True, exist_ok=True)
    def command(parts):
        result = subprocess.run(parts, env=ENV, capture_output=True)
        if result.returncode: raise RuntimeError("synthetic_preview_tool_failed")
        return result.stdout.decode().strip()
    sim = args.simulator
    container = Path(command(["xcrun", "simctl", "get_app_container", sim, "com.mobyyyc.RcpLens", "data"]))
    scenarios = [("native-" + mode, mode, ["--t05-light"]) for mode in ["wallet", "detail", "review", "source", "library"]]
    scenarios += [("native-dark-wallet", "wallet", []), ("native-large-text", "review", ["--t05-large-text", "--t05-reduce-motion", "--t05-opaque", "--t05-contrast"]), ("native-empty", "empty", []), ("native-light-empty", "empty", ["--t05-light"])]
    try:
        for name, mode, flags in scenarios:
            ready = container / "Library/Caches/t05-synthetic-preview.json"
            ready.unlink(missing_ok=True)
            command(["xcrun", "simctl", "launch", "--terminate-running-process", sim, "com.mobyyyc.RcpLens", "--t05-synthetic-preview", mode] + flags)
            for _ in range(300):
                if ready.exists(): break
                time.sleep(.1)
            if not ready.exists(): raise RuntimeError("synthetic_preview_not_ready")
            time.sleep(1.5)
            command(["xcrun", "simctl", "io", sim, "screenshot", str(args.output_directory / (name + ".png"))])
            print(json.dumps({"synthetic_screen": mode, "captured": True}), flush=True)
    finally:
        command(["xcrun", "simctl", "launch", "--terminate-running-process", sim, "com.mobyyyc.RcpLens"])

if __name__ == "__main__":
    try: main()
    except Exception: raise SystemExit("Synthetic capture failed; no receipt details printed")
