# Nullable branch values through the shared OCaml target

This regression preserves the nullable argument behavior from `M14CallArgumentControlTest` as a direct shared-target prerequisite.
The source distinguishes null from zero, retains nullable values through locals and returns, and selects only the chosen branch.
The original instance-method regression remains required and unchanged.

Run from the repository root:

```sh
npm run test:reflaxe-ocaml:shared-nullable-values
```

The test first checks independent upstream Haxe results. It then requires both adapters to preserve the complete function inventory and identical target facts.
Both adapters preserve nullable Int arguments, returns, locals, conditional values, and comparisons with null.
The test requires declared runtime reasons and the exact runtime source bytes from the checked catalog.
It compiles an independent OCaml observer against the emitted functions and packaged runtime.
The observer checks null, zero, negative values, both 32-bit integer limits, and the established nullable representation.
The command also compiles through the complete standalone preprocessing lifecycle.
It builds both the standalone output and the shared program output, then runs the observer against each.
The focused adapter, native wrapper, packaging, and negative checks run in `npm run test:reflaxe-ocaml:target-definition`.

The target records each runtime operation by owning function and structural expression path.
Its final-output checks reject lost or unowned runtime references.
Physical source locations are unavailable in these facts; the report does not invent filenames or offsets.
Runtime file hashes cover exact UTF-8 bytes, including non-ASCII comments in the existing runtime.

Standalone compilation resolves runtime sources from the installed `reflaxe.ocaml` package.
The native wrapper currently requires `-D reflaxe_ocaml_runtime_directory=<installed reflaxe.ocaml std/runtime directory>` for programs that need runtime support.
The directory must contain the checked runtime manifest and its exact source files.
Automatic native installation asset discovery remains unfinished. Runtime-free programs do not require this setting.

Nullable Int must retain the standalone target's represented runtime value and null sentinel.
An OCaml option or a zero-as-null convention would be a different ABI and cannot replace that contract.
Runtime dependencies must come from the target's owned requirement and artifact paths; copying a private helper name is insufficient.

The native frontend and wrapper run under the upstream interpreter in this fixture; their emitted applications are native OCaml executables.
Full native frontend execution, receiver construction/capture, and original integration acceptance remain open.
