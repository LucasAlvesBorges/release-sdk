#!/usr/bin/env python3
"""Bound one shell command without requiring GNU timeout.

The command is supplied through RELEASE_TIMEOUT_COMMAND so shell syntax stays intact and does not
need to be reconstructed from argv. Exit 124 means the deadline expired; 137 means the process
group ignored SIGTERM and required SIGKILL.
"""

from __future__ import annotations

import os
import signal
import subprocess
import sys


def main() -> int:
    if len(sys.argv) != 2 or not sys.argv[1].isdigit():
        print("usage: release-timeout.py <seconds>", file=sys.stderr)
        return 2
    timeout = int(sys.argv[1])
    command = os.environ.get("RELEASE_TIMEOUT_COMMAND", "")
    if not command:
        print("release-timeout: RELEASE_TIMEOUT_COMMAND is empty", file=sys.stderr)
        return 2

    process = subprocess.Popen(command, shell=True, start_new_session=True)
    try:
        return process.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=10)
            return 124
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
            return 137


if __name__ == "__main__":
    raise SystemExit(main())
