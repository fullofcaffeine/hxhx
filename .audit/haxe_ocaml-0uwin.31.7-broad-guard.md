# Broad-guard disposition

The catch-runtime change passed its focused, independent-oracle, native
build/run, runtime-authority, inventory, inspection, formatting, typing, and
privacy checks.

The first `npm run ci:guards` attempt also passed the complete-program server
matrix, including its 30-request memory check:

```text
REFLAXE_OCAML_COMPLETE_PROGRAM_SERVER:PASS
rss_after_20_kb=917312 rss_final_kb=894880
```

That run later exposed a separate command-line defect: two planner fixtures
imported Reflaxe lifecycle types without loading the `reflaxe` library. Adding
the missing `-lib reflaxe` flag made both exact commands and their chained
planner suite pass.

The required clean full rerun reached the same complete-program matrix but
failed its memory-only final-ten plateau check:

```text
owned server RSS did not approach a plateau in the final ten requests
after20=871056KB final=960848KB
```

All semantic clean/warm comparison cases printed before that check passed. The
repository has no retry allowance for this memory gate, so this result was not
replaced by repeated attempts. `haxe_ocaml-850ii.33.5.1` now owns the
measurement divergence and must determine whether it is retained compiler
state or unstable RSS/garbage-collection evidence.

`haxe_ocaml-0uwin.31.7` therefore remains open. Its implementation is ready,
but its broad-guard acceptance is not yet complete.
