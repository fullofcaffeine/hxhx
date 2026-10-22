# Upstream C++ startup behavior

These authored programs establish startup expectations before hxhx selects an
initialization schedule. They run through upstream Haxe 4.3.7 and hxcpp 4.3.2.
They do not prove that hxhx implements these behaviors yet.

| Case | Required observation |
| --- | --- |
| `order` | All class `__init__` methods run before ordinary field initializers. The uncalled sibling class still initializes. |
| `transitive/none` | A callback stored in a static field and an uncalled method do not move Gamma before Alpha. |
| `transitive/eager` | A field read inside the called helper moves Gamma before Alpha. |
| `transitive/invoked` | A callback invoked inside that helper also moves Gamma before Alpha. |
| `transitive/stored` | Even an unused callback inside the called helper contributes this dependency. |
| `transitive/dead` | A field read under `if (false)` inside the called helper contributes this dependency. |
| `modules` | A type annotation, an uncalled method, or a stored callback can load another module whose fields initialize first. |
| `cycle` | A cyclic read observes the target default. Int starts at zero and Bool at false. String, Null<Int>, arrays, records, callbacks, objects, and Dynamic start at null. |
| `extern` | An actively used extern does not run its initializer. An ordinary class does. Dead-code elimination is disabled. |

The interpreter uses a different order for class startup methods. Its separate
golden file retains that contrast. Do not use interpreter startup order as the
C++ expectation. The callback cases also rule out treating startup dependencies
as a walk of only the expressions that execute.

## Run the check

Use an isolated haxelib repository so the check does not change project libraries:

```sh
mkdir -p .tmp/cpp-static-startup-oracle
cd .tmp/cpp-static-startup-oracle
haxelib newrepo
haxelib install hxcpp 4.3.2 --always
cd ../..
```

Select the host Haxe and haxelib executables before npm adds its local shims:

```sh
HAXE_BIN="$(command -v haxe)" HAXELIB_BIN="$(command -v haxelib)" \
  taskpolicy -b nice -n 10 npm run test:m14:cpp-static-startup-oracle
```

On hosts without `taskpolicy`, use `nice -n 10`. Set
`HXHX_CPP_STARTUP_ORACLE_WORKDIR` to reuse another isolated repository.
The runner checks both toolchain versions, bounds each build and runtime, and
compares stdout byte for byte. It retains build logs, stdout, and stderr under
`receipts/` in that work directory. Unexpected runtime stderr fails the check.

The 12 native cases run sequentially in one build directory. This lets hxcpp reuse
its runtime objects while Haxe regenerates each selected program. Each build uses
two compile workers. Do not run two copies against the same work directory.

This is a separate upstream evidence command because it needs hxcpp and a native
toolchain. It is not part of the ordinary managed-emitter test loop. Future hxhx
startup tests must consume the same source behaviors and independently authored
expectations. The `test:m14:cpp-managed-startup-order` command now checks the
11 native ordering expectations against hxhx with real loaded dependencies.
It checks the schedule only. The separate
[`cpp_managed_startup_execution_seed`](../cpp_managed_startup_execution_seed/README.md)
fixture checks native execution of a smaller program.
Initialization failures, wider type defaults, inheritance, cross-module
cycles, and complete startup ordering still need further coverage. README Goals
status is unchanged.
