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


def is_darwin_patch_host() -> bool:
    return platform.system() == "Darwin" or os.environ.get("HXHX_PATCH_HELPER_FORCE_DARWIN") == "1"


def patch_skip_sys_on_macos(upstream_dir: str) -> None:
    if os.environ.get("HXHX_RUNCi_FORCE_SYS") == "1":
        return
    if not is_darwin_patch_host():
        return

    system_path = upstream_path(upstream_dir, "tests/runci/System.hx")
    if system_path.is_file():
        src = read_text(system_path)
        needle = "static public function runSysTest(cmd:String, ?args:Array<String>) {"
        if needle in src and "HXHX Gate runner" not in src:
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
            write_text(system_path, src.replace(needle, insert, 1))

    js_target_path = upstream_path(upstream_dir, "tests/runci/targets/Js.hx")
    if not js_target_path.is_file():
        return

    marker = "HXHX Gate runner: skip JS sys compile on macOS"
    lines = read_lines(js_target_path)
    if any(marker in line for line in lines):
        return

    out: list[str] = []
    changed_start = False
    changed_end = False
    for line in lines:
        if not changed_start and "changeDirectory(sysDir);" in line:
            indent = line.split("changeDirectory(sysDir);", 1)[0]
            out.append(indent + f"// {marker}\n")
            out.append(indent + "if (Sys.systemName() == \"Mac\" && Sys.getEnv(\"HXHX_RUNCi_FORCE_SYS\") != \"1\") {\n")
            out.append(indent + "\tinfoMsg(\"Skipping JS sys tests on Mac (HXHX Gate runner; set HXHX_RUNCi_FORCE_SYS=1 to enable)\");\n")
            out.append(indent + "} else {\n")
            changed_start = True
        out.append(line)
        if changed_start and not changed_end and "runSysTest(" in line:
            indent = line.split("runSysTest(", 1)[0]
            out.append(indent + "}\n")
            changed_end = True

    if changed_start != changed_end:
        fail("Js.hx sys skip patch could not find a complete sys test block")
    if changed_start:
        write_lines(js_target_path, out)

    java_target_path = upstream_path(upstream_dir, "tests/runci/targets/Java.hx")
    if not java_target_path.is_file():
        return

    marker = "HXHX Gate runner: skip Java sys compile on macOS"
    lines = read_lines(java_target_path)
    if any(marker in line for line in lines):
        return

    out = []
    changed_start = False
    changed_end = False
    for line in lines:
        if not changed_start and "changeDirectory(sysDir);" in line:
            indent = line.split("changeDirectory(sysDir);", 1)[0]
            out.append(indent + f"// {marker}\n")
            out.append(indent + "if (Sys.systemName() == \"Mac\" && Sys.getEnv(\"HXHX_RUNCi_FORCE_SYS\") != \"1\") {\n")
            out.append(indent + "\tinfoMsg(\"Skipping Java sys tests on Mac (HXHX Gate runner; set HXHX_RUNCi_FORCE_SYS=1 to enable)\");\n")
            out.append(indent + "} else {\n")
            changed_start = True
        out.append(line)
        if changed_start and not changed_end and "runSysTest(" in line:
            indent = line.split("runSysTest(", 1)[0]
            out.append(indent + "}\n")
            changed_end = True

    if changed_start != changed_end:
        fail("Java.hx sys skip patch could not find a complete sys test block")
    if changed_start:
        write_lines(java_target_path, out)


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


def patch_node_echo_server(upstream_dir: str) -> None:
    """Replace the shared Neko HTTP fixture with a stage0-free Node harness.

    Gate3 target runs compile and start a tiny echo server before each target.
    The upstream fixture builds that server with `haxe -neko`, which blocks all
    strict native target lanes before they reach the target under test. This
    patch keeps the observable harness behavior (echo POST body after a short
    delay) while avoiding stage0 Haxe and Neko bytecode compilation.
    """

    run_ci = upstream_path(upstream_dir, "tests/RunCi.hx")
    echo_dir = upstream_path(upstream_dir, "tests/echoServer")
    if not run_ci.is_file() or not echo_dir.is_dir():
        return

    node_server = echo_dir / "hxhx_node_echo_server.js"
    write_text(
        node_server,
        """const http = require('http');

const server = http.createServer((req, res) => {
  const chunks = [];
  req.on('data', chunk => chunks.push(chunk));
  req.on('end', () => {
    setTimeout(() => {
      res.statusCode = 200;
      res.setHeader('content-type', 'text/plain');
      res.end(Buffer.concat(chunks));
    }, 300);
  });
});

server.listen(20200);

function shutdown() {
  server.close(() => process.exit(0));
}

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
""",
    )

    src = read_text(run_ci)
    marker = "HXHX_GATE3_NODE_ECHO_SERVER"
    if marker in src:
        return

    build_needle = "\t\tif (isCi()) {\n\t\t\tchangeDirectory('echoServer');\n\t\t\trunCommand('haxe', ['build.hxml']);\n\t\t\tchangeDirectory(cwd);\n\t\t}\n"
    build_replacement = (
        "\t\tif (isCi() && Sys.getEnv(\"HXHX_GATE3_NODE_ECHO_SERVER\") != \"1\") {\n"
        "\t\t\tchangeDirectory('echoServer');\n"
        "\t\t\trunCommand('haxe', ['build.hxml']);\n"
        "\t\t\tchangeDirectory(cwd);\n"
        "\t\t}\n"
    )
    if build_needle not in src:
        fail("RunCi.hx echoServer build block not found")
    src = src.replace(build_needle, build_replacement, 1)

    process_needle = "\t\t\t//run neko-based http echo server\n\t\t\tvar echoServer = new sys.io.Process('nekotools', ['server', '-d', 'echoServer/www/', '-p', '20200']);\n"
    process_replacement = (
        "\t\t\t// HXHX Gate runner: strict native lanes use a stage0-free Node echo harness.\n"
        "\t\t\tvar echoServer = if (Sys.getEnv(\"HXHX_GATE3_NODE_ECHO_SERVER\") == \"1\") {\n"
        "\t\t\t\tnew sys.io.Process('node', ['echoServer/hxhx_node_echo_server.js']);\n"
        "\t\t\t} else {\n"
        "\t\t\t\tnew sys.io.Process('nekotools', ['server', '-d', 'echoServer/www/', '-p', '20200']);\n"
        "\t\t\t};\n"
    )
    if process_needle not in src:
        fail("RunCi.hx echoServer process block not found")
    write_text(run_ci, src.replace(process_needle, process_replacement, 1))


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
        "node-echo-server": lambda: patch_node_echo_server(args.upstream_dir),
    }
    command = commands.get(args.command)
    if command is None:
        fail(f"unknown command: {args.command}")
    command()


if __name__ == "__main__":
    main(sys.argv[1:])
