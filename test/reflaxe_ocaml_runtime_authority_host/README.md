# Runtime validation in a compiled host

The shared OCaml target must validate private runtime calls and runtime source files from ordinary compiled Haxe.
These checks must not depend on macro, eval, or Reflaxe runtime compilation defines.

Run the focused contract:

```sh
bash scripts/ci/reflaxe-ocaml-runtime-authority-host-test.sh
```

The script compiles a Neko executable and runs it against the checked OCaml runtime catalog.
It uses the existing runtime-use authorities and manifest loader.
The fixture verifies one planned helper reference and rejects stale plans, wrong roots or symbols, duplicate references, unchecked names, and missing final output.
It loads and verifies the real runtime source manifest, resolves the exact nullable runtime root, and rejects missing and tooling-only application dependencies.
Plan locations in this fixture are explicitly synthetic test data.

The command runs within the target-definition aggregate.
It proves availability and validation outside the interpreter; it does not prove nullable lowering, native OCaml host execution, or a rebuilt hxhx compiler.
The nullable integration regression and the original instance-method acceptance remain required.
