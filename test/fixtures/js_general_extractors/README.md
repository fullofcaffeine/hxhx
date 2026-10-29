# General switch extractors

Run `haxe test/m14_js_general_extractor_runtime_test.hxml` from the repository root.
This strict runtime test currently fails under `haxe_ocaml-l0oh8`.
Upstream Haxe passes the same source and its independently stated assertions.

An extension method runs first. A later extractor calls an ordinary function
and matches its enum result. Assertions check selected values, captured results,
fallback behavior, call order, and exactly one call per selected extractor.

The required switch integration test separately checks the current explicit
rejection. That negative check does not count as runtime support. When general
extractors work, replace the negative check with this strict runtime command.
