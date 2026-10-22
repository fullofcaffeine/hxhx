#!/usr/bin/env python3
"""Check the independently retained object-bound acceptance matrix with Haxe 4.3.7."""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parent
version = subprocess.run(["haxe", "--version"], capture_output=True, text=True, check=True, timeout=15)
if version.stdout.strip() != "4.3.7":
    raise SystemExit("The object-constraint oracle requires Haxe 4.3.7")

accepted = ["class", "object", "empty", "array", "string", "class_value", "interface", "null", "abstract_to_object"]
rejected = ["int", "float", "bool", "function", "enum", "abstract_int", "abstract_object"]
for name in accepted + rejected:
    result = subprocess.run(
        ["haxe", "-cp", str(root / name), "-main", "Main", "--no-output"],
        capture_output=True, text=True, timeout=15,
    )
    if name in accepted:
        if result.returncode != 0:
            raise SystemExit(f"Expected acceptance for {name}:\n{result.stderr}")
    elif result.returncode == 0 or " should be { }" not in result.stderr:
        raise SystemExit(f"Expected object-constraint rejection for {name}:\n{result.stderr}")
    print(f"UPSTREAM_EMPTY_OBJECT_CONSTRAINT:PASS {name}")
