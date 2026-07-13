# Full1 Target and Generator Scope

Last audited: 2026-07-13

This page answers a simple question: **which upstream Haxe 4.3.7 output choices
must work before `hxhx` may call itself Full1?**

The short answer is that Full1 is a strict compatibility promise for the list
below. It is not a promise that every target ever shipped by Haxe is included.
The machine-readable source is
`docs/02-user-guide/compat/full-1.0-scope.json`.

## What the words mean

- **Required**: Full1 cannot ship until same-candidate CI evidence passes.
- **Deferred**: not included in the first Full1 release; a later release may add it.
- **Incompatible**: intentionally outside the `hxhx` product promise.

Recognizing a command-line flag or reaching an experimental backend does not
make a target supported. Only the required release evidence does that.

## Required for the first Full1 release

| Haxe 4.3.7 surface | Command | What Full1 must prove |
| --- | --- | --- |
| JavaScript output | `--js` | Compile and run the strict upstream JavaScript target workload. |
| Lua output | `--lua` | Compile and run the strict upstream Lua target workload. |
| Neko bytecode output | `--neko` | Produce and run compatible Neko output. |
| PHP output | `--php` | Compile and run the strict upstream PHP target workload. |
| C++ source output | `--cpp` | Produce, build, and run the complete strict C++/hxcpp workload. |
| Cppia bytecode output | `--cppia` | Pass the Cppia checks that upstream includes inside its C++ lane. |
| C# output | `--cs` | Compile and run with the declared .NET/Mono toolchain. |
| Java source output | `--java` | Compile and run the Java source target workload. |
| Python output | `--python` | Compile and run the strict Python target workload. |
| HashLink bytecode output | `--hl <file.hl>` | Produce real `.hl` bytecode and run it. |
| HashLink C output | `--hl <file.c>` | Produce, build, and run the C form covered by upstream's HashLink lane. |
| Interpreter execution | `--interp` | Run interpreter-style workloads without required upstream-Haxe delegation. |
| Run-module execution | `--run` | Run a named Haxe module with compatible argument behavior. |

The strict Gate3 workflow uses the labels
`Macro,Js,Neko,Hl,Python,Java,Cs,Cpp,Lua,Php`. `Macro` is the test harness's
compiler/macro lane, not an extra output format. Interpreter and run-module
behavior are also checked by the Full1 macro/eval and upstream-suite evidence.

### Why C++ includes Cppia

Upstream Haxe's C++ test lane exercises both normal C++ output and Cppia. A
green C++ label that silently skipped Cppia would describe less behavior than
the upstream lane. For this reason both are required, and C++/hxcpp is a real
Full1 blocker rather than an optional follow-up.

### Why HashLink has two rows

Haxe's one `--hl` flag can produce `.hl` bytecode or C source depending on the
output filename. Upstream's HashLink lane checks both forms on its supported CI
platform. Full1 therefore requires both forms even though CI displays one `Hl`
target label.

## Not included in the first Full1 release

| Haxe 4.3.7 surface | Command | Decision | What this means for a user |
| --- | --- | --- | --- |
| Flash SWF/SWC output | `--swf` | Incompatible | Keep upstream Haxe 4.3.7 or another Flash-capable toolchain for SWF/SWC projects. |
| Direct JVM bytecode output | `--jvm` | Deferred | Java source output is required, but direct JVM bytecode is a different generator. Keep upstream Haxe for `--jvm`. |
| XML type-description output | `--xml` | Deferred | Tools that consume Haxe's XML type description must keep upstream Haxe for that step. |
| JSON type-description output | `--json` | Deferred | Tools that consume Haxe's JSON type description must keep upstream Haxe for that step. |

Flash is a deliberate product exclusion. JVM, XML, and JSON may be proposed
later, but they do not count toward the first Full1 release and must not be
silently presented as working.

## Safe public wording

Use:

> Haxe 4.3.7-compatible for the declared Full1 target and generator scope.

Do not use an unqualified “all-target drop-in replacement” statement. Release
notes must link this page so users can see the required and excluded surfaces
before deciding whether `hxhx` fits their project.

This scope decision only removes ambiguity. It does not mean the required
targets are green today, and it does not increase the README readiness bars.
