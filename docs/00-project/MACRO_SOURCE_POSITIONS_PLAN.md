# Macro source positions: contracts before a representation change

Status: reviewed. Bead: `haxe_ocaml-9sj5p.2`. The decisions in section 5 come from the
independent Fable review of 2026-11-24, which the owner's standing rule delegates; none needed
the owner. Positions PR 1 (section 6) is the first code. It adds new files only.

This document states the five contracts that the bead requires before `HxExpr` or the parser
change, the decisions, and the order of work.

## 1. Why this is needed

A project macro receives its arguments as `haxe.macro.Expr` values. Every `Expr` has a `pos`.
Upstream Haxe 4.3.7 gives each syntax occurrence its own exact range in its own file. Macros
use these ranges: they report errors at an argument, compare positions, or return syntax that
keeps the positions of another file. hxhx cannot do this today:

- `HxPos` records a start only: an index, a line, and a column (`packages/hxhx-core/src/HxPos.hx`).
  It has no end and no file.
- Only 13 of the 48 `HxExpr` constructors carry an `HxPos`. Constants, identifiers, calls,
  fields, array and object literals, and operators carry none. `ENull`, `EThis`, and `ESuper`
  are singleton values, so two occurrences cannot even be told apart.
- `MacroSyntaxExport.argument` (`packages/hxhx-core/src/MacroSyntaxExport.hx`, line 49) fails
  when the argument's root has no position. That is why `Macros.tally(["alpha", "beta"])` in
  `test/fixtures/project-macro-reification` fails on current sources, and why constant
  arguments use a placeholder position.
- `MacroSyntaxExport.convert` (lines 59-65) gives a child without its own position its
  parent's position.
- Exported positions are zero-width (`min == max`), because no node has an end.
  `MacroSyntaxPositions.resolve` (lines 54-58) accepts only zero-width positions and keys on
  the start.
- A returned position that this call did not export is dropped. The importer then uses the
  first argument's start or `HxPos.unknown()` (`MacroSyntaxImport.hx`, lines 41-47).
- Tokens already have an exclusive end (`HxToken.endIndex`, bead `haxe_ocaml-9sj5p.1`), but
  the parser does not pass it to syntax nodes.

The bead also asks that a returned macro expression keep its own position, including positions
in other files.

## 2. How upstream Haxe 4.3.7 behaves

All citations are `git -C ~/workspace/code/haxe show 4.3.7:<path>`. The numbers below come from
upstream probes recorded in `test/fixtures/macro_source_positions/upstream.txt`.

- **The position type.** `pos = { pfile; pmin; pmax }` (`src/core/globals.ml`, lines 1-3). The
  unknown position is `null_pos = { pfile = "?"; pmin = -1; pmax = -1 }` (line 36).
- **Offsets count Unicode code points.** The lexer uses `Sedlexing.Utf8` (`src/syntax/lexer.ml`,
  lines 20-21). `mk_tok` and `mk` set `pmin = lexeme_start` and `pmax = lexeme_end`
  (lines 297-301). Sedlex counts code points, so a non-BMP character is one unit, not two
  (UTF-16) or four (UTF-8 bytes). `pmax` is exclusive. Probe: in `A.hx`, `base` after a string
  holding a non-BMP character is 59-63, `A.hx:3: characters 23-27`.
- **Token ranges.** A string token covers the written text, with quotes and escapes; its value
  is unescaped (lines 464-473). Probe: `"e\n\"x"` is 102-110, eight code points. A
  regular-expression token ends at the closing `/` and excludes the flags, because `lexeme_end`
  is read before the flags (line 624). Probe: `~/a\/b/gi` is 284-291.
- **Line breaks in `.hx` files.** The lexer's `newline` (lines 180-183) records the offset after
  each break. `\r\n` is one break of two code points, and a lone `\n` or a lone `\r` is one
  break (lines 385-386). Probes: CRLF `B.hx` puts `base` at 47-51, line 3, `characters 9-13`;
  lone-CR `C.hx` puts it at 45-49, line 3. `resolve_pos` (lines 213-245) is used only for files
  the lexer never read, and it also consumes the character after a lone `\r`.
- **Lines and characters.** `find_line` takes the last line start at or before the offset
  (lines 185-210), so a negative offset is on line 1. `get_pos_coords` and `get_error_pos` print
  1-based columns (lines 270-290): `(unknown)` when `pmin = -1`, `character c` for a zero-width
  range, `characters a-b` on one line, and `lines a-b` across lines. An unreadable file has one
  line. Probes: `Nope.hx:1: characters 6-3` (min 5, max 2, no such file), `:1: characters 1-4`
  (empty file name), `A.hx:1: characters -4-4` (min -5), `G.hx:3: lines 3-5`.
