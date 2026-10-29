"""Check authored constructor admission cases through the public Haxe CLI."""
import json
import pathlib
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parent
output = pathlib.Path(sys.argv[1])
output.mkdir(parents=True, exist_ok=True)
results = []
for case in json.loads((root / "cases.json").read_text()):
    folder = output / case["name"]
    folder.mkdir(exist_ok=True)
    source = ('class Main { static function main():Void { new Result(false); } }\n'
              'abstract Result(Int) { public function new(flag:Bool) { '
              + case["body"] + ' } }\n')
    (folder / "Main.hx").write_text(source)
    command = ["haxe", "-cp", str(folder), "-main", "Main", "--js",
               str(folder / "unused.js"), "--no-output"]
    run = subprocess.run(command, text=True, capture_output=True, timeout=30)
    results.append({"case": case["name"], "expected": case["accepted"],
                    "accepted": run.returncode == 0, "command": command,
                    "exit": run.returncode, "stdout": run.stdout, "stderr": run.stderr})
(output / "results.json").write_text(json.dumps(results, indent=2) + "\n")
failures = [row["case"] for row in results if row["accepted"] != row["expected"]]
if failures:
    raise SystemExit("Upstream expectations differ: " + ", ".join(failures))
print("CONSTRUCTOR_INITIALIZATION_UPSTREAM:PASS cases=" + str(len(results)))
