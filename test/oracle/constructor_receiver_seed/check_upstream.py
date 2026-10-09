"""Verify retained receiver observations through the public Haxe 4.3.7 CLI."""
import hashlib
import json
import pathlib
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parent
output = pathlib.Path(sys.argv[1]).resolve()
output.mkdir(parents=True, exist_ok=True)
version = subprocess.run(["haxe", "--version"], text=True, capture_output=True, timeout=15)
if version.returncode != 0 or version.stdout.strip() != "4.3.7":
    raise SystemExit("This observation corpus requires upstream Haxe 4.3.7")
results = []
failures = []
for name in ["primitive_capture", "array_capture", "nullable_transport"]:
    source_root = root / name
    source = (source_root / "Main.hx").read_bytes()
    expected = (source_root / "expected.stdout").read_text()
    for target in ["eval", "neko"]:
        artifact = output / (name + ".n")
        command = ["haxe", "-cp", str(source_root), "-main", "Main"]
        command += ["--interp"] if target == "eval" else ["--neko", str(artifact)]
        compiled = subprocess.run(command, text=True, capture_output=True, timeout=30)
        steps = [{"kind": "compile-and-run" if target == "eval" else "compile",
                  "command": command, "exit": compiled.returncode,
                  "stdout": compiled.stdout, "stderr": compiled.stderr}]
        runtime_command = None
        executed = compiled if target == "eval" else None
        if target == "neko" and compiled.returncode == 0:
            runtime_command = ["neko", str(artifact)]
            executed = subprocess.run(runtime_command, text=True, capture_output=True, timeout=30)
            steps.append({"kind": "run", "command": runtime_command, "exit": executed.returncode,
                          "stdout": executed.stdout, "stderr": executed.stderr})
        matched = (compiled.returncode == 0 and executed is not None
                   and executed.returncode == 0 and executed.stdout == expected)
        warning = "(WVarInit)" in compiled.stderr
        if not matched or warning != (name == "primitive_capture"):
            failures.append(name + "/" + target)
        results.append({
            "case": name, "target": target, "haxe_version": version.stdout.strip(),
            "source_sha256": hashlib.sha256(source).hexdigest(), "steps": steps,
            "expected_stdout": expected, "stdout_matched": matched,
            "initialization_warning": warning,
        })
        (output / "results.json").write_text(json.dumps(results, indent=2) + "\n")
        print(name, target, "matched", matched, "initialization_warning", warning, flush=True)
if failures:
    raise SystemExit("Upstream receiver expectations differ: " + ", ".join(failures))
print("CONSTRUCTOR_RECEIVER_UPSTREAM:PASS records=" + str(len(results)))
