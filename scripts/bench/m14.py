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
    profile: str,
    runtime_mode: str,
) -> Dict[str, Any]:
    return _bench_runtime_workload(
        tmp_root=tmp_root,
        reps=reps,
        compile_reps=compile_reps,
        haxe_bin=haxe_bin,
        workload_id="stringbuf",
        workload_param_name="n",
        workload_param_value=stringbuf_n,
        expected_output=str(stringbuf_n),
        profile=profile,
        runtime_mode=runtime_mode,
    )


def _bench_int_array_sum(
    tmp_root: Path,
    reps: int,
    compile_reps: int,
    int_array_n: int,
    haxe_bin: str,
    profile: str,
    runtime_mode: str,
) -> Dict[str, Any]:
    expected = int_array_n * (int_array_n - 1) // 2
    return _bench_runtime_workload(
        tmp_root=tmp_root,
        reps=reps,
        compile_reps=compile_reps,
        haxe_bin=haxe_bin,
        workload_id="int_array_sum",
        workload_param_name="n",
        workload_param_value=int_array_n,
        expected_output=str(expected),
        profile=profile,
        runtime_mode=runtime_mode,
    )


def _bench_anon_getset(
    tmp_root: Path,
    reps: int,
    compile_reps: int,
    anon_iterations: int,
    haxe_bin: str,
    profile: str,
    runtime_mode: str,
) -> Dict[str, Any]:
    return _bench_runtime_workload(
        tmp_root=tmp_root,
        reps=reps,
        compile_reps=compile_reps,
        haxe_bin=haxe_bin,
        workload_id="anon_getset",
        workload_param_name="iterations",
        workload_param_value=anon_iterations,
        expected_output=str(anon_iterations),
        profile=profile,
        runtime_mode=runtime_mode,
    )


