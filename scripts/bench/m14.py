#!/usr/bin/env python3

"""
M14 benchmark harness (reflaxe.ocaml backend).

Goals
- Provide a single, reproducible command that:
  - runs a small runtime micro-benchmark (stdlib hot-path),
  - runs a compiler-shaped benchmark (lots of typing/lowering work),
  - and records results to JSON for tracking/regression detection.

This intentionally avoids external benchmark tools (hyperfine, etc) so it works
in minimal environments (local and CI) as long as python3 is available.
"""

from __future__ import annotations

import argparse
import datetime as _dt
import json
import os
import platform
import shutil
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple


ROOT = Path(__file__).resolve().parents[2]


def _cmd_output(cmd: Sequence[str], cwd: Optional[Path] = None) -> str:
    try:
        out = subprocess.check_output(cmd, cwd=str(cwd) if cwd else None, stderr=subprocess.STDOUT)
        return out.decode("utf-8", errors="replace").strip()
    except Exception:
        return "unknown"


def _haxe_version(haxe_bin: str) -> str:
    for args in (["--version"], ["-version"]):
        v = _cmd_output([haxe_bin, *args])
        if v != "unknown" and v.strip():
            return v
    return "unknown"


def _git_info() -> Dict[str, Any]:
    if not shutil.which("git"):
        return {"commit": "unknown", "dirty": "unknown"}
    commit = _cmd_output(["git", "rev-parse", "HEAD"], cwd=ROOT)
    dirty = "unknown"
    try:
        r = subprocess.run(["git", "diff", "--quiet"], cwd=str(ROOT))
        dirty = bool(r.returncode != 0)
    except Exception:
        pass
    return {"commit": commit, "dirty": dirty}


@dataclass(frozen=True)
class Stats:
    reps: int
    avg_ms: int
    best_ms: int
    worst_ms: int

    @staticmethod
    def from_durations(durations_ms: List[int]) -> "Stats":
        if not durations_ms:
            raise ValueError("no durations")
        total = sum(durations_ms)
        reps = len(durations_ms)
        return Stats(
            reps=reps,
            avg_ms=int(total / reps),
            best_ms=min(durations_ms),
            worst_ms=max(durations_ms),
        )


def _time_reps(
    label: str,
    fn,
    reps: int,
) -> Tuple[Stats, List[int]]:
    durations: List[int] = []
    for _ in range(reps):
        start = time.perf_counter()
        fn()
        end = time.perf_counter()
        durations.append(int((end - start) * 1000))
    stats = Stats.from_durations(durations)
    print(f"{label:28s} avg={stats.avg_ms:6d}ms  best={stats.best_ms:6d}ms  worst={stats.worst_ms:6d}ms  reps={stats.reps}")
    return stats, durations


def _run(
    cmd: Sequence[str],
    cwd: Path,
    env: Optional[Dict[str, str]] = None,
    capture: bool = False,
) -> subprocess.CompletedProcess[bytes]:
    merged_env = os.environ.copy()
    if env:
        merged_env.update(env)
    return subprocess.run(
        list(cmd),
        cwd=str(cwd),
        env=merged_env,
        stdout=subprocess.PIPE if capture else subprocess.DEVNULL,
        stderr=subprocess.PIPE if capture else subprocess.DEVNULL,
        check=True,
    )


def _ensure_dir(p: Path) -> None:
    p.mkdir(parents=True, exist_ok=True)


def _copy_tree(src: Path, dst: Path) -> None:
    if dst.exists():
        shutil.rmtree(dst)
    shutil.copytree(src, dst)


def _bench_stringbuf(
    tmp_root: Path,
    reps: int,
    compile_reps: int,
    stringbuf_n: int,
    haxe_bin: str,
) -> Dict[str, Any]:
    """
    Runtime + build microbench.

    Measures:
    - compile+build time (hx -> ml -> dune build native exe)
    - runtime of executing the produced binary with a fixed workload size
    """

    workload_src = ROOT / "bench" / "workloads" / "stringbuf"
    if not workload_src.exists():
        raise RuntimeError(f"Missing workload: {workload_src}")

    def compile_once(work_dir: Path) -> None:
        _copy_tree(workload_src, work_dir)
        _run([haxe_bin, "build.hxml", "-D", "ocaml_build=native"], cwd=work_dir)

    # Compile+build timing (fresh workspace each rep).
    def compile_rep() -> None:
        with tempfile.TemporaryDirectory(dir=str(tmp_root)) as td:
            compile_once(Path(td))

    compile_stats, compile_durations = _time_reps("stringbuf: build", compile_rep, compile_reps)

    # Runtime timing (compile once, then run many times).
    with tempfile.TemporaryDirectory(dir=str(tmp_root)) as td:
        work_dir = Path(td)
        compile_once(work_dir)
        exe = work_dir / "out" / "_build" / "default" / "out.exe"
        if not exe.exists():
            raise RuntimeError(f"Missing built executable: {exe}")

        # Sanity check (capture once).
        out = _run([str(exe), str(stringbuf_n)], cwd=work_dir, capture=True).stdout.decode("utf-8", errors="replace").strip()
        if out != str(stringbuf_n):
            raise RuntimeError(f"Unexpected stringbuf output: got={out!r} expected={str(stringbuf_n)!r}")

        def run_rep() -> None:
            _run([str(exe), str(stringbuf_n)], cwd=work_dir)

        run_stats, run_durations = _time_reps("stringbuf: run", run_rep, reps)

    return {
        "id": "stringbuf",
        "kind": "runtime_microbench",
        "params": {"n": stringbuf_n},
        "build_ms": compile_stats.__dict__,
        "build_durations_ms": compile_durations,
        "run_ms": run_stats.__dict__,
        "run_durations_ms": run_durations,
    }


