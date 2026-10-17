# Try results and typed catches

This fixture checks normal try results, ordered Int and String catches, and returns from try and catch bodies. No statements after those returns may execute.

The upstream Haxe expectation is retained in `expected.stdout`. The compiler's source syntax, typing, and shared lowering checks pass. Native C++ handler emission remains unfinished under `haxe_ocaml-qrk0u`; the full runtime test must pass before this fixture provides native acceptance evidence.

Run the upstream program with `npm exec -- haxe -cp test/oracle/source_try_control_seed/src --run Main`.
Run the native contract with `npm exec -- haxe test/m14_source_try_control_test.hxml`.
Run the focused structural checks with `haxe test/m14_source_try_syntax_test.hxml` and `haxe test/m14_source_try_typing_test.hxml`.
