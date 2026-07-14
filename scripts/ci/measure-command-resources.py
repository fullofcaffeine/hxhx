#!/usr/bin/env python3
"""Run one command and record elapsed time plus OS-reported child peak RSS.

The helper is intentionally separate from shell orchestration. It always writes
its small JSON record, including failures, and then returns the measured
command's exit status. On macOS ``ru_maxrss`` is bytes; on Linux it is KiB.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import platform
import resource
import subprocess
import sys
import time
from typing import Sequence


SCHEMA = "hxhx.command-resource-sample.v1"
RSS_SCOPE = (
    "OS ru_maxrss for the completed build command child hierarchy; "
    "not simultaneous whole-machine or process-tree-sum memory"
)


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def normalized_rss_kb(raw_value: int) -> int:
    if platform.system() == "Darwin":
        return int(raw_value / 1024)
    return int(raw_value)


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cwd", required=True)
    parser.add_argument("--stdout", required=True)
    parser.add_argument("--stderr", required=True)
    parser.add_argument("--json-out", required=True)
    parser.add_argument("--label", required=True)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    if args.command and args.command[0] == "--":
        args.command = args.command[1:]
    if not args.command:
        parser.error("a command is required after --")
    return args


def main(argv: Sequence[str]) -> int:
    args = parse_args(argv)
    cwd = Path(args.cwd).resolve()
    stdout_path = Path(args.stdout).resolve()
    stderr_path = Path(args.stderr).resolve()
    json_path = Path(args.json_out).resolve()
    for output in (stdout_path, stderr_path, json_path):
        output.parent.mkdir(parents=True, exist_ok=True)

    started_at = utc_now()
    started = time.perf_counter()
    exit_code = 127
    launch_error = None
    with stdout_path.open("w", encoding="utf-8") as stdout_handle, stderr_path.open(
        "w", encoding="utf-8"
    ) as stderr_handle:
        try:
            process = subprocess.run(
                args.command,
                cwd=cwd,
                stdout=stdout_handle,
                stderr=stderr_handle,
                check=False,
            )
            exit_code = process.returncode
            if exit_code < 0:
                exit_code = 128 + abs(exit_code)
        except OSError as error:
            launch_error = str(error)
            stderr_handle.write(f"measure-command-resources: {error}\n")

    ended = time.perf_counter()
    usage = resource.getrusage(resource.RUSAGE_CHILDREN)
    payload = {
        "schema": SCHEMA,
        "label": args.label,
        "command": args.command,
        "started_at": started_at,
        "ended_at": utc_now(),
        "elapsed_ms": int(round((ended - started) * 1000)),
        "peak_child_rss_kb": normalized_rss_kb(usage.ru_maxrss),
        "rss_scope": RSS_SCOPE,
        "exit_code": exit_code,
        "launch_error": launch_error,
    }
    json_path.write_text(f"{json.dumps(payload, indent=2)}\n", encoding="utf-8")
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