- **Composite positions.** `punion` keeps the first position's file and takes the smaller
  `pmin` and the larger `pmax` (`src/core/ast.ml`, lines 449-452). A constant has its token's
  range (`src/syntax/grammar.mly`, line 1412). An array literal spans `[` to `]` (line 1231):
  `[null, null, 1]` is 121-136 with `1` at 134-135. A call spans its callee to `)`
  (line 1570): `this1(null, (base))` is 129-148, its callee 129-134.
- **Conditional compilation.** Upstream lexes inactive branches too (an invalid token there,
  such as an emoji identifier, is still an error), and the parser drops their tokens
  (`src/syntax/parserEntry.ml`, lines 259-326). Positions therefore count the original file text.
  Probe: in `D.hx`, an inactive branch with non-BMP text and a comment come before `base` at
  106-110.
- **Interpolation happens at typing, not parsing.** A single-quoted string is a constant token.
  `format_string` (`src/typing/typer.ml`, from line 733) splits it while typing and places each
  part inside the literal. A macro therefore sees the raw constant. Quirk: those inner offsets
  come from `String.unsafe_get` on the string value, so they count bytes, not code points
  (probe `E.hx` reports `lines 3-4` for a part on line 3).
- **Macro positions are kept as given.** `Context.getPosInfos` and `Context.makePosition` read
  and build `{min, max, file}` (`src/macro/macroApi.ml`, lines 1981-1986). Upstream accepts
  `min > max`, a negative `min`, and an empty file name. A returned expression keeps whatever
  position it carries, in any file.

## 3. The contracts

Each contract says what must be true, who owns it, and how a violation fails. Section 4 maps
each one to the current code.

### C1. Source ownership

- Each authored syntax occurrence owns exactly one source range, `HxSourceRange`: a file, a
  start offset, and an exclusive end offset (C3 gives the unit). This covers every expression
  occurrence, leaves included.
- Two occurrences never share a range or a value. A repeated `null`, `this`, or `1` is a
  separate occurrence with its own range.
- Ranges follow upstream's composition rules (section 2): a token's range for a leaf, and the
  first-to-last token union for a composite.
- The parser owns the range. It sets the range when it builds the node, from its own tokens.
  No later stage searches the source text, transfers a range between equal spellings, or keeps
  a side table keyed by node identity or child path.
- A node that has no authored source is not given a range. It carries a provenance instead
  (C4).
- Failure policy: an admitted node kind (section 5, D9) without a range fails export, with an
  error that names the node. During the migration, kinds that are not yet admitted keep the
  current inheritance of the parent's position (`MacroSyntaxExport.convert`, lines 59-65)
  through one named list; the last step removes that list.
- Positions outside expressions, such as metadata entries and `Var.namePos`, are out of scope.
  A macro that needs one fails explicitly.

### C2. Recursive children

- A node holds its own range, and its children hold theirs. A range is immutable data inside
  the node, so it travels with the node through every copy and rebuild.
- A parent range covers the ranges of its authored children, as with upstream `punion`. A test
  checks this for every admitted node kind.
- A rewrite that rebuilds a container with changed children keeps the container's range when
  the container itself is still the authored node. The rebuilt children keep their own ranges
  (`ExprMacroExpander` already promises this for nodes that have positions today).
- A rewrite that creates a new container gives it a derived provenance (C4). It does not reuse
  a child's range as its own.
- A rebuild that drops a range gives no range, and the consumer that needs one fails
  explicitly (D1).

### C3. Original-source Unicode offsets

- Unit: Unicode code points (scalar values) from the start of the original file text, before
  conditional filtering. The end is exclusive. This is upstream's unit.
- The compiler computes offsets on hosts whose `String` indexes by code point: the OCaml
  runtime (`packages/reflaxe.ocaml/std/runtime/HxString.ml`) and the interpreter. The macro host
  does not: its runtime counts bytes
  (`packages/hxhx-macro-host/bootstrap_out/runtime/HxString.ml`). Rule: the macro host never
  computes an offset. Offsets cross the wire as integers.
- Conditional filtering keeps code-point offsets. `HxConditionalCompilation` replaces inactive
  text with spaces, one per character, and keeps line breaks
  (`HxConditionalCompilation.hx`, lines 441-446). Unlike upstream, it does not lex inactive
  branches, so an invalid token there is not reported.
- Lines and columns come from `HxLineTable`, which follows the lexer's `newline` rule:
  `\r\n` is one break of two offsets, and a lone `\n` or a lone `\r` is one break. `HxLexer`
  does not treat a lone `\r` as a break (`HxLexer.hx`, lines 96-101), so `HxPos.line` can
  disagree there. The line table is the authority, and a test covers lone CR.
- A string token's range covers its written text. A regular-expression token's range ends at
  the closing `/` and excludes the flags. The decoded value never decides a range.
