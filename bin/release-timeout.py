#!/usr/bin/env python3
"""Run one test command under a user-wide queue and an execution-only deadline.

The command comes from RELEASE_TIMEOUT_COMMAND so shell syntax is preserved. The advisory lock is
owned by this process, so the kernel releases a stale lock after a crash. Only the process group
created for the command is signalled; an external runner can leave work in a remote daemon after
its local client exits.
"""

from __future__ import annotations

import os
import signal
import subprocess
import sys
import time
from pathlib import Path

import fcntl


class QueueCancelled(Exception):
    """A caller cancelled while waiting for a test slot."""


class RunCancelled(Exception):
    """A caller cancelled an owned test command."""


def metadata_path() -> Path | None:
    value = os.environ.get("RELEASE_TEST_META_FILE", "")
    return Path(value) if value else None


def write_metadata(**values: object) -> None:
    path = metadata_path()
    if path is not None:
        path.write_text("".join(f"{key}={value}\n" for key, value in values.items()), encoding="utf-8")


def lock_path() -> Path:
    configured = os.environ.get("RELEASE_TEST_LOCK_PATH", "")
    if configured:
        return Path(configured)
    return Path("/tmp") / f"release-sdk-test-{os.getuid()}.lock"


def elapsed_seconds(started: float) -> int:
    return max(0, int(time.monotonic() - started))


def process_group_exists(group_id: int) -> bool:
    try:
        os.killpg(group_id, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def terminate_owned_group(process: subprocess.Popen[object], group_id: int) -> None:
    if process.poll() is not None and not process_group_exists(group_id):
        return
    try:
        os.killpg(group_id, signal.SIGTERM)
    except ProcessLookupError:
        return


def stop_owned_group(process: subprocess.Popen[object], group_id: int) -> bool:
    """Terminate only the process group created for this command, then escalate after grace."""
    terminate_owned_group(process, group_id)
    grace_deadline = time.monotonic() + 10
    while time.monotonic() < grace_deadline:
        process.poll()
        if not process_group_exists(group_id):
            process.wait()
            return True
        time.sleep(0.05)
    try:
        os.killpg(group_id, signal.SIGKILL)
    except ProcessLookupError:
        return True
    except PermissionError:
        return False
    process.wait()
    return True


def wait_for_owned_group(process: subprocess.Popen[object], group_id: int, timeout: int) -> tuple[int, bool]:
    """Wait for the shell and descendants; the deadline starts after queue acquisition."""
    deadline = time.monotonic() + timeout if timeout else None
    while True:
        return_code = process.poll()
        if return_code is not None and not process_group_exists(group_id):
            return normalize_return_code(return_code), False
        if deadline is not None and time.monotonic() >= deadline:
            return (124 if stop_owned_group(process, group_id) else 137), True
        time.sleep(0.05)


def normalize_return_code(return_code: int) -> int:
    return 128 + -return_code if return_code < 0 else return_code


def main() -> int:
    if len(sys.argv) != 2 or not sys.argv[1].isdigit():
        print("usage: release-timeout.py <seconds>", file=sys.stderr)
        return 2
    timeout = int(sys.argv[1])
    command = os.environ.get("RELEASE_TIMEOUT_COMMAND", "")
    if not command:
        print("release-timeout: RELEASE_TIMEOUT_COMMAND is empty", file=sys.stderr)
        return 2

    queue_started = time.monotonic()
    lock_file = lock_path().open("a+", encoding="utf-8")

    def cancel_queue(_signal: int, _frame: object) -> None:
        raise QueueCancelled

    previous_int = signal.signal(signal.SIGINT, cancel_queue)
    previous_term = signal.signal(signal.SIGTERM, cancel_queue)
    try:
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
    except QueueCancelled:
        write_metadata(
            TEST_QUEUE_STATUS="cancelled",
            TEST_QUEUE_WAIT=elapsed_seconds(queue_started),
            TEST_RUN_ELAPSED=0,
            TEST_TIMED_OUT="false",
        )
        return 130
    finally:
        signal.signal(signal.SIGINT, previous_int)
        signal.signal(signal.SIGTERM, previous_term)

    queue_wait = elapsed_seconds(queue_started)
    run_started = time.monotonic()
    # The command inherits this fd. If this supervisor is SIGKILLed, the kernel keeps the flock
    # until its surviving local descendants exit instead of admitting another test concurrently.
    process = subprocess.Popen(
        command,
        shell=True,
        start_new_session=True,
        pass_fds=(lock_file.fileno(),),
    )
    process_group = os.getpgid(process.pid)
    cancelled = False

    def cancel_run(_signal: int, _frame: object) -> None:
        raise RunCancelled

    previous_int = signal.signal(signal.SIGINT, cancel_run)
    previous_term = signal.signal(signal.SIGTERM, cancel_run)
    try:
        return_code, timed_out = wait_for_owned_group(process, process_group, timeout)
    except (KeyboardInterrupt, RunCancelled):
        cancelled = True
        stop_owned_group(process, process_group)
        return_code = 130
        timed_out = False
    finally:
        signal.signal(signal.SIGINT, previous_int)
        signal.signal(signal.SIGTERM, previous_term)
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
        lock_file.close()

    if cancelled:
        return_code = 130
    write_metadata(
        TEST_QUEUE_STATUS="acquired",
        TEST_QUEUE_WAIT=queue_wait,
        TEST_RUN_ELAPSED=elapsed_seconds(run_started),
        TEST_TIMED_OUT=str(timed_out).lower(),
    )
    return return_code


if __name__ == "__main__":
    raise SystemExit(main())
