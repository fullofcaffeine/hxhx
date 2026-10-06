#!/usr/bin/env python3
"""Run independent Haxe exception contracts and retain every command's evidence.

The caller's working directory selects its haxelib scope. C++ programs compile
sequentially into one output directory so hxcpp can reuse native runtime objects.
Expected output is checked in; this runner never records or updates expectations.
"""

import argparse
import difflib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys


FIXTURE = Path(__file__).resolve().parent
PROGRAMS = [
    ("Main", "expected.stdout"),
    ("NumericCatchMain", "numeric.{target}.stdout"),
    ("WrapperCatchMain", "wrapper.{target}.stdout"),
    ("RuntimeBoundaryCatchMain", "runtime-boundary.expected.stdout"),
]


def run(command, output, name, receipts):
    """Keep stdout, stderr, status, and the exact command, including failed compiles."""
    stdout = output / (name + ".stdout")
    stderr = output / (name + ".stderr")
    with stdout.open("wb") as out, stderr.open("wb") as err:
        process = subprocess.Popen(command, stdout=out, stderr=err, start_new_session=True)
        try:
            status = process.wait(timeout=180)
        except subprocess.TimeoutExpired:
            # The owned session includes haxelib and native compiler descendants.
            # Terminating only Haxe would leave its build running after a timeout.
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
            status = "timeout"
    receipts.append({"command": command, "status": status, "stdout": str(stdout), "stderr": str(stderr)})
    (output / "commands.json").write_text(json.dumps(receipts, indent=2) + "\n")
    return status, stdout, stderr


def require_success(result):
    status, stdout, stderr = result
    if status != 0:
        raise RuntimeError(f"Command failed ({status}); inspect {stdout} and {stderr}")
    return stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", choices=["eval", "neko", "cpp"], required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    receipts = []
    version = require_success(run(["haxe", "--version"], output, "haxe-version", receipts)).read_text().strip()
    if version != "4.3.7":
        raise RuntimeError(f"This compatibility contract requires Haxe 4.3.7, found {version}")
    if args.target == "cpp":
        paths = require_success(run(["haxelib", "path", "hxcpp"], output, "hxcpp-path", receipts)).read_text().splitlines()
        manifests = [Path(path) / "haxelib.json" for path in paths if path and not path.startswith("-")]
        versions = [json.loads(path.read_text())["version"] for path in manifests if path.is_file()]
        if versions != ["4.3.2"]:
            raise RuntimeError(f"This native expectation requires hxcpp 4.3.2 in the caller's scope, found {versions}")

    for program, expected_name in PROGRAMS:
        base = ["haxe", "-cp", str(FIXTURE / "src"), "-main", program]
        if args.target == "eval":
            actual = require_success(run(base + ["--interp"], output, program, receipts))
        elif args.target == "neko":
            artifact = output / (program + ".n")
            require_success(run(base + ["-neko", str(artifact)], output, program + ".build", receipts))
            actual = require_success(run(["neko", str(artifact)], output, program, receipts))
        else:
            artifact = output / "cpp"
            require_success(run(base + ["-cpp", str(artifact)], output, program + ".build", receipts))
            actual = require_success(run([str(artifact / program)], output, program, receipts))
        expected = FIXTURE / expected_name.format(target=args.target)
        if actual.read_bytes() != expected.read_bytes():
            difference = "".join(difflib.unified_diff(expected.read_text().splitlines(True), actual.read_text().splitlines(True),
                                                    fromfile=str(expected), tofile=str(actual)))
            raise RuntimeError("Upstream behavior changed:\n" + difference)
        print(f"UPSTREAM_CATCH_CONTRACT:PASS {args.target} {program}", flush=True)

    rejected = ["haxe", "-cp", str(FIXTURE / "rejected"), "-main", "RejectedNumericCatchOrderMain"]
    flags = {"eval": ["--interp"], "neko": ["-neko", str(output / "rejected.n")],
             "cpp": ["-cpp", str(output / "rejected-cpp"), "--no-output"]}[args.target]
    status, _, diagnostic = run(rejected + flags, output, "rejected-order", receipts)
    if status == 0 or status == "timeout" or "Int can be caught to Float" not in diagnostic.read_text():
        raise RuntimeError(f"Expected the upstream unreachable-handler diagnostic; inspect {diagnostic}")
    print(f"UPSTREAM_CATCH_ORDER_REJECTION:PASS {args.target}", flush=True)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
