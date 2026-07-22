#!/usr/bin/env python3
"""Exercise native hxhx socket request output and failure isolation.

The fixture starts one native server, sends editor and compiler requests through
the public ``--connect`` client, and checks that compiler-owned output returns to
that client instead of leaking into the server process. A deliberately failing
compile is followed by another successful compile to prove that request failure
does not poison the long-lived process. Separate stdio processes prove that a
negative or oversized length receives a framed protocol error before allocation.
Both transports prove that an expired request returns a cancellation response
without stopping the server, then prove that an explicit shutdown response is
sent before the server exits successfully.
"""

from __future__ import annotations

import argparse
import re
import socket
import struct
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


def require_baseline_report(result: subprocess.CompletedProcess[str], label: str) -> int:
    text = result.stdout + result.stderr
    required = [
        "hxhx_server_report.semantic_cache=disabled",
        "hxhx_server_report.semantic_cache_hits=0",
        "hxhx_server_report.semantic_cache_entries=0",
        "hxhx_server_report.cancelled=",
        "hxhx_server_report.cleanup=ok",
        "hxhx_server_report.elapsed_ms=",
    ]
    for marker in required:
        if marker not in text:
            raise RuntimeError(f"{label} is missing baseline report marker {marker!r}: {text!r}")
    match = re.search(r"hxhx_server_report\.request_id=(\d+)", text)
    if match is None:
        raise RuntimeError(f"{label} is missing its request ID: {text!r}")
    return int(match.group(1))


def require_cancellation_report(result: subprocess.CompletedProcess[str], label: str) -> int:
    request_id = require_baseline_report(result, label)
    text = result.stdout + result.stderr
    required = [
        "request cancelled [deadline-exceeded] at request-dispatch",
        "hxhx_server_report.cancelled=1",
        "hxhx_server_report.cancellation_reason=deadline-exceeded",
        "hxhx_server_report.cancellation_stage=request-dispatch",
    ]
    for marker in required:
        if marker not in text:
            raise RuntimeError(f"{label} is missing cancellation marker {marker!r}: {text!r}")
    return request_id


def require_rejected_stdio_length(
    hxhx_bin: Path, output_path: Path, declared_length: int, expected: str
) -> None:
    result = subprocess.run(
        [str(hxhx_bin), "--hxhx-no-run", "--js", str(output_path), "--wait", "stdio"],
        input=struct.pack("<i", declared_length),
        capture_output=True,
        timeout=30,
        check=False,
    )
    if result.returncode == 0:
        raise RuntimeError(f"invalid stdio frame length {declared_length} unexpectedly succeeded")
    if result.stdout:
        raise RuntimeError(f"invalid stdio frame wrote unexpected stdout: {result.stdout!r}")
    if len(result.stderr) < 4:
        raise RuntimeError(f"invalid stdio frame omitted its response header: {result.stderr!r}")
    response_length = struct.unpack("<I", result.stderr[:4])[0]
    response = result.stderr[4:]
    if len(response) != response_length:
        raise RuntimeError(
            f"invalid stdio response length mismatch: header={response_length}, body={len(response)}"
        )
    text = response.decode("utf-8", errors="replace")
    if expected not in text or "\x02" not in text:
        raise RuntimeError(f"invalid stdio frame lacked its protocol error: {text!r}")


def require_stdio_shutdown(hxhx_bin: Path, output_path: Path) -> None:
    payload = b"--hxhx-server-control\nshutdown\n"
    result = subprocess.run(
        [str(hxhx_bin), "--hxhx-no-run", "--js", str(output_path), "--wait", "stdio"],
        input=struct.pack("<I", len(payload)) + payload,
        capture_output=True,
        timeout=30,
        check=False,
    )
    if result.returncode != 0 or result.stdout:
        raise RuntimeError(
            f"stdio shutdown failed (rc={result.returncode}, stdout={result.stdout!r}, stderr={result.stderr!r})"
        )
    if len(result.stderr) < 4:
        raise RuntimeError(f"stdio shutdown omitted its response header: {result.stderr!r}")
    response_length = struct.unpack("<I", result.stderr[:4])[0]
    response = result.stderr[4:]
    if len(response) != response_length:
        raise RuntimeError(
            f"stdio shutdown response length mismatch: header={response_length}, body={len(response)}"
        )
    if b"hxhx_server_control.shutdown=ok" not in response or b"\x02" in response:
        raise RuntimeError(f"stdio shutdown returned an unexpected response: {response!r}")
    if output_path.exists():
        raise RuntimeError("stdio shutdown unexpectedly produced target output")


