# Second-pass review: complete numeric literals in bootstrap compilers

## Outcome

The numeric-literal Bead can close. Both maintained compiler forms preserve the
full integer and floating-point values that previously lost digits:

- the committed stage0-free bootstrap compiler; and
- a native compiler built from the current Haxe-authored `hxhx` sources through
  `reflaxe.ocaml`.

## Independent expected behavior

Upstream Haxe 4.3.7 compiles the same fixture first. Its normalized runtime
output must match the reviewed `expected.stdout` file. The candidate compiler
does not generate its own expected values.

The fixture covers decimal and hexadecimal integers, negative values, signed
32-bit boundaries, digit separators, leading-dot floats, scientific notation,
and the long decimal value `0.69314718056`. The values `31`, `28`, and the long
decimal directly represent the digits that previously drifted in
`DateTools.DAYS_OF_MONTH` and `FPHelper.LN2` output. Those upstream fields are
private implementation details, so the durable regression protects the general
compiler behavior instead of coupling the test to private field access.

## Faithful observation boundary

The test does more than check parser tokens. It compiles a real Haxe program,
reads the numeric arrays from generated JavaScript, executes that JavaScript,
and compares its output with the independent oracle. It then compiles the same
program again and requires byte-identical JavaScript.

This protects the whole path that matters to users: source text, parsing,
compiler-carried numeric meaning, JavaScript emission, and runtime behavior.

## Two compiler forms

The stage0-free snapshot route passed again on current `main`.

The current-source route passed at `f09500606`: Haxe/Reflaxe generation
completed after about 2,044 seconds, Dune built 1,434 actions, and the resulting
compiler passed both JavaScript/value checks twice. A Git path audit proves that
no `packages/hxhx`, `packages/hxhx-core`, numeric fixture, or fixture-runner file
changed between that candidate and this closure. Later implementation work only
changed `reflaxe.ocaml` report identity and its evidence consumers, so another
hour-long rebuild would not test a new numeric-literal compiler input.

## Scope

This closes one bootstrap correctness regression. It does not prove every Haxe
numeric edge case, complete Full1, make Stage3 the authentic shared target, or
authorize a release. README Goals and readiness percentages therefore remain
unchanged.

The original `thinking:high` level was sufficient. The remaining work was an
evidence reconciliation across two existing compiler routes, with no competing
architecture or unclear semantic boundary. Oracle review was not needed.
