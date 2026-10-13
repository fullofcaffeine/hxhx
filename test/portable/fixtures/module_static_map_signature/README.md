# Generic map helpers in recursive modules

A helper such as `count<T>(values:StringMap<T>):Int` uses the map's existing
boxed storage. Its exported OCaml signature must retain that storage when
its module depends on another module that calls back into it.

This fixture calls the same helper with Int, String and Bool maps and with
null. It also reads the concrete values after the calls. The native executable
must match the written expectations and Haxe/eval output.

The Boolean check uses typed equality. Direct printing of a nullable Boolean
map value has a separate existing defect, tracked by `haxe_ocaml-nnshx`.

The macro checks the exported map type. It rejects bare generic arguments and
generic results: they need their own call contract, not permission borrowed
from a map declaration. Existing generic declaration tests check exact method
parameter ownership and unknown-type rejection.

Run `PORTABLE_FIXTURE_ALLOWLIST=module_static_map_signature bash scripts/test-portable.sh`
from the repository root.
