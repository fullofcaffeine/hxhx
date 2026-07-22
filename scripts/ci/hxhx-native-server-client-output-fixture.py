#!/usr/bin/env python3
"""Exercise native hxhx socket request output and failure isolation.

The fixture starts one native server, sends editor and compiler requests through
the public ``--connect`` client, and checks that compiler-owned output returns to
that client instead of leaking into the server process. A deliberately failing
compile is followed by another successful compile to prove that request failure
does not poison the long-lived process.
"""

from __future__ import annotations

import argparse
import os
import socket
import subprocess
import sys
import time
from pathlib import Path
from typing import List, Optional


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--hxhx-bin", required=True, type=Path)
    parser.add_argument("--tmpdir", required=True, type=Path)
    return parser.parse_args()


def reserve_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        probe.bind(("127.0.0.1", 0))
        return int(probe.getsockname()[1])


def run_client(hxhx_bin: Path, base_args: List[str], endpoint: str, request_args: List[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [str(hxhx_bin), *base_args, "--connect", endpoint, *request_args],
        capture_output=True,
        text=True,
        timeout=90,
        check=False,
    )


def require_success(result: subprocess.CompletedProcess[str], label: str) -> None:
    if result.returncode != 0:
        raise RuntimeError(
            f"{label} failed (rc={result.returncode}, stdout={result.stdout!r}, stderr={result.stderr!r})"
        )


def main() -> int:
    args = parse_args()
    hxhx_bin = args.hxhx_bin.resolve()
    tmpdir = args.tmpdir.resolve()
    fixture_root = tmpdir / "native-server-client-output"
    classpath = fixture_root / "src"
    classpath.mkdir(parents=True, exist_ok=True)
    (classpath / "DisplayMain.hx").write_text(
        "class DisplayMain { static function main() {} }\n", encoding="utf-8"
    )
    (classpath / "SocketCompileMain.hx").write_text(
        'class SocketCompileMain { static function main() { Sys.println("socket-compile-ok"); } }\n',
        encoding="utf-8",
    )
    display_source = classpath / "DisplayMain.hx"
    out_dir = fixture_root / "out"
    artifact = out_dir / "main.js"
    server_stdout_path = fixture_root / "server.stdout"
    server_stderr_path = fixture_root / "server.stderr"

    endpoint = f"127.0.0.1:{reserve_port()}"
    base_args = ["--hxhx-no-run", "--js", str(artifact)]

    test_error: Optional[BaseException] = None
    server_stdout = ""
    server_stderr = ""
    with server_stdout_path.open("w+", encoding="utf-8") as server_stdout_file, server_stderr_path.open(
        "w+", encoding="utf-8"
    ) as server_stderr_file:
        server = subprocess.Popen(
            [str(hxhx_bin), *base_args, "--wait", endpoint],
            stdout=server_stdout_file,
            stderr=server_stderr_file,
            text=True,
        )
        try:
            last: Optional[subprocess.CompletedProcess[str]] = None
            for _ in range(80):
                time.sleep(0.1)
                last = run_client(
                    hxhx_bin,
                    base_args,
                    endpoint,
                    ["--display", f"{display_source}@0@diagnostics", "-cp", str(classpath), "--no-output"],
                )
                if last.returncode == 0:
                    if '[{"diagnostics":[]}]' not in last.stderr:
                        raise RuntimeError(f"unexpected display response: {last.stderr!r}")
                    break
            else:
                raise RuntimeError(
                    "connect request never succeeded "
                    f"(last rc={last.returncode if last else '?'}, stderr={last.stderr if last else ''!r})"
                )

            first_success = run_client(
                hxhx_bin,
                base_args,
                endpoint,
                ["-cp", str(classpath), "-main", "SocketCompileMain"],
            )
            require_success(first_success, "first ordinary socket compile")
            if "resolved_modules=" not in first_success.stdout or "stage3=ok" not in first_success.stdout:
                raise RuntimeError(f"compiler progress did not reach the first client: {first_success.stdout!r}")
            if not artifact.is_file():
                raise RuntimeError(f"first ordinary socket compile did not create {artifact}")

            first_run = subprocess.run(
                ["node", str(artifact)], capture_output=True, text=True, timeout=30, check=False
            )
            require_success(first_run, "first socket-generated program")
            if first_run.stdout.strip() != "socket-compile-ok":
                raise RuntimeError(f"unexpected first generated-program output: {first_run.stdout!r}")

            artifact.unlink()
            expected_failure = run_client(
                hxhx_bin,
                base_args,
                endpoint,
                ["-cp", str(classpath), "-main", "MissingSocketMain"],
            )
            if expected_failure.returncode == 0:
                raise RuntimeError("missing-main socket request unexpectedly succeeded")
            failure_text = expected_failure.stdout + expected_failure.stderr
            if "resolve failed" not in failure_text or "MissingSocketMain" not in failure_text:
                raise RuntimeError(f"missing-main diagnostic did not reach its client: {failure_text!r}")
            if artifact.exists():
                raise RuntimeError("failed socket request unexpectedly produced the target artifact")

            second_success = run_client(
                hxhx_bin,
                base_args,
                endpoint,
                ["-cp", str(classpath), "-main", "SocketCompileMain"],
            )
            require_success(second_success, "second ordinary socket compile")
            if "resolved_modules=" not in second_success.stdout or "stage3=ok" not in second_success.stdout:
                raise RuntimeError(f"compiler progress did not reach the second client: {second_success.stdout!r}")
            if not artifact.is_file():
                raise RuntimeError(f"second ordinary socket compile did not recreate {artifact}")

            second_run = subprocess.run(
                ["node", str(artifact)], capture_output=True, text=True, timeout=30, check=False
            )
            require_success(second_run, "second socket-generated program")
            if second_run.stdout.strip() != "socket-compile-ok":
                raise RuntimeError(f"unexpected second generated-program output: {second_run.stdout!r}")
        except BaseException as error:
            test_error = error
        finally:
            if server.poll() is None:
                server.terminate()
            try:
                server.wait(timeout=5)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait(timeout=5)
            server_stdout_file.seek(0)
            server_stderr_file.seek(0)
            server_stdout = server_stdout_file.read()
            server_stderr = server_stderr_file.read()

    if test_error is not None:
        raise RuntimeError(
            f"{test_error}\nserver stdout={server_stdout!r}\nserver stderr={server_stderr!r}"
        ) from test_error
    if server_stdout or server_stderr:
        raise RuntimeError(
            "compiler-owned request output leaked into the server process "
            f"(stdout={server_stdout!r}, stderr={server_stderr!r})"
        )

    print("HXHX_NATIVE_SERVER_CLIENT_OUTPUT_FIXTURE:PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
