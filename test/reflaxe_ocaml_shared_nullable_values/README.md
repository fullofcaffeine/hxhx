# Nullable branch values through the shared OCaml target

This regression preserves the nullable argument behavior from `M14CallArgumentControlTest` as a direct shared-target prerequisite.
The source distinguishes null from zero, retains nullable values through locals and returns, and selects only the chosen branch.
The original instance-method regression remains required and unchanged.

Run from the repository root:

```sh
node_modules/.bin/haxe test/reflaxe_ocaml_shared_nullable_values/test.hxml
```

The test first checks independent upstream Haxe results. It then requires both adapters to preserve the complete function inventory and identical target facts.
Conditional expressions are now supported, but nullable signatures and conversions still do not enter the shared target.
The test requires declared runtime reasons and the exact runtime source bytes from the checked catalog.
It compiles an independent OCaml observer against the emitted functions and packaged runtime.
The observer checks null, zero, negative values, both 32-bit integer limits, and the established nullable representation.
It already passes against the existing standalone compiler output.
The shared-target command remains red and is not part of a passing aggregate yet.

Nullable Int must retain the standalone target's represented runtime value and null sentinel.
An OCaml option or a zero-as-null convention would be a different ABI and cannot replace that contract.
Runtime dependencies must come from the target's owned requirement and artifact paths; copying a private helper name is insufficient.

The native frontend runs under the upstream interpreter in this fixture. Full native frontend execution, receiver construction/capture, and original integration acceptance remain open.