def _bench_runtime_workload(
    tmp_root: Path,
    reps: int,
    compile_reps: int,
    haxe_bin: str,
    workload_id: str,
    workload_param_name: str,
    workload_param_value: int,
    expected_output: str,
    profile: str,
    runtime_mode: str,
) -> Dict[str, Any]:
    """
    Generic runtime + build microbench runner.

    Measures:
    - compile+build time (hx -> ml -> dune build native exe)
    - runtime of executing the produced binary with a fixed workload input
    """

    workload_src = ROOT / "bench" / "workloads" / workload_id
    if not workload_src.exists():
        raise RuntimeError(f"Missing workload: {workload_src}")

    profile_define = f"ocaml_profile={profile}"
    runtime_mode_define = f"ocaml_runtime_mode={runtime_mode}"
    label = f"{workload_id} [{profile}]"

    def compile_once(work_dir: Path) -> None:
        _copy_tree(workload_src, work_dir)
        _run([haxe_bin, "build.hxml", "-D", "ocaml_build=native", "-D", profile_define, "-D", runtime_mode_define], cwd=work_dir)

    def compile_rep() -> None:
        with tempfile.TemporaryDirectory(dir=str(tmp_root)) as td:
            compile_once(Path(td))

    compile_stats, compile_durations = _time_reps(f"{label}: build", compile_rep, compile_reps)

    with tempfile.TemporaryDirectory(dir=str(tmp_root)) as td:
        work_dir = Path(td)
        compile_once(work_dir)
        exe = work_dir / "out" / "_build" / "default" / "out.exe"
        if not exe.exists():
            raise RuntimeError(f"Missing built executable: {exe}")

        output = _run([str(exe), str(workload_param_value)], cwd=work_dir, capture=True).stdout.decode("utf-8", errors="replace").strip()
        if output != expected_output:
            raise RuntimeError(f"Unexpected {workload_id} output (profile={profile}): got={output!r} expected={expected_output!r}")

        def run_rep() -> None:
            _run([str(exe), str(workload_param_value)], cwd=work_dir)

        run_stats, run_durations = _time_reps(f"{label}: run", run_rep, reps)

    return {
        "id": workload_id,
        "kind": "runtime_microbench",
        "profile": profile,
        "params": {workload_param_name: workload_param_value},
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

    This uses the acceptance example `workloads/hih-workload`, but runs it in a
    fresh temp workspace per rep to reduce "incremental build" effects.
    """

    workload_src = ROOT / "workloads" / "hih-workload"
    if not workload_src.exists():
        raise RuntimeError(f"Missing workload: {workload_src}")

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


def _parse_profiles(raw_profiles: str) -> List[str]:
    tokens = [token.strip().lower() for token in raw_profiles.split(",") if token.strip()]
    if not tokens:
        raise ValueError("at least one profile must be provided")
    allowed = {"portable", "metal"}
    normalized: List[str] = []
    seen = set()
    for token in tokens:
        if token not in allowed:
            raise ValueError(f"invalid profile '{token}' (expected portable|metal)")
        if token in seen:
            continue
        seen.add(token)
        normalized.append(token)
    return normalized


def _parse_runtime_mode(raw_runtime_mode: str) -> str:
    token = raw_runtime_mode.strip().lower()
    if token in ("full", "selective", "none"):
        return token
    raise ValueError(f"invalid runtime mode '{raw_runtime_mode}' (expected full|selective|none)")


def _safe_ratio(numerator: int, denominator: int) -> Optional[float]:
    if denominator <= 0:
        return None
    return round(numerator / denominator, 6)


def _build_runtime_profile_ratios(benchmarks: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    rows_by_id: Dict[str, Dict[str, Dict[str, Any]]] = {}
    for bench in benchmarks:
        if bench.get("kind") != "runtime_microbench":
            continue
        bench_id = str(bench.get("id", ""))
        profile = str(bench.get("profile", ""))
        if bench_id == "" or profile == "":
            continue
        if profile not in ("portable", "metal"):
            continue
        if bench_id not in rows_by_id:
            rows_by_id[bench_id] = {}
        rows_by_id[bench_id][profile] = bench

    ratios: List[Dict[str, Any]] = []
    for bench_id in sorted(rows_by_id.keys()):
        pair = rows_by_id[bench_id]
        portable = pair.get("portable")
        metal = pair.get("metal")
        if portable is None or metal is None:
            continue
        ratios.append(
            {
                "id": bench_id,
                "kind": "runtime_microbench",
                "portable_over_metal": {
                    "build_avg_ms": _safe_ratio(int(portable["build_ms"]["avg_ms"]), int(metal["build_ms"]["avg_ms"])),
                    "run_avg_ms": _safe_ratio(int(portable["run_ms"]["avg_ms"]), int(metal["run_ms"]["avg_ms"])),
                    "run_best_ms": _safe_ratio(int(portable["run_ms"]["best_ms"]), int(metal["run_ms"]["best_ms"])),
                    "run_worst_ms": _safe_ratio(int(portable["run_ms"]["worst_ms"]), int(metal["run_ms"]["worst_ms"])),
                },
            }
        )
    return ratios


def main(argv: Sequence[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--haxe-bin", default=os.environ.get("HAXE_BIN", "haxe"))
    parser.add_argument("--reps", type=int, default=10)
    parser.add_argument("--compile-reps", type=int, default=3)
    parser.add_argument("--profiles", default="portable,metal")
    parser.add_argument("--runtime-mode", default="full")
    parser.add_argument("--stringbuf-n", type=int, default=200000)
    parser.add_argument("--int-array-n", type=int, default=50000)
    parser.add_argument("--anon-iterations", type=int, default=300000)
    parser.add_argument("--out", required=True)
    args = parser.parse_args(list(argv[1:]))

    try:
        profiles = _parse_profiles(args.profiles)
    except ValueError as error:
        print(f"Invalid profile configuration: {error}", file=sys.stderr)
        return 2

    try:
        runtime_mode = _parse_runtime_mode(args.runtime_mode)
    except ValueError as error:
        print(f"Invalid runtime mode configuration: {error}", file=sys.stderr)
        return 2

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
    print(f"Profiles: {','.join(profiles)}")
    print(f"Runtime mode: {runtime_mode}")
    print(f"Reps: {args.reps} (compile reps: {args.compile_reps})")
    print("")

    started = _dt.datetime.now(tz=_dt.timezone.utc)

    benches: List[Dict[str, Any]] = []
    for profile in profiles:
        benches.append(
            _bench_stringbuf(
                tmp_root=tmp_root,
                reps=args.reps,
                compile_reps=args.compile_reps,
                stringbuf_n=args.stringbuf_n,
                haxe_bin=haxe_bin,
                profile=profile,
                runtime_mode=runtime_mode,
            )
        )
        benches.append(
            _bench_int_array_sum(
                tmp_root=tmp_root,
                reps=args.reps,
                compile_reps=args.compile_reps,
                int_array_n=args.int_array_n,
                haxe_bin=haxe_bin,
                profile=profile,
                runtime_mode=runtime_mode,
            )
        )
        benches.append(
            _bench_anon_getset(
                tmp_root=tmp_root,
                reps=args.reps,
                compile_reps=args.compile_reps,
                anon_iterations=args.anon_iterations,
                haxe_bin=haxe_bin,
                profile=profile,
                runtime_mode=runtime_mode,
            )
        )
    benches.append(
        _bench_hih_workload_compile(
            tmp_root=tmp_root,
            compile_reps=args.compile_reps,
            haxe_bin=haxe_bin,
        )
    )
    runtime_profile_ratios = _build_runtime_profile_ratios(benches)

    if runtime_profile_ratios:
        print("")
        print("== portable/metal runtime ratios (avg portable over metal)")
        for ratio in runtime_profile_ratios:
            print(
                f"{ratio['id']:28s} build={ratio['portable_over_metal']['build_avg_ms']} "
                f"run={ratio['portable_over_metal']['run_avg_ms']}"
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
            "profiles": profiles,
            "runtime_mode": runtime_mode,
            "stringbuf_n": args.stringbuf_n,
            "int_array_n": args.int_array_n,
            "anon_iterations": args.anon_iterations,
        },
        "benchmarks": benches,
        "runtime_profile_ratios": runtime_profile_ratios,
    }

    out_path = Path(args.out)
    _ensure_dir(out_path.parent)
    out_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
