#!/usr/bin/env python3
"""Patch helper for run-upstream-runci-targets.sh.

The Gate3 shell runner owns toolchain setup, process control, and target
selection. This helper owns structural edits to the temporary upstream Haxe
worktree so the shell script does not accumulate multiline Python heredocs.
"""

from __future__ import annotations

import argparse
import os
import pathlib
import platform
import re
import sys


def fail(message: str) -> "None":
    sys.stderr.write(message)
    if not message.endswith("\n"):
        sys.stderr.write("\n")
    raise SystemExit(1)


def upstream_path(upstream_dir: str, rel_path: str) -> pathlib.Path:
    return pathlib.Path(upstream_dir) / rel_path


def read_text(path: pathlib.Path) -> str:
    return path.read_text(encoding="utf-8")


def write_text(path: pathlib.Path, text: str) -> None:
    path.write_text(text, encoding="utf-8")


def read_lines(path: pathlib.Path) -> list[str]:
    return path.read_text(encoding="utf-8").splitlines(keepends=True)


def write_lines(path: pathlib.Path, lines: list[str]) -> None:
    path.write_text("".join(lines), encoding="utf-8")


def patch_skip_sys_on_macos(upstream_dir: str) -> None:
    if os.environ.get("HXHX_RUNCi_FORCE_SYS") == "1":
        return
    if platform.system() != "Darwin":
        return

    path = upstream_path(upstream_dir, "tests/runci/System.hx")
    if not path.is_file():
        return

    src = read_text(path)
    needle = "static public function runSysTest(cmd:String, ?args:Array<String>) {"
    if needle not in src or "HXHX Gate runner" in src:
        return

    insert = (
        needle
        + "\n\t\t// HXHX Gate runner: upstream tests/sys contains unicode filename fixtures that are invalid on macOS/APFS.\n"
        + "\t\t// Skip sys tests on macOS to keep runci usable for other stages.\n"
        + "\t\t// Override with: HXHX_RUNCi_FORCE_SYS=1\n"
        + "\t\tif (Sys.systemName() == \"Mac\" && Sys.getEnv(\"HXHX_RUNCi_FORCE_SYS\") != \"1\") {\n"
        + "\t\t\tinfoMsg(\"Skipping sys tests on Mac (HXHX Gate runner; macOS/APFS unicode filename fixtures unsupported)\");\n"
        + "\t\t\treturn;\n"
        + "\t\t}\n"
    )
    write_text(path, src.replace(needle, insert, 1))


def patch_js_server_timeouts_on_macos(upstream_dir: str, timeout_ms: str) -> None:
    if platform.system() != "Darwin":
        return
    if os.environ.get("HXHX_GATE3_FORCE_JS_SERVER") == "1":
        return

    test_builder = upstream_path(upstream_dir, "tests/server/src/utils/macro/TestBuilder.macro.hx")
    test_case = upstream_path(upstream_dir, "tests/server/src/TestCase.hx")
    if not test_builder.is_file() or not test_case.is_file():
        return

    marker = "HXHX Gate runner: relaxed Js server timeouts on macOS"
    tb_src = read_text(test_builder)
    if marker not in tb_src:
        base_line = "$i{asyncName}.setTimeout(20000);"
        replaced_line = "$i{asyncName}.setTimeout(" + timeout_ms + ");"
        if base_line in tb_src:
            tb_src = tb_src.replace(base_line, "// " + marker + "\n\t\t\t\t" + replaced_line, 1)
        else:
            tb_src = re.sub(
                r"\$i\{asyncName\}\.setTimeout\(\d+\);",
                "// " + marker + "\n\t\t\t\t" + replaced_line,
                tb_src,
                count=1,
            )
        write_text(test_builder, tb_src)

    tc_src = read_text(test_case)
    if marker not in tc_src:
        needle = "public function setup(async:utest.Async) {\n"
        if needle in tc_src:
            tc_src = tc_src.replace(
                needle,
                needle + "\t\t// " + marker + "\n\t\tasync.setTimeout(" + timeout_ms + ");\n",
                1,
            )
            write_text(test_case, tc_src)


