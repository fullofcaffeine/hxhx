# Unicode code points in the OCaml EReg runtime

Upstream Haxe 4.3.7 eval counts `EReg` positions in Unicode code points, and
`.` or a character class matches one whole character. The OCaml runtime
matches with OCaml's byte-based `Str` library. Before this fixture, on
`"héllo😀漢l"`, `~/l+/` reported `matchedPos().pos == 3` (upstream: 2), and
`~/./g` split `é` into two ill-formed one-byte matches. Because `String`
methods count code points, `s.substr(r.matchedPos().pos)` cut the wrong place.

`Main` covers `matchedPos`, `matchedLeft`, `matchedRight`, `matchSub` with a
position and a length, `split`, `replace`, `map`, `.` with and without `s`,
negated classes, classes with non-ASCII members and ranges, quantified
multi-byte literals, `(?:...)` groups, `\x{...}` escapes, case-insensitive
matching on non-ASCII text, back references and alternations over non-ASCII
groups, counted repetition (`{m,n}`), one `EReg` used on ASCII, then
non-ASCII, then ASCII subjects, `matchSub` at the end and with an empty
window, `replace` keeping the previous match, and a subject longer than the
String runtime's cache threshold. Every line it prints matches upstream:

```sh
haxe -cp test/portable/fixtures/ereg_unicode_code_points/src --run Main
```

`PortableMain` runs `Main` and then prints five OCaml-only lines, where
upstream eval has no self-consistent value or the runtime deliberately
differs:

- `matchSub` reads its position and length as code points, like
  `matchedPos`. Upstream eval reads them as bytes, so feeding `matchedPos`
  back into `matchSub` repeats one match forever after multibyte text.
- After an empty global match, the runtime steps one whole character.
  Upstream eval steps one byte, so on non-ASCII text `split` and `replace`
  cut characters in half and `map` stops with a PCRE error. The runtime
  otherwise follows upstream's algorithm, which is why `split` also drops the
  last character here, exactly as upstream does on ASCII (`/a/` for `"ab"`).
- Syntax the runtime cannot translate (`(?=`, `\A`, `\B`, unknown letter
  escapes, a counted capturing group, or a back reference that needs more
  than nine internal groups) raises when the `EReg` is created. Upstream
  supports most of these, so there is no upstream value.
- `\W` matches `é` here: `\w`, `\d` and `\s` are ASCII sets, while upstream
  uses Unicode properties (`haxe_ocaml-2lqqu`). `matchSub` out of range
  returns `false`; upstream stops the program with a PCRE error.

Stage3 cannot run this program yet: it emits `EReg` values as a placeholder
(`haxe_ocaml-r4ylw`).

Run it from the repository root:

```sh
PORTABLE_FIXTURE_ALLOWLIST=ereg_unicode_code_points bash scripts/test-portable.sh
```
