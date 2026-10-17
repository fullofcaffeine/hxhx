# Native frontend host

This check builds the Haxe-authored parser, typer, and shared OCaml target into
a native executable. That executable compiles the same small source fixture as
stock Haxe. The check compares target plans, manifests, file hashes, generated
files, and runtime output. It also rejects retained legacy Stage3 emitters.

Run from the repository root:

```sh
npm run test:reflaxe-ocaml:native-program-host
```

To retain all artifacts, select a directory that does not yet exist:

```sh
REFLAXE_OCAML_NATIVE_PROGRAM_HOST_WORK_ROOT="$PWD/.tmp/native-host-check" \
  npm run test:reflaxe-ocaml:native-program-host
```

Every run builds fresh source. An existing output directory is rejected instead
of being treated as current evidence. The retained directory contains both stock
outputs, the native host, the native target output, and generation progress in
`native-host-progress.log`. Default runs retain artifacts on failure and remove
them on success.

The host build uses full dead-code elimination. All reachable frontend and target
operations remain; the native executable must still process the source fixture.
Large compiler and native builds use background scheduling. Reported build time
is diagnostic verification cost, not a native performance benchmark.

A pass proves this complete path for the fixture. It does not prove general
compiler compatibility, full Reflaxe or Genes promotion, self-hosting, or faster
iteration on representative projects. Those need their own acceptance evidence.
