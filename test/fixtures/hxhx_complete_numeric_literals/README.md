# Complete numeric literals

This fixture protects the `hxhx` bootstrap compiler. It does not make a claim
about the standalone Haxe-to-OCaml target.

The source uses decimal integers, hexadecimal integers, negative values,
32-bit boundaries, decimal separators, float separators, leading-dot floats,
and scientific notation. The test compiles the same source with upstream Haxe
4.3.7 and with `hxhx`. Both programs must produce the reviewed line in
`expected.stdout`.

The test also reads the generated JavaScript arrays and compiles the candidate
twice. This catches lost digits before runtime and checks deterministic output.

Use the quick stage0-free bootstrap path during ordinary compiler work:

```bash
npm run test:m14:hih-complete-numeric-literals
```

Use the current-source path when qualifying a new native compiler build:

```bash
npm run test:m14:hih-complete-numeric-literals:current-source
```

The current-source command is intentionally separate because it rebuilds the
large compiler through `reflaxe.ocaml`.