def patch_haxelib_git_install_if_present(upstream_dir: str, rel_path: str, needle: str, lib_name: str) -> None:
    path = upstream_path(upstream_dir, rel_path)
    if not path.is_file():
        return

    out: list[str] = []
    changed = False
    for line in read_lines(path):
        if needle in line:
            indent = line.split(needle, 1)[0]
            out.append(indent + "try {\n")
            out.append(indent + f"\trunCommand(\"haxelib\", [\"path\", \"{lib_name}\"]);\n")
            out.append(indent + "} catch (e:Dynamic) {\n")
            out.append(indent + "\t" + needle + "\n")
            out.append(indent + "}\n")
            changed = True
        else:
            out.append(line)

    if changed:
        write_lines(path, out)


def patch_skip_utest_install_if_present(upstream_dir: str) -> None:
    patch_haxelib_git_install_if_present(
        upstream_dir,
        "tests/RunCi.hx",
        'haxelibInstallGit("haxe-utest", "utest", "a94f8812e8786f2b5fec52ce9f26927591d26327", "--always");',
        "utest",
    )


def patch_macro_skip_haxeserver_install_if_present(upstream_dir: str) -> None:
    patch_haxelib_git_install_if_present(
        upstream_dir,
        "tests/runci/targets/Macro.hx",
        'haxelibInstallGit("Simn", "haxeserver");',
        "haxeserver",
    )


def patch_macro_optional_skip_party(upstream_dir: str) -> None:
    path = upstream_path(upstream_dir, "tests/runci/targets/Macro.hx")
    if not path.is_file():
        return

    needle = "deleteDirectoryRecursively(partyDir);"
    out: list[str] = []
    changed = False
    already = False
    for line in read_lines(path):
        if "HXHX_GATE2_SKIP_PARTY" in line:
            already = True
        if needle in line and not already:
            indent = line.split(needle, 1)[0]
            out.append(indent + "if (Sys.getEnv(\"HXHX_GATE2_SKIP_PARTY\") == \"1\") {\n")
            out.append(indent + "\tinfoMsg(\"Skipping party stage (HXHX Gate runner; set HXHX_GATE2_SKIP_PARTY=0 to enable)\");\n")
            out.append(indent + "\treturn;\n")
            out.append(indent + "}\n")
            out.append(line)
            changed = True
        else:
            out.append(line)

    if changed:
        write_lines(path, out)


def patch_sourcemaps_skip_sourcemap_install_if_present(upstream_dir: str) -> None:
    path = upstream_path(upstream_dir, "tests/sourcemaps/src/Test.hx")
    if not path.is_file():
        return

    src = read_text(path)
    needle = "Sys.command('haxelib', ['install', 'sourcemap']);"
    if needle not in src:
        return

    replacement = (
        "if (Sys.command('haxelib', ['path', 'sourcemap']) != 0) {\n"
        "\t\t\tSys.command('haxelib', ['install', 'sourcemap']);\n"
        "\t\t}"
    )
    write_text(path, src.replace(needle, replacement, 1))


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("command")
    parser.add_argument("--upstream-dir", required=True)
    parser.add_argument("--timeout-ms", default=os.environ.get("HXHX_GATE3_JS_SERVER_TIMEOUT_MS", "60000"))
    return parser.parse_args(argv)


def main(argv: list[str]) -> None:
    args = parse_args(argv)
    commands = {
        "skip-sys-on-macos": lambda: patch_skip_sys_on_macos(args.upstream_dir),
        "js-server-timeouts-on-macos": lambda: patch_js_server_timeouts_on_macos(args.upstream_dir, args.timeout_ms),
        "skip-utest-install-if-present": lambda: patch_skip_utest_install_if_present(args.upstream_dir),
        "macro-skip-haxeserver-install-if-present": lambda: patch_macro_skip_haxeserver_install_if_present(args.upstream_dir),
        "macro-optional-skip-party": lambda: patch_macro_optional_skip_party(args.upstream_dir),
        "sourcemaps-skip-sourcemap-install-if-present": lambda: patch_sourcemaps_skip_sourcemap_install_if_present(args.upstream_dir),
    }
    command = commands.get(args.command)
    if command is None:
        fail(f"unknown command: {args.command}")
    command()


if __name__ == "__main__":
    main(sys.argv[1:])
