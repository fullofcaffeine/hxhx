# Stage3 String methods on non-ASCII text

`Main.hx` runs the String API on `"héllo😀漢"`, which mixes one-, two-, three-
and four-byte UTF-8 characters. Upstream Haxe 4.3.7 eval counts Unicode code
points, so `length` is 7, `charAt(1)` is `é`, and `charCodeAt(5)` is 128512.

Before the fix, the native program counted bytes. It printed `length=13`,
split `é` into two one-byte Strings, upper-cased only ASCII letters, and wrote
ill-formed UTF-8 to stdout.

The fixture covers `length`, `charAt`, `charCodeAt`, `fromCharCode`,
`indexOf`, `lastIndexOf`, `substr`, `substring`, `split`, `toUpperCase`,
`toLowerCase`, `StringTools.fastCodeAt`/`unsafeCodeAt`/`lpad`/`rpad`/`trim`/
`startsWith`/`endsWith`/`contains`/`isSpace`/`htmlEscape`, String comparison,
`StringBuf.length`, and a string longer than the runtime's cache threshold.
It also upper- and lower-cases every code point and prints a checksum, so the
runtime case table must match upstream for all 2224 code points that change.

`npm run test:m14:stage3-string-methods` checks that upstream prints
`expected.stdout`, then builds the program with Stage3 and requires the native
executable to print the same text.

Stage3 cannot run two parts yet, so they live in the reflaxe.ocaml portable
fixture `test/portable/fixtures/string_unicode_code_points`, which runs this
`Main` too:

- `for (c in s)` and `for (k => c in s)` never finish, because Stage3 emits the
  iterator's `offset++` field increment as a constant (haxe_ocaml-jyy95).
- Stage3 replaces every `StringTools.replace(...)` call with `""`.
