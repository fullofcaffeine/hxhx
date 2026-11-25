# Upstream source-position probes

These files are probes for upstream Haxe 4.3.7 source positions. `upstream.txt` is what upstream
printed for them. `test/M14MacroSourcePositionsTest.hx` checks `HxSourceRange` and `HxLineTable`
against it (bead `haxe_ocaml-9sj5p.2`, plan `docs/00-project/MACRO_SOURCE_POSITIONS_PLAN.md`).

- `M.hx` declares `M.p(e)`, which prints each argument's `min`, `max` and position text, and
  `M.bad`, which makes unusual positions with `Context.makePosition`. `Z.hx` makes a zero-width,
  an unknown, and a multi-line position.
- `A.hx` has a non-BMP prefix, an interpolated string, an escaped string, and an array literal.
  `B.hx` uses CRLF line ends, and `C.hx` uses lone CR line ends. `D.hx` has comments, an inactive
  branch with non-BMP text, calls, operators, a function, a `while` loop, and a regular
  expression. `E.hx` shows that upstream counts interpolation offsets in bytes. `F.hx` calls
  `M.bad`. `G.hx` has a multi-line argument and calls `Z.edge`.

Offsets depend on every byte, so these files must not change. `hxformat.json` turns the
formatter off here, and `.gitattributes` keeps the line ends.

Regenerate `upstream.txt` from this directory:

```bash
for m in A B C D E F G; do echo "== haxe -cp . -main $m --no-output"; haxe -cp . -main $m --no-output 2>&1; done > upstream.txt
```
