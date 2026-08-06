#!/usr/bin/env python3
"""Launch the zero-cost local training as a detached, logged process."""

from __future__ import annotations

import json
import os
import signal
import sys
import time
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
BUILD_DIR = SCRIPT_DIR / "build"
OUTPUT_DIR = BUILD_DIR / "training-full"
PID_PATH = BUILD_DIR / "training-full.pid"
LOG_PATH = BUILD_DIR / "training-full.log"
ERROR_PATH = BUILD_DIR / "training-full.err.log"
PYTHON = SCRIPT_DIR.parent / "02-coreml-latencia" / ".venv" / "bin" / "python"


def live_pid() -> int | None:
    if not PID_PATH.exists():
        return None
    try:
        pid = int(PID_PATH.read_text(encoding="utf-8").strip())
        os.kill(pid, 0)
        return pid
    except (ValueError, ProcessLookupError, PermissionError):
        return None


def training_command() -> list[str]:
    return [
        "/usr/bin/caffeinate",
        "-dimsu",
        str(PYTHON),
        str(SCRIPT_DIR / "train_plue.py"),
        "--output-dir",
        str(OUTPUT_DIR),
        "--epochs",
        "3",
        "--batch-size",
        "16",
        "--gradient-accumulation",
        "2",
        "--max-length",
        "256",
        "--learning-rate",
        "2e-5",
        "--weight-decay",
        "0.01",
        "--warmup-ratio",
        "0.10",
        "--seed",
        "42",
        "--log-every",
        "100",
        "--pad-to-multiple-of",
        "32",
        "--mps-empty-cache-every",
        "100",
        "--device",
        "mps",
        "--precision",
        "fp32",
    ]


def main() -> int:
    if not PYTHON.is_file():
        raise FileNotFoundError(f"Disposable Python environment not found: {PYTHON}")
    existing = live_pid()
    if existing is not None:
        print(json.dumps({"status": "already_running", "pid": existing}))
        return 0

    BUILD_DIR.mkdir(parents=True, exist_ok=True)
    read_fd, write_fd = os.pipe()
    first_child = os.fork()
    if first_child > 0:
        os.close(write_fd)
        payload = os.read(read_fd, 128).decode("ascii")
        os.close(read_fd)
        os.waitpid(first_child, 0)
        pid = int(payload)
        for _ in range(50):
            if live_pid() == pid:
                print(json.dumps({"status": "started", "pid": pid, "log": str(LOG_PATH)}))
                return 0
            time.sleep(0.1)
        raise RuntimeError("Detached process did not become observable")

    os.close(read_fd)
    os.setsid()
    second_child = os.fork()
    if second_child > 0:
        os._exit(0)

    pid = os.getpid()
    PID_PATH.write_text(f"{pid}\n", encoding="utf-8")
    os.write(write_fd, str(pid).encode("ascii"))
    os.close(write_fd)
    os.chdir(SCRIPT_DIR)
    os.umask(0o077)
    with open(os.devnull, "rb", buffering=0) as stdin, open(LOG_PATH, "wb", buffering=0) as stdout, open(
        ERROR_PATH, "wb", buffering=0
    ) as stderr:
        os.dup2(stdin.fileno(), sys.stdin.fileno())
        os.dup2(stdout.fileno(), sys.stdout.fileno())
        os.dup2(stderr.fileno(), sys.stderr.fileno())
        os.execv(training_command()[0], training_command())
    return 1


if __name__ == "__main__":
    signal.signal(signal.SIGHUP, signal.SIG_IGN)
    sys.exit(main())
