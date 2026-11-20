<p align="center">
  <img src="assets/hxhx-logo.png" alt="hxhx logo" width="560" />
</p>

# hxhx and reflaxe.ocaml

[![CI](https://github.com/fullofcaffeine/hxhx/actions/workflows/ci.yml/badge.svg)](https://github.com/fullofcaffeine/hxhx/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-0.44.0-blue)](https://github.com/fullofcaffeine/hxhx/releases)

This repository contains two products. Both have the MIT license.

- **`reflaxe.ocaml`** compiles Haxe 4.3.7 code to OCaml. The upstream Haxe compiler runs it as a [Reflaxe](https://github.com/SomeRanDev/reflaxe) target.
- **`hxhx`** is a Haxe compiler that is written in Haxe. Its goal is compatibility with Haxe 4.3.7.

`hxhx` depends on `reflaxe.ocaml`. Upstream Haxe and `reflaxe.ocaml` compile the `hxhx` sources to OCaml, and that OCaml code becomes the `hxhx` binary.

The project treats practical edit-compile-test latency as a product goal. A faster native build or a compiler-server cache counts as progress only when repeated builds give the same output as clean builds.

## Status

Last update: 2026-11-20. Neither product is ready for production.

| Product | Status today | Use it for |
| --- | --- | --- |
| `reflaxe.ocaml` with upstream Haxe | Preview. This is the most complete path. | OCaml output from Haxe programs, with results that you compare with upstream Haxe. |
| `hxhx` | Experimental. JavaScript output works for a [declared scope](docs/02-user-guide/HXHX_JS_NATIVE_SCOPE_1_0.md) (a written list of supported features). | Compiler experiments and contributions. |

### Measured progress

<!--
Update rule: change a number here only when its source changes.
- Parse oracle: npm run oracle:parse on main prints the totals. The baseline file scripts/oracle/parse-oracle-baseline.json can be lower.
- Typed oracle: npm run oracle:typed on main prints the totals. The baseline file is scripts/oracle/typed-oracle-baseline.json.
- Representation matrix: scripts/reflaxe-ocaml/representation-matrix-baseline.md
- Gate rows: the GitHub Actions history of the named workflow on main
Also change the "Last update" date.
-->

| Measure | Product | On `main` |
| --- | --- | --- |
| Parse oracle: field bodies that `hxhx` parses the same as upstream | `hxhx` | 1720 of 1850 (93.0%) |
| Parse oracle: files where each body matches | `hxhx` | 83 of 138 |
| Typed oracle: method signatures that `hxhx` types the same as upstream | `hxhx` | 1487 of 1671 (89.0%) |
| Representation matrix: cells with the same output as upstream | `reflaxe.ocaml` | 220 of 239 (92.1%) |
| Upstream unit suite (milestone F2) | `hxhx` | There is no pass count yet. The run stops at a macro call. |

The two oracles compare `hxhx` with upstream Haxe 4.3.7 on the `haxe` package of the standard library. [`scripts/oracle/README.md`](scripts/oracle/README.md) gives the method.

The representation matrix moves 16 value types through 15 boundaries. On `main`, 19 cells fail, and no cell prints a wrong value:

- 3 cells give OCaml that does not build.
- 16 cells stop with a named error.

[The baseline](scripts/reflaxe-ocaml/representation-matrix-baseline.md) shows each cell.

### Roadmap

The owner set these priorities on 2026-11-16. Work goes in this order.

| Order | Milestone | Exit condition | State |
| --- | --- | --- | --- |
| 1 | `reflaxe.ocaml` 1.0 | A declared scope works on upstream Haxe 4.3.7 with no known silent wrong output. | In progress |
| 2 | F1: frontend parity | The parse oracle and the typed oracle show that `hxhx` agrees with upstream. | In progress, measured |
| 3 | F2: unit suite on JavaScript | `hxhx` passes the upstream unit suite on the JavaScript target. | Not reached. Macro support blocks it. |
| 4 | F3: self-hosting | `hxhx` builds two native generations of `hxhx` and does not use upstream Haxe. | Not reached |
| 5 | Full1 | `hxhx` passes the upstream suites for [each target in the Full1 scope](docs/02-user-guide/compat/FULL1_TARGET_SCOPE.md). | Not started |

The plugin SDK, compiler customization, and new features for backends other than JavaScript wait for F2.

### Known limits

- `reflaxe.ocaml` can generate OCaml that does not build. Without `-D ocaml_build=native`, a failed OCaml build is only a warning, and `haxe` exits with 0.
- `hxhx` does not run all macros. The run of the upstream unit suite stops at a macro call.
- The `hxhx` typer rejects some valid programs.
- `hxhx --ocaml` does not compile ordinary programs yet. On 2026-11-18, it rejected a program with an empty `main`.
- The `hxhx` build uses a committed OCaml snapshot. Upstream Haxe and `reflaxe.ocaml` generate that snapshot from the `hxhx` sources.
- On `main`, the Gate 1 Lite check and the weekly upstream gates fail. The Full1 gate failed on each recent scheduled run.

The evidence is in the [architecture review](docs/00-project/ARCHITECTURE_REVIEW_2026_11_16.md) and the [goals](docs/00-project/NORTH_STAR_GOALS.md).

## Prerequisites

- Node.js and npm
- OCaml 5.2 or later, `dune`, and `ocamlfind`

The repository pins Haxe 4.3.7 in `.haxerc`. Lix installs that version, and `npx haxe` runs it.

macOS:

```bash
brew install ocaml dune ocaml-findlib
```

Linux, with opam:

```bash
sudo apt-get update
sudo apt-get install -y opam m4 pkg-config libgmp-dev
opam init -a --disable-sandboxing
opam switch create 5.2.1
eval "$(opam env)"
opam install -y dune ocamlfind
```

Then get the repository:

```bash
git clone https://github.com/fullofcaffeine/hxhx.git
cd hxhx
npm install
npx lix download
npx haxe -version
```

The last command prints `4.3.7`. If it prints a different version, run `npx lix download haxe 4.3.7`. Then run `npx lix use haxe 4.3.7`.

## Compile Haxe to OCaml

This procedure uses `reflaxe.ocaml` with upstream Haxe. It compiles one Haxe program to a native executable.

1. Make a directory for the program.

   ```bash
   mkdir -p /tmp/hello/src
   ```

2. Write this code to `/tmp/hello/src/Main.hx`.

   ```haxe
   class Main {
   	static function main() {
   		trace("Hello from OCaml");
   	}
   }
   ```

3. In the repository root, compile the program.

   ```bash
   npx haxe -cp /tmp/hello/src -main Main -lib reflaxe.ocaml \
     -D ocaml_output=/tmp/hello/out -D ocaml_build=native --no-output
   ```

4. Run the executable.

   ```bash
   /tmp/hello/out/_build/default/out.exe
   ```

The program prints `Main.hx:3: Hello from OCaml`. In a test on macOS, the compilation took approximately 20 seconds.

`-D ocaml_output=<dir>` is mandatory. It selects the directory for the generated OCaml. With `-D ocaml_build=native`, a failed OCaml build stops the compilation with an error. Without it, the compiler still builds, but a failed build is only a warning. To write the OCaml sources only, add `-D ocaml_no_build`.

In the repository, [`haxe_libraries/reflaxe.ocaml.hxml`](haxe_libraries/reflaxe.ocaml.hxml) connects `-lib reflaxe.ocaml` to the sources. Thus, run `npx haxe` from the repository root.

Next steps:

- To use `reflaxe.ocaml` from a project in a different directory, read [reflaxe.ocaml with upstream Haxe](docs/01-getting-started/REFLAXE_OCAML_WITH_UPSTREAM_HAXE.md).
- For the options, the `doctor` command, and the build and watch commands, read the [package README](packages/reflaxe.ocaml/README.md).
- For the supported scope, read the [1.0 contract](docs/00-project/REFLAXE_OCAML_1_0_CONTRACT.md).
- To call OCaml libraries from Haxe, read [OCaml-native mode](docs/02-user-guide/OCAML_NATIVE_MODE.md).

## Try hxhx

This procedure builds the `hxhx` binary and compiles a program to JavaScript.

1. Build `hxhx`. The build compiles the committed OCaml snapshot.

   ```bash
   HXHX_BIN="$(bash scripts/hxhx/build-hxhx.sh | tail -n 1)"
   "$HXHX_BIN" --version
   ```

2. Compile the program from the last procedure.

   ```bash
   HXHX_FORBID_STAGE0=1 "$HXHX_BIN" --js /tmp/hello/main.js -cp /tmp/hello/src -main Main
   ```

`hxhx` writes `main.js` and runs it with Node.js. It prints some status lines, then the output of the program (`Hello from OCaml`), and then `run=ok`. In a test on macOS, the build took approximately 45 seconds and the compilation took 1 second.

To write the file only, add `--hxhx-no-run`. `hxhx` also writes work files to `out_stage3` in the current directory.

If `hxhx` tries to call upstream Haxe, `HXHX_FORBID_STAGE0=1` stops the compilation. Thus, a successful compilation shows that `hxhx` did all the work. In this project, "stage0" is the name for upstream Haxe.

If `hxhx` rejects your program, compare the code with the [JavaScript scope](docs/02-user-guide/HXHX_JS_NATIVE_SCOPE_1_0.md). An error for a valid program is a known limit.

Next steps:

- [Quickstart: native lane](docs/01-getting-started/QUICKSTART_NATIVE.md) shows the lanes in which `hxhx` does all the compilation work.
- [Quickstart: compat lane](docs/01-getting-started/QUICKSTART_COMPAT.md) shows the lanes in which `hxhx` sends the work to upstream Haxe.
- [What works today](docs/01-getting-started/WHAT_WORKS_TODAY.md) lists each lane and its status.

## Other use cases

These use cases are experimental or deferred.

| Use case | State | Guide |
| --- | --- | --- |
| Run `reflaxe.ocaml` through `hxhx` | Not usable yet. Ordinary programs fail. | [reflaxe.ocaml with hxhx](docs/01-getting-started/REFLAXE_OCAML_WITH_HXHX.md) |
| Embed `hxhx` in a tool as a subprocess | Experimental | [Embedding](docs/02-user-guide/EMBEDDING.md) |
| Package a Reflaxe target as a native `hxhx` plugin | Experimental. New work waits for F2. | [Promote a Reflaxe target](docs/01-getting-started/PROMOTE_REFLAXE_TO_NATIVE.md) |
| Run Haxe macros with `hxhx` | Partial. The upstream unit suite stops at a macro call. | [Expression macros](docs/02-user-guide/HXHX_EXPRESSION_MACROS.md) |
| Compile to other targets with `hxhx` | Experimental. New features wait for F2. | [Builtin backends](docs/02-user-guide/HXHX_BUILTIN_BACKENDS.md) |
| One native target core for upstream Haxe and `hxhx` | Planned. This work waits for F2. | [Goals](docs/00-project/NORTH_STAR_GOALS.md) |

## Where to go next

| Question | Document |
| --- | --- |
| Which lane fits my goal? | [Choose your lane](docs/01-getting-started/CHOOSE_YOUR_LANE.md) |
| What does this term mean? | [Terms you must know](docs/01-getting-started/TERMS_YOU_MUST_KNOW.md), [Glossary](docs/00-project/GLOSSARY.md) |
| What are the goals and the priorities? | [Goals](docs/00-project/NORTH_STAR_GOALS.md), [Architecture review](docs/00-project/ARCHITECTURE_REVIEW_2026_11_16.md) |
| What does each CI gate show? | [CI gates](docs/00-project/CI_GATES.md) |
| Where is the full list of documents? | [Documentation map](docs/README.md) |

## Contribute

1. Read [CONTRIBUTING.md](CONTRIBUTING.md) and [AGENTS.md](AGENTS.md).
2. Install the Git hooks.

   ```bash
   npm run hooks:install
   ```

3. Before you open a pull request, run the guard checks.

   ```bash
   npm run ci:guards
   ```

4. If you change the `hxhx` parser, run the parse oracle.

   ```bash
   npm run test:oracle:parse
   ```

5. If the oracle count increases, increase the baseline in the same pull request.

Keep each pull request small. For the test commands, read [Testing](docs/01-getting-started/TESTING.md) and [Fast local validation](docs/01-getting-started/FAST_LOCAL_VALIDATION.md).

The project compares its behavior with upstream Haxe and does not copy upstream compiler sources. Before you contribute compiler code, read the [provenance policy](docs/00-project/PROVENANCE_POLICY.md).

## License

The license is MIT. See [LICENSE](LICENSE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
