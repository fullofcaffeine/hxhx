# EReg / Regex Strategy (M11)

Haxe’s `EReg` API is used by:

- user applications directly, and
- parts of the Haxe ecosystem / tooling (and `hxhx` itself, which scans
  source text with `EReg.map`).

Upstream Haxe ships `EReg` as a **target-implemented API**. The fallback
implementation throws a `NotImplementedException`, so the OCaml target must ship
its own runtime.

## What you can rely on

On non-ASCII text, `EReg` behaves like upstream `haxe --interp` (eval):

```haxe
final s = "héllo😀漢l";
final r = ~/l+/;
r.match(s);
r.matchedPos();               // {pos: 2, len: 2}, counted in characters
s.substr(r.matchedPos().pos); // "llo😀漢l"
~/./g.map("é漢😀", m -> "[" + m.matched(0) + "]"); // "[é][漢][😀]"
~/É+/i.match("xéÉé");         // true, matched(0) == "éÉé"
```

- Every position counts Unicode code points, the same unit `String` uses, so
  `matchedPos` values work with `substr`, `charAt` and `substring`.
- `.`, `[...]`, `[^...]`, `\D`, `\W`, `\S` and a quantified non-ASCII literal
  (`😀+`) match whole characters. Upstream compiles every pattern in
  Unicode mode, with or without the `u` option, and so does this runtime.
- `i` folds ASCII letters and non-ASCII letters with Unicode simple case
  mapping (`é`/`É`, `ж`/`Ж`, `σ`/`Σ`). Like upstream, one character never
  matches several (`straße` does not match `STRASSE`).
- `matchSub(s, pos, len)` reads `pos` and `len` as code points, and only
  matches inside `[pos, pos + len)`. **This differs from upstream eval on
  purpose**: eval reads them as bytes while `matchedPos` returns code points,
  so a loop that feeds `matchedPos` back into `matchSub` repeats one match
  forever after multibyte text. JavaScript and the other Unicode targets use
  characters, which is what this runtime does.
- After an empty match, global `split`, `replace` and `map` step over one
  whole character. Upstream steps one byte, which cuts non-ASCII characters
  in half (and makes `map` fail). Otherwise these follow upstream's
  algorithm, so ASCII results are identical, including upstream's quirk that
  `~/x*/g.split("ab")` gives `["", "a", ""]`.
- An unmatched optional group gives `null` from `matched(n)`, as upstream.

The portable fixture `test/portable/fixtures/ereg_unicode_code_points` checks
all of this against upstream output.

## How it works

- Extern surface: `packages/reflaxe.ocaml/std/ocaml/_std/EReg.hx`
- Runtime implementation: `packages/reflaxe.ocaml/std/runtime/EReg.ml`

The runtime matches with OCaml’s standard `Str` library. `Str` is available on
every OCaml install, so no extra dependency is needed, but it is byte based
and uses Emacs-style syntax. So `new EReg(pattern, options)` translates the
Haxe (PCRE-style) pattern into `Str` syntax, in one of two modes:

1. **ASCII mode**, used when the subject string is pure ASCII. The pattern
   maps almost one-to-one, `i` uses `Str`'s own case folding, and byte offsets
   already are character offsets. This keeps the common case as fast as
   before.
2. **UTF-8 mode**, compiled the first time a subject contains non-ASCII text.
   Each `.` or class becomes a set of code points, written as alternative
   UTF-8 byte sequences (`[\xc3][\xa0-\xbc]` and so on). A quantified
   multi-byte literal is wrapped in a group so `+` repeats the whole
   character. Case folding is written into the pattern, because `Str`'s
   folding table is Latin-1 and would treat the UTF-8 lead bytes `0xC3` and
   `0xE3` as the same letter.

The extra groups shift `Str`'s group numbers, so each translation keeps a
small table from Haxe group numbers (`matched(1)`) to `Str` group numbers.
The same table implements `(?:...)` non-capturing groups.

Matches are found as byte offsets. They become code points only where Haxe
code sees a position (`matchedPos`, `matchSub`), using the String runtime's
code-point layout (`HxString.layout`, `byte_offset`, `index_of_byte`), which
caches long strings. Text results (`matched`, `matchedLeft`, `split`, …) are
byte slices taken at character boundaries.

Other translated syntax: `\d \w \s` (ASCII sets), `\n \r \t \f \v \e`,
`\xhh` and `\x{h...}`, back references `\1`–`\9`, `^`, `$`, `\b`, `|`, `*`,
`+`, `?`, and the `g`, `i`, `s` options.

## Known limitations

Tracked by `haxe_ocaml-2lqqu`:

- Unicode properties for `\w`, `\d`, `\s` and `\b`. Upstream matches `é` and
  `漢` with `\w`; this runtime only matches ASCII word characters.
- `{m,n}` counted repetition (the braces are literal), lazy quantifiers
  (`*?` is matched greedily), lookahead/lookbehind, named groups, inline
  flags, and `\B`. Unsupported group syntax raises an error when the `EReg` is
  created.
- `^` and `$` always match at line boundaries, as if `m` were set.
- Ranges with more than 12288 code points are not case folded under `i`.
- Ill-formed UTF-8 (possible only from OCaml file or process input): a stray
  continuation byte is not matched by `.` on its own.

Stage3 (the native `hxhx` emitter) cannot run `EReg` programs yet; it emits
regex values as placeholders (`haxe_ocaml-r4ylw`).

## Future direction (1.0)

If the `Str`-based approach becomes a blocker, the planned path is:

1. Keep the Haxe API surface stable (`EReg` in Haxe stays the same).
2. Replace the matcher with a code-point engine or a PCRE binding tier, and
   measure it against the `Str` ASCII fast path on `hxhx`'s own source scans.
3. Expand portable fixtures to cover the additional semantics.
