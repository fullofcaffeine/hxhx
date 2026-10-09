"""Observe accepted initialization edge cases through upstream eval and Neko."""
import json
import pathlib
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parent
output = pathlib.Path(sys.argv[1])
output.mkdir(parents=True, exist_ok=True)
results = []
selected = {"do_early_break", "short_circuit", "capture_before_assignment"}
for case in json.loads((root / "cases.json").read_text()):
    if case["name"] not in selected:
        continue
    for flag in [False, True]:
        folder = output / (case["name"] + ("_true" if flag else "_false"))
        folder.mkdir(exist_ok=True)
        source = ('class Main { static function main():Void { final value:Null<Int> = new Result('
                  + str(flag).lower() + ').read(); Sys.println(value); Sys.println(value == null); } }\n'
                  'abstract Result(Int) { public function new(flag:Bool) { '
                  + case["body"] + ' } public function read():Int { return this; } }\n')
        (folder / "Main.hx").write_text(source)
        for target in ["eval", "neko"]:
            artifact = folder / "main.n"
            command = ["haxe", "-cp", str(folder), "-main", "Main"]
            command += ["--interp"] if target == "eval" else ["--neko", str(artifact)]
            compiled = subprocess.run(command, text=True, capture_output=True, timeout=30)
            run = compiled
            runtime_command = None
            if target == "neko" and compiled.returncode == 0:
                runtime_command = ["neko", str(artifact)]
                run = subprocess.run(runtime_command, text=True, capture_output=True, timeout=30)
            results.append({"case": case["name"], "flag": flag, "target": target,
                            "command": command, "runtime_command": runtime_command,
                            "compile_exit": compiled.returncode, "compile_stderr": compiled.stderr,
                            "exit": run.returncode, "stdout": run.stdout, "stderr": run.stderr})
(output / "results.json").write_text(json.dumps(results, indent=2) + "\n")
for row in results:
    print(row["case"], row["flag"], row["target"], row["exit"], repr(row["stdout"]))
if any(row["exit"] != 0 for row in results):
    raise SystemExit("Some upstream runtime probes failed; inspect results.json")