- Required tests (from the bead): nested and repeated syntax, comments between tokens, escaped
  strings, Unicode and non-BMP text before the node, inactive conditional branches before the
  node, and rebuilt children.

### C4. Rewrite provenance

Every node's position is one of these kinds:

| Kind | Meaning | Range |
| --- | --- | --- |
| Authored | written in a source file and built by the parser | its own (C1) |
| Derived | built from an authored node by a named rewrite, such as a parser desugaring, regex lowering, or a typer lowering | the authored node's range, plus the rewrite's name |
| MacroResult | returned by a macro | the position the macro gave, in any file |
| Synthetic | made by the compiler with no source | none; carries the reason |

- **Every rewrite states the kind** of each node it creates. Today the rewrites include
  single-quote interpolation in the parser, `ERegexLiteral` lowering, `EDiscardThen`,
  `ELoweredControl`, macro reification lowering, and the macro pass's call replacement.
- **A macro result keeps its own position, as given.** The only check is the wire shape: two
  integers and a string. Any values are kept, as upstream keeps them; `min = -1` means
  unknown. This includes positions in another file, such as the macro's own source or a
  position from `Context.makePosition`. The importer no longer drops positions it did not
  export.
- **A diagnostic in a macro result reports that file**, through the compilation-level line
  tables (D4).
- **Interpolation.** hxhx keeps interpolating in the parser for now (D7). Until the parser
  stream's authored-mode node lands, macro export of an interpolated single-quoted string
  fails explicitly. Afterwards it exports the raw constant, and the concatenation is marked
  Derived.

### C5. Parse cache and fingerprints

- **The parse cache key changes with the representation.** The key already includes the
  original source, the filtered source, and the parser configuration
  (`CompilationServerSourceCacheRequest.hx`, lines 126-137; the comment there notes that
  inactive Unicode can change positions without changing filtered text). The first
  representation change bumps `ParserStage.cacheConfigurationRevision()`
  (`hxhx-parser-schema-v12`, `ParserStage.hx` line 297) to v13, so a server never reuses a
  module parsed without ranges.
- **The integrity revision includes every new range** from that same first representation
  change. `ParsedModuleIntegrity` already adds each field and function position
  (lines 112-117), so a mutated range is caught before reuse.
- **No identity split yet (D5).** `TypedBodyFingerprint` adds the positions of the nodes that
  own one (lines 37-44), and its identities serve freshness and capture checks. It keeps
  ignoring the new ranges until the last step decides whether some consumers need an
  occurrence identity.
- **A whitespace-only edit changes ranges.** Through the parse cache key it invalidates the
  parsed module. Upstream's server re-types a module after any edit, so hxhx may be stricter but
  not looser.
- **Plugin cache keys stay as they are.** Project-macro plugin keys bind source files by digest,
  not by syntax. Ranges do not change them.

## 4. Where the current code stands

| Contract | Current fact | Where |
| --- | --- | --- |
| C1 | 35 of 48 expression constructors own no position; `ENull`, `EThis`, and `ESuper` are singletons | `HxExpr.hx` |
| C1 | export fails for arguments whose root owns no position; children inherit the parent's | `MacroSyntaxExport.hx`, lines 49 and 59-65 |
| C2 | rebuilt containers keep positions they already own | `ExprMacroExpander.rewriteExpr` |
| C3 | offsets are code points in the compiler; the macro host counts bytes; no end on syntax nodes | `HxPos.hx`, `HxToken.endIndex`, both `HxString.ml` |
| C3 | the conditional filter keeps offsets; the lexer ignores a lone CR | `HxConditionalCompilation.hx`, `HxLexer.hx` |
| C4 | interpolation happens in the parser: `'a$b'` parses as `EBinop(+, EString(a), ...)` | `HxParser.hx`, lines 1911-1913 |
| C4 | foreign macro-result positions are dropped; `resolve` keys on a zero-width start | `MacroSyntaxImport.hx`, lines 41-47; `MacroSyntaxPositions.hx`, lines 54-58 |
| C5 | the parse cache key and the integrity revision exist; fingerprints include positions | `CompilationServerSourceCacheRequest.hx`, `ParsedModuleIntegrity.hx`, `TypedBodyFingerprint.hx` |

## 5. Decisions (Fable review 2026-11-24)

- **D1. Representation.** Each constructor gets a trailing optional `?range:HxSourceRange`. It
  becomes mandatory in the last step. Short patterns and constructor calls keep compiling:
  `ELambda(args, body, ?signature)` (`HxExpr.hx`, line 151) is the precedent. A rebuild that
  drops the range gives `null`, and the consumer fails explicitly. A wrapper node is rejected,
  because it breaks nested patterns silently.