def _bench_hih_workload_compile(
    tmp_root: Path,
    compile_reps: int,
    haxe_bin: str,
) -> Dict[str, Any]:
    """
    Compiler-shaped benchmark (Haxe typing/lowering workload).

    This uses the acceptance example `examples/hih-workload`, but runs it in a
    fresh temp workspace per rep to reduce "incremental build" effects.
    """

    workload_src = ROOT / "examples" / "hih-workload"
    if not workload_src.exists():
        raise RuntimeError(f"Missing example: {workload_src}")

    def compile_rep() -> None:
        with tempfile.TemporaryDirectory(dir=str(tmp_root)) as td:
            work_dir = Path(td) / "hih-workload"
            _copy_tree(workload_src, work_dir)
            # Keep output contained and avoid any dune builds here; this is a "compiler-shaped" pass.
            _run([haxe_bin, "build.hxml"], cwd=work_dir)

    compile_stats, compile_durations = _time_reps("hih-workload: type", compile_rep, compile_reps)

    return {
        "id": "hih_workload",
        "kind": "compiler_shaped",
        "compile_ms": compile_stats.__dict__,
        "compile_durations_ms": compile_durations,
    }


def main(argv: Sequence[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--haxe-bin", default=os.environ.get("HAXE_BIN", "haxe"))
    parser.add_argument("--reps", type=int, default=10)
    parser.add_argument("--compile-reps", type=int, default=3)
    parser.add_argument("--stringbuf-n", type=int, default=200000)
    parser.add_argument("--out", required=True)
    args = parser.parse_args(list(argv[1:]))

    haxe_bin = args.haxe_bin
    if not shutil.which(haxe_bin):
        print(f"Missing Haxe compiler on PATH (expected '{haxe_bin}').", file=sys.stderr)
        return 2

    for tool in ("dune", "ocamlc"):
        if not shutil.which(tool):
            print("Skipping M14 benchmarks: dune/ocamlc not found on PATH.")
            return 0

    tmp_root = ROOT / "bench" / "tmp"
    _ensure_dir(tmp_root)

    print("== M14 bench (backend runtime + compiler-shaped)")
    print(f"Platform: {platform.system()} {platform.machine()}")
    print(f"Git: {_git_info().get('commit')}")
    print(f"Stage0 haxe: {_haxe_version(haxe_bin)}")
    print(f"OCaml: {_cmd_output(['ocamlc', '-version'])}")
    print(f"Dune: {_cmd_output(['dune', '--version'])}")
    print(f"Reps: {args.reps} (compile reps: {args.compile_reps})")
    print("")

    started = _dt.datetime.now(tz=_dt.timezone.utc)

    benches: List[Dict[str, Any]] = []
    benches.append(
        _bench_stringbuf(
            tmp_root=tmp_root,
            reps=args.reps,
            compile_reps=args.compile_reps,
            stringbuf_n=args.stringbuf_n,
            haxe_bin=haxe_bin,
        )
    )
    benches.append(
        _bench_hih_workload_compile(
            tmp_root=tmp_root,
            compile_reps=args.compile_reps,
            haxe_bin=haxe_bin,
        )
    )

    ended = _dt.datetime.now(tz=_dt.timezone.utc)

    payload: Dict[str, Any] = {
        "schema_version": 1,
        "started_at": started.isoformat(),
        "ended_at": ended.isoformat(),
        "git": _git_info(),
        "env": {
            "platform": {"system": platform.system(), "machine": platform.machine(), "release": platform.release()},
            "python": sys.version.split()[0],
            "haxe": _haxe_version(haxe_bin),
            "ocamlc": _cmd_output(["ocamlc", "-version"]),
            "dune": _cmd_output(["dune", "--version"]),
        },
        "params": {
            "reps": args.reps,
            "compile_reps": args.compile_reps,
            "stringbuf_n": args.stringbuf_n,
        },
        "benchmarks": benches,
    }

    out_path = Path(args.out)
    _ensure_dir(out_path.parent)
    out_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
