#!/usr/bin/env python3
"""Observe SDK versus project retention with pinned upstream Haxe, without modifying the SDK."""

import os
from itertools import product
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
HAXE = ROOT / "node_modules/.bin/haxe"
FIXTURE = ROOT / "test/fixtures/js_feature_intrinsic"


def run(arguments, *, env=None, expected_status=0):
    result = subprocess.run(arguments, cwd=ROOT, env=env, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60)
    if result.returncode != expected_status:
        raise RuntimeError(f"command failed: {arguments}\n{result.stdout}{result.stderr}")
    return result.stdout + result.stderr


def main():
    if run([HAXE, "--version"]).strip() != "4.3.7":
        raise RuntimeError("feature-origin contract requires Haxe 4.3.7")
    lookup = run([HAXE, "-v", "--no-output", "-main", "FeatureOriginMissing"], expected_status=1)
    providers = set(re.findall(r"^Parsed (.*[/\\]StdTypes\.hx)$", lookup, re.MULTILINE))
    if len(providers) != 1:
        raise RuntimeError("cannot identify the exact upstream StdTypes provider")
    standard_root = Path(providers.pop()).parent
    # The Lix launcher sets its own SDK environment. Invoke the verified binary
    # beside that SDK so this observer can select an isolated standard-library root.
    compiler = standard_root.parent / ("haxe.exe" if os.name == "nt" else "haxe")
    if not compiler.is_file() or run([compiler, "--version"]).strip() != "4.3.7":
        raise RuntimeError("cannot verify the compiler beside the selected SDK")
    (ROOT / ".tmp").mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="feature-origin-", dir=ROOT / ".tmp") as temporary:
        work = Path(temporary)
        sdk = work / "std"
        sdk.mkdir()
        # The installed SDK remains read-only. Only the new fixture is authored here.
        for entry in standard_root.iterdir():
            (sdk / entry.name).symlink_to(entry, target_is_directory=entry.is_dir())
        shutil.copyfile(FIXTURE / "origin_lib/FeatureOriginLibrary.hx", sdk / "FeatureOriginLibrary.hx")
        environment = os.environ.copy()
        environment["HAXE_STD_PATH"] = str(sdk)
        failures = []
        for mode in ("full", "std", "no"):
            for source, called in product(("sdk", "project", "explicit-sdk"), (False, True)):
                case = f"{mode}:{source}:called={called}"
                script = work / f"{mode}-{source}-{called}.js"
                arguments = [compiler, "-cp", FIXTURE]
                if source == "project":
                    arguments += ["-cp", FIXTURE / "origin_lib"]
                elif source == "explicit-sdk":
                    arguments += ["-cp", sdk]
                arguments += ["-main", "FeatureOrigin", "-js", script, "-dce", mode]
                if called:
                    arguments += ["-D", "feature_origin_call"]
                run(arguments, env=environment)
                output = run(["node", script])
                observed = [re.sub(r"^.*\.hx:\d+: ", "", line) for line in output.strip().splitlines()]
                unused_emitted = "FeatureOriginLibrary.unused =" in script.read_text()
                print(f"JS_FEATURE_ORIGIN_OBSERVED:{case}:{observed}:unused_emitted={unused_emitted}", flush=True)
                # Emission alone does not activate a definition: no-DCE SDK
                # methods remain emitted but do not enable this unused feature.
                enabled = called or (source == "project" and mode != "full")
                expected = ["library:on" if enabled else "library:off", "used"]
                if observed != expected:
                    failures.append(f"{case}: {observed}, expected {expected}")
                else:
                    print(f"JS_FEATURE_ORIGIN:{case}:PASS", flush=True)
        if failures:
            raise RuntimeError("feature origin differs: " + "; ".join(failures))
    print("JS_FEATURE_ORIGIN_CONTRACT:PASS", flush=True)


if __name__ == "__main__":
    main()
