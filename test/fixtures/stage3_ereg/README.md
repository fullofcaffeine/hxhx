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

The fixture keeps each `match` in its own statement before `matched` reads
the result. Stage3 currently evaluates String concatenation operands right
to left (Bead `haxe_ocaml-b544p`), so a `match` and a `matched` in the same
concatenation would test that bug instead of `EReg`. The patterns are also
limited to cases where the OCaml `Str` translation in `EReg.ml` already
agrees with upstream Haxe; runtime pattern parity is tracked separately.

`npm run test:m14:stage3-ereg` checks that upstream Haxe 4.3.7 prints
`expected.stdout`. It then builds the program with Stage3, checks that
`Main.ml` constructs regexes with `EReg.create` and has no placeholder, and
requires the native executable to print the same text.
