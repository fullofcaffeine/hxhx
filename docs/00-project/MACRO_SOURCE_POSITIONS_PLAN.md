# Macro source positions: contracts before a representation change

Status: draft for independent review (Fable) and an owner decision. Bead: `haxe_ocaml-9sj5p.2`.
This document changes no code. It states the five contracts that the bead requires before
`HxExpr` or the parser change, and the decisions that are still open.

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
- Exported positions are zero-width (`min == max`), because no node has an end
  (`MacroSyntaxPositions`).
- A returned position that this call did not export is dropped. The importer then uses the
  first argument's start or `HxPos.unknown()` (`MacroSyntaxImport.hx`, lines 45-46).
- Tokens already have an exclusive end (`HxToken.endIndex`, bead `haxe_ocaml-9sj5p.1`), but
  the parser does not pass it to syntax nodes.

The bead also asks that a returned macro expression keep its own validated position, including
positions in other files.

## 2. How upstream Haxe 4.3.7 behaves

All citations are `git -C ~/workspace/code/haxe show 4.3.7:<path>`.

- **The position type.** `pos = { pfile; pmin; pmax }` (`src/core/globals.ml`, lines 1-3). The
  unknown position is `null_pos = { pfile = "?"; pmin = -1; pmax = -1 }` (line 36).
- **Offsets count Unicode code points.** The lexer uses `Sedlexing.Utf8` (`src/syntax/lexer.ml`,
  lines 20-21). `mk_tok` and `mk` set `pmin = lexeme_start` and `pmax = lexeme_end`
  (lines 297-301). Sedlex counts code points, so a non-BMP character is one unit, not two
  (UTF-16) or four (UTF-8 bytes). `pmax` is exclusive.
- **String tokens.** A string token's range covers the written text, including the quotes and
  the escapes. The token's value is the unescaped string (lines 464-473).
- **Lines and characters.** `resolve_pos` reads the file again and counts code points. `\r\n`
  counts as two offsets and one line break (lines 213-245). `get_pos_coords` and `get_error_pos`
  print 1-based columns as `characters a-b`, or `lines a-b` across lines (lines 270-290). For
  `base` at column 33, upstream prints `characters 33-37`: the start column, and the column
  after the last character.
- **Composite positions.** `punion` keeps the first position's file and takes the smaller
  `pmin` and the larger `pmax` (`src/core/ast.ml`, lines 449-452). A constant has its token's
  range (`src/syntax/grammar.mly`, line 1412). An array literal spans `[` to `]` (line 1231). A
  call spans its callee to `)` (line 1570).
- **Conditional compilation skips tokens.** The preprocessor drops the tokens of inactive
  branches (`src/syntax/parserEntry.ml`, lines 259-326). Positions therefore always count the
  original file text.
- **Interpolation happens at typing, not parsing.** A single-quoted string is a constant token.
  `format_string` (`src/typing/typer.ml`, from line 733) splits it while typing and places each
  part inside the literal (`pmin + 1 + offset`). A macro therefore sees the raw constant.
  Quirk: those inner offsets come from `String.unsafe_get` on the string value, so they count
  bytes, not code points.
- **The macro API exposes positions as `{min, max, file}`.** `Context.getPosInfos` and
  `Context.makePosition` read and build them (`src/macro/macroApi.ml`, lines 1981-1986). A
  returned expression keeps whatever position it carries, in any file.

## 3. The contracts

Each contract says what must be true, who owns it, and how a violation fails. Section 4 maps
each one to the current code.

### C1. Source ownership

- Each authored syntax occurrence owns exactly one source range: a file identity, a start
  offset, and an exclusive end offset (C3 gives the unit). This covers every expression and
  statement occurrence, leaves included.
- Two occurrences never share a range object or a value. A repeated `null`, `this`, or `1` is a
  separate occurrence with its own range.
- Ranges follow upstream's composition rules (section 2): a token's range for a leaf, and the
  first-to-last token union for a composite.
- The parser owns the range. It sets the range when it builds the node, from its own tokens.
  No later stage searches the source text, transfers a range between equal spellings, or keeps
  a side table keyed by node identity or child path.
- A node that has no authored source is not given a range. It carries a provenance instead
  (C4).