- **D2. Singletons.** `ENull()`, `EThis()`, and `ESuper()`, with the same optional range. This
  is a separate mechanical pull request after the parser stack lands, because about 433
  places match them and a bare `case ENull:` stops compiling.
- **D3. Units.** Code points with an exclusive end. `\r\n` is two offsets and one break. A lone
  `\r` is a line break (`lexer.ml`, line 386). Upstream's byte-counted interpolation offsets are
  not reproduced.
- **D4. File identity.** The plain file string as upstream spells it: the class-path entry
  joined with the module path, for example `A.hx`. It is not normalized. One lazy
  compilation-level map goes from file to line table. An unreadable file reports line 1.
- **D5. Identity.** No split now. `TypedBodyFingerprint` stays without ranges until the last
  step. `ParsedModuleIntegrity` includes ranges from the first representation change.
- **D6. Conditional compilation.** Keep the offset-preserving text filter
  (`HxConditionalCompilation.hx`, lines 441-446). Probe: `base` after an inactive branch is at
  106, its code-point index.
- **D7. Interpolation.** Do not move it to typing now. Until the parser stream's authored-mode
  node lands, macro export of an interpolated single-quoted string fails explicitly.
  Afterwards it exports the raw constant, with the concatenation marked Derived.
- **D8. Sequencing.** The macro stream writes every step. PR 1 adds new files only and can
  open now. PR 2 changes `HxExpr.hx` and `HxParser.hx`, so it lands after #275 and the
  interpolation branch (`HxParser.hx` lines 1911-1913 are in both). If that stack takes more
  than two days, PR 2 branches from the stack's tip.
- **D9. First admitted surface.** `EString` (not interpolated), `EInt`, `EFloat`, `EBool`,
  `EIdent`, `EArrayDecl`, and `ECall`. `null` and `this` wait for D2.
- **D10. Lost notes.** The bead refers to `pr92-expression-occurrence-design.md`, which is not
  in the repository or its history. This plan replaces it.

## 6. Order of work

Each step is one pull request with its failing test first.

1. **PR 1, new files only (this branch).** `HxSourceRange` (file, min, max; immutable; code
   points; exclusive end) and `HxLineTable` (offset to line and column, and upstream's
   `characters a-b` / `lines a-b` text). No provenance type yet, and no change to `HxExpr`,
   `HxParser`, or `HxLexer`. `test/M14MacroSourcePositionsTest.hx` checks them against the
   upstream probes in `test/fixtures/macro_source_positions`: a non-BMP prefix (59-63,
   `3: characters 23-27`), CRLF (47-51, line 3, `characters 9-13`), lone CR (45-49, line 3), an
   escaped string 8 wide, an unreadable file on line 1, and every argument position upstream
   printed for the probes.
2. **PR 2, after the parser stack (D8).** The seven D9 constructors get `?range`. `HxParser` sets
   it from the token start and `HxToken.endIndex`; a call ends at `)`, and an array spans `[`
   to `]`. `MacroSyntaxExport.argument` and `convert` export the real `{min, max}`, with the
   named inheritance list for kinds not yet admitted (C1). `MacroSyntaxPositions` keys on
   `(min, max)`. `ParsedModuleIntegrity` includes ranges, the parser schema becomes v13, and
   `TypedBodyFingerprint` does not change. Tests go through the real parser, with upstream
   numbers:
   - `[null, null, 1]` is 121-136 and `1` is 134-135;
   - `this1(null, (base))` is 129-148 and its callee 129-134;
   - with a comment between tokens and an inactive Unicode branch before it, `base` is 106-110;
   - repeated equal literals get different ranges, and a rebuilt child keeps its range;
   - the reification smoke step for `Macros.tally(["alpha", "beta"])` passes;
   - the Identity and `while` exports do not change;
   - an admitted node without a range fails by name.
3. **Singletons (D2).** `ENull()`, `EThis()`, and `ESuper()` with `?range`, as one mechanical
   pull request; then `null` and `this` join the admitted surface.
4. **Provenance and macro results (C4).** The provenance kinds. Macro results keep their
   positions as given, in any file. The compilation-level line-table map (D4) gives
   diagnostics for other files. The authored interpolation constant follows once the parser
   stream's node lands (D7).
5. **The remaining expression kinds.** Then the inheritance list is removed and the range
   becomes mandatory.
6. **Identity (D5).** Decide whether any `TypedBodyFingerprint` consumer needs an occurrence
   identity, with a test for each consumer that changes.

The checked-in `packages/hxhx/bootstrap_out/*.ml` would conflict with the parser stream, so the
bootstrap snapshot is regenerated last, after the rebase.

Acceptance stays as the bead states it: independently specified positions for the C3 test set;
unchanged Identity and `while` macro export and checked return insertion; and an explicit
failure for syntax whose positions are not owned. Token-only tests, or tests of supplied
positions, do not close the bead.
