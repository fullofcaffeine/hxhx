This program checks primitive exception values and control flow in native Stage3 OCaml.
Run `npm run test:m14:stage3-exceptions` from the repository root.
The runner compares the same source with upstream Haxe and the independently written expected.stdout.

The checks cover handler order, rethrowing, mutation, shadowing, one-time payload evaluation, normal results, returns and nested loops.
Class identity and numeric catch compatibility remain separate unfinished requirements under haxe_ocaml-k93zp.