- Failure policy: a consumer that needs a range, such as macro export or a diagnostic, and
  finds none fails with an error that names the node's provenance. It never substitutes the
  call's position or the parent's position without saying so.

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
- Semantic consumers keep receiving complete expressions. If the representation uses a wrapper
  node, no consumer may skip the wrapper silently (bead constraint; decision D1).

### C3. Original-source Unicode offsets

- Unit: Unicode code points (scalar values) from the start of the original file text, before
  conditional filtering. The end is exclusive. This is upstream's unit.
- Host independence: the offset must not depend on how the host stores strings. hxhx's two hosts
  index strings by code point: the OCaml runtime (`HxString`, "two code points, three bytes ...
  `length` is 2") and the interpreter. So the lexer's `charCodeAt` index is a code-point offset
  today. A future host with UTF-16 strings would need an explicit conversion. The contract
  names the unit, not the host API.
- Conditional filtering must keep code-point offsets. `HxConditionalCompilation` replaces
  inactive text and directives with spaces, one per character, and keeps line breaks
  (`HxConditionalCompilation.hx`, lines 15-19 and 444). That keeps the offsets.
- Lines and columns are derived from offsets as upstream derives them: `\n`, `\r\n` (two
  offsets, one break), 1-based columns counted in code points. `HxPos.line` and `column` must
  agree with that derivation (decision D3 covers a lone `\r`).
- A string, regular-expression, or comment token's range covers its written text. The decoded
  value never decides a range.
- Required tests (from the bead): nested and repeated syntax, comments between tokens, escaped
  strings, Unicode and non-BMP text before the node, inactive conditional branches before the
  node, and rebuilt children.

### C4. Rewrite provenance

Every node's position is one of these kinds:

| Kind | Meaning | Range |
| --- | --- | --- |
| Authored | written in a source file and built by the parser | its own (C1) |
| Derived | built from an authored node by a named rewrite, such as a parser desugaring, regex lowering, or a typer lowering | the authored node's range, plus the rewrite's name |
| MacroResult | returned by a macro | the position the macro gave, validated, in any file |
| Synthetic | made by the compiler with no source | none; carries the reason |

- **Every rewrite states the kind** of each node it creates. Today the rewrites include
  single-quote interpolation in the parser, `ERegexLiteral` lowering, `EDiscardThen`,
  `ELoweredControl`, macro reification lowering, and the macro pass's call replacement.
- **A macro result keeps its own position.** It is validated (a non-empty file, and
  `0 <= min <= max`) and kept, even when it points into another file (the macro's own source,
  or a position from `Context.makePosition`). A position that fails validation is an error at
  the call. The importer no longer drops positions it did not export.
- **A diagnostic in a macro result reports that file.** This needs line tables for files other
  than the module being typed (decision D4).
- **Interpolation timing.** Upstream makes interpolation a typing-time rewrite. If hxhx keeps
  interpolating in the parser, a macro sees a concatenation where upstream gives a constant
  (decision D7).

### C5. Parse cache and fingerprints

- **The parse cache key changes with the representation.** The key already includes the
  original source, the filtered source, and the parser configuration
  (`CompilationServerSourceCacheRequest.hx`, lines 126-137; the comment there notes that
  inactive Unicode can change positions without changing filtered text). Any representation
  change must bump `ParserStage.cacheConfigurationRevision()` (`hxhx-parser-schema-v12`), so a
  server never reuses a module parsed without ranges.
- **The integrity revision must include every new range.** `ParsedModuleIntegrity` already adds
  each field and function position (lines 112-117), so a mutated range is caught before reuse.
- **Two identities, chosen per consumer.** `TypedBodyFingerprint` already adds the positions
  of the nodes that own one (lines 37-44). Its identities serve freshness and capture checks
  (`TypedBackend*Occurrence`, `TyFunctionEnv`, and others). With a range on every node, two
  equal expressions at different places stop being equal. The contract needs:
  - a structural identity that ignores ranges, for consumers that compare syntax by meaning;
  - an occurrence identity that includes ranges, for consumers that identify one written
    occurrence.

  Each existing consumer must be assigned one of the two, with a test (decision D5).
- **A whitespace-only edit changes ranges.** It must invalidate everything that depends on
  occurrence identity, and should not invalidate what depends only on structure. Upstream's
  server re-types a module after any edit, so hxhx may be stricter but not looser.
- **Plugin cache keys stay as they are.** Project-macro plugin keys bind source files by digest,
  not by syntax. Ranges do not change them.

## 4. Where the current code stands

| Contract | Current fact | Where |
| --- | --- | --- |
| C1 | 35 of 48 expression constructors own no position; `ENull`, `EThis`, and `ESuper` are singletons | `HxExpr.hx` |
| C1 | export fails for arguments whose root owns no position | `MacroSyntaxExport.hx`:49 |
| C2 | rebuilt containers keep positions they already own | `ExprMacroExpander.rewriteExpr` |
| C3 | offsets are code points on both hosts; no end on syntax nodes | `HxPos.hx`, `HxToken.endIndex`, `HxString.ml` |
| C3 | the conditional filter keeps offsets | `HxConditionalCompilation.hx` |
| C4 | interpolation happens in the parser: `'a$b'` parses as `EBinop(+, EString(a), ...)` | `HxParser` |
| C4 | foreign macro-result positions are dropped | `MacroSyntaxImport.hx`:45-46 |
| C5 | the parse cache key and the integrity revision exist; fingerprints mix structure and position | `CompilationServerSourceCacheRequest.hx`, `ParsedModuleIntegrity.hx`, `TypedBodyFingerprint.hx` |

## 5. Proposed order of work, after approval

Each step is one pull request with its own failing test first.

1. **Offset and line functions.** Code-point offsets to line and column, matching upstream's
   display, with the C3 test set. No representation change.
2. **The range type.** A file identity plus start and end, with provenance kinds (C4) and
   validation. Use it first where positions already exist (fields, functions, classes).
3. **The first admitted surface** through the real parser: constants, identifiers, array
   literals, and calls. Export uses real ranges; the reification smoke step and exact constant
   argument positions follow.
4. **Macro results.** Validated foreign positions, and diagnostics that report them (C4, D4).
5. **Remaining expression and statement kinds**, then removal of the singleton constructors.
6. **Identity split (C5).** Each fingerprint consumer moves to its structural or occurrence
   identity, then the cache schema is bumped.

Acceptance stays as the bead states it: independently specified positions for the C3 test set;
unchanged Identity and `while` macro export and checked return insertion; and an explicit
failure for syntax whose positions are not owned. Token-only tests, or tests of supplied
positions, do not close the bead.

## 6. Open decisions

- **D1. Representation.** The options:
  - a range field on every `HxExpr` constructor;
  - a wrapper node around each occurrence;
  - one common occurrence record that holds the range and the expression.

  The bead forbids identity maps and child-path tables, and forbids consumers that ignore
  wrappers silently. Every option touches `HxExpr` and the parser, which are the parser
  stream's files.
- **D2. Singleton constructors.** `ENull`, `EThis`, and `ESuper` must become per-occurrence
  values. That changes pattern matches in many stages.
- **D3. Units and line rules.** Confirm code points (upstream's unit), and how a lone `\r`
  counts. Decide whether to reproduce upstream's byte-counted interpolation offsets.
- **D4. File identity.** A normalized path string or an interned identity. How diagnostics get
  line tables for files other than the current module (macro sources, `Context.makePosition`).
- **D5. Identity split.** Which consumers of `TypedBodyFingerprint` and the occurrence
  identities need structure, and which need the written occurrence.
- **D6. Conditional compilation.** Keep the offset-preserving text filter, or move to
  token-level skipping as upstream does. Either way, C3 must hold.
- **D7. Interpolation timing.** Move single-quote interpolation from the parser to typing, so
  macros see the raw constant. This changes parse-oracle output and the parser stream's files.
- **D8. Ownership and sequencing.** `HxExpr` and `HxParser` belong to the parser stream, and its
  pull requests are stacked on them. Who makes steps 2-5, and in which order with those pull
  requests.
- **D9. The first admitted surface.** Confirm step 3's node set, or choose another.
- **D10. Lost design notes.** The bead refers to `pr92-expression-occurrence-design.md` for
  earlier design questions. That file is not in the repository or its history, so this
  document starts from the current code.
