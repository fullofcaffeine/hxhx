# Stage3 regular expressions: literals and `new EReg`

`Main.hx` builds regexes as literals (`~/b+/`, `~/o/g`, `~/[a-z]+/i`,
`~/^b/m`) and with `new EReg(pattern, flags)`. It calls `match`, `matched`,
`matchedLeft`, `matchedRight`, `matchedPos`, `matchSub` (with and without a
length), `replace` (first match, all matches, and `$1` group references),
`split`, and `map`, plus the static `EReg.escape`. The regexes are held in
locals, a static field, an instance field that is assigned again, and a
function parameter. A literal is also used directly as a call receiver and
as a call argument.

Before the fix, Stage3 emitted every regex value as the placeholder
`(Obj.magic 0)`. A statement that used a literal as a call receiver or
argument was dropped as a whole, because the placeholder made the
expression unsupported. The build succeeded, and the executable crashed on
the first `match`. `matchedLeft()`, `matchedRight()`, and `matchedPos()` also
returned an unapplied OCaml function, because the runtime versions of those
methods take a trailing unit argument that the generic call did not pass.

Stage3 passes the flags string to `EReg.create` unchecked. Flag behavior is
runtime scope: today `EReg.ml` interprets only `g` and `i`. The `~/^b/m` line
agrees with upstream only because OCaml `Str` always anchors `^` and `$` at
line boundaries; without `m`, upstream would print `false` and native `true`.
The `s` flag is ignored. Flag parity is tracked in Bead `haxe_ocaml-y2nv7`
(coordinate with PR #132), so this fixture does not prove that `m` works.

The fixture keeps each `match` in its own statement before `matched` reads
the result. Stage3 currently evaluates String concatenation operands right
to left (Bead `haxe_ocaml-b544p`), so a `match` and a `matched` in the same
concatenation would test that bug instead of `EReg`. The patterns are also
limited to cases where the OCaml `Str` translation in `EReg.ml` already
agrees with upstream Haxe; runtime pattern parity is tracked separately.

`test/fixtures/stage3_ereg_errors` is native-only. It pins two failures that
must stay catchable: an invalid pattern throws a Haxe String, and a method
call on an EReg held in `Dynamic` throws a named error (full Dynamic dispatch
is Bead `haxe_ocaml-m2wff`). Upstream cannot be the oracle there: its
`--interp` aborts on the invalid pattern without reaching `catch`, other
targets word the message differently, and it supports the Dynamic call.

`npm run test:m14:stage3-ereg` checks that upstream Haxe 4.3.7 prints
`expected.stdout`. It then builds the program with Stage3, checks that
`Main.ml` constructs every regex in the source with `EReg.create` and has no
placeholder outside function return tails, and
requires the native executable to print the same text.