def require_stdio_cancellation(hxhx_bin: Path, output_path: Path) -> None:
    payload = b"--hxhx-server-timeout-ms\n0\n-main\nNeverCompiled\n"
    result = subprocess.run(
        [
            str(hxhx_bin),
            "--hxhx-no-run",
            "--hxhx-server-report",
            "--js",
            str(output_path),
            "--wait",
            "stdio",
        ],
        input=struct.pack("<I", len(payload)) + payload,
        capture_output=True,
        timeout=30,
        check=False,
    )
    if result.returncode != 0 or result.stdout:
        raise RuntimeError(
            f"stdio cancellation failed (rc={result.returncode}, stdout={result.stdout!r}, stderr={result.stderr!r})"
        )
    if len(result.stderr) < 4:
        raise RuntimeError(f"stdio cancellation omitted its response header: {result.stderr!r}")
    response_length = struct.unpack("<I", result.stderr[:4])[0]
    response = result.stderr[4:]
    if len(response) != response_length:
        raise RuntimeError(
            f"stdio cancellation response length mismatch: header={response_length}, body={len(response)}"
        )
    required = [
        b"request cancelled [deadline-exceeded] at request-dispatch",
        b"hxhx_server_report.cancelled=1",
        b"hxhx_server_report.cleanup=ok",
        b"\x02",
    ]
    for marker in required:
        if marker not in response:
            raise RuntimeError(f"stdio cancellation omitted {marker!r}: {response!r}")
    if output_path.exists():
        raise RuntimeError("stdio cancellation unexpectedly produced target output")


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
    base_args = ["--hxhx-no-run", "--hxhx-server-report", "--js", str(artifact)]
    request_ids: List[int] = []

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
                    request_ids.append(require_baseline_report(last, "display request"))
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
            request_ids.append(require_baseline_report(first_success, "first ordinary socket compile"))
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

            first_artifact_bytes = artifact.read_bytes()
            cancelled = run_client(
                hxhx_bin,
                base_args,
                endpoint,
                [
                    "--hxhx-server-timeout-ms",
                    "0",
                    "-cp",
                    str(classpath),
                    "-main",
                    "SocketCompileMain",
                ],
            )
            if cancelled.returncode == 0:
                raise RuntimeError("expired socket request unexpectedly succeeded")
            request_ids.append(require_cancellation_report(cancelled, "expired socket request"))
            if not artifact.is_file() or artifact.read_bytes() != first_artifact_bytes:
                raise RuntimeError("expired socket request changed the last successful target artifact")

            artifact.unlink()
            expected_failure = run_client(
                hxhx_bin,
                base_args,
                endpoint,
                ["-cp", str(classpath), "-main", "MissingSocketMain"],
            )
            if expected_failure.returncode == 0:
                raise RuntimeError("missing-main socket request unexpectedly succeeded")
            request_ids.append(require_baseline_report(expected_failure, "missing-main socket request"))
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
            request_ids.append(require_baseline_report(second_success, "second ordinary socket compile"))
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

            shutdown = run_client(
                hxhx_bin,
                base_args,
                endpoint,
                ["--hxhx-server-control", "shutdown"],
            )
            require_success(shutdown, "socket server shutdown")
            request_ids.append(require_baseline_report(shutdown, "socket server shutdown"))
            if "hxhx_server_control.shutdown=ok" not in shutdown.stdout:
                raise RuntimeError(f"socket shutdown did not confirm the control request: {shutdown.stdout!r}")
            if request_ids != sorted(set(request_ids)):
                raise RuntimeError(f"server request IDs were not unique and increasing: {request_ids!r}")
            server.wait(timeout=5)
            if server.returncode != 0:
                raise RuntimeError(f"socket server exited with {server.returncode} after graceful shutdown")
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

    invalid_stdio_output = fixture_root / "invalid-stdio.js"
    require_rejected_stdio_length(hxhx_bin, invalid_stdio_output, -1, "negative request frame length")
    require_rejected_stdio_length(
        hxhx_bin, invalid_stdio_output, 64 * 1024 * 1024 + 1, "maximum is 67108864"
    )
    if invalid_stdio_output.exists():
        raise RuntimeError("rejected stdio frame unexpectedly produced target output")
    require_stdio_cancellation(hxhx_bin, fixture_root / "cancelled-stdio.js")
    require_stdio_shutdown(hxhx_bin, fixture_root / "shutdown-stdio.js")

    print("HXHX_NATIVE_SERVER_CLIENT_OUTPUT_FIXTURE:PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
