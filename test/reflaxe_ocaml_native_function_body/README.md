# Native function-body adapter regression

Run `haxe test/reflaxe_ocaml_native_function_body/test.hxml` from the repository
root with the pinned libraries and Dune installed. The existing
`npm run test:reflaxe-ocaml:target-definition` command also runs this fixture.

The source declares a local, reads it, shadows it inside a block, then reads
the outer local again. Native `hxhx` previously rejected this nonempty function
before target generation. The standalone target already supported its body.

The fixture parses and types the source with the Haxe-authored native compiler
modules. It compares the normalized function identity and OCaml syntax with
the stock-Haxe adapter for the same source. It then generates, builds, and runs
the application through the shared standalone target. Execution succeeds with
empty stdout; the identity and syntax comparisons detect a dropped body.

The negative checks reject missing declarations, duplicate identities, escaped
block locals, foreign function locals, stale bodies, uninitialized locals,
mutation, returns, calls, and conditional statements. A repeated valid request
checks that rejection does not change later results.

Unused Haxe locals remain valid. The generated Dune stanza leaves OCaml warning
26 visible but does not promote it to an error. Other diagnostics retain the
normal Dune policy.

This test runs the compiler modules under the Haxe interpreter and executes the
generated application natively. It does not rebuild the complete native `hxhx`
binary or prove the recursive standard-library workload. Calls, arguments,
return values, control flow, and runtime requirements remain separate work.
