# HXHX Native Frontend Protocol (Lexer/Parser Hook Wire Format)

This document defines the **wire format** used by the “native frontend” hook in:

- `packages/reflaxe.ocaml/std/runtime/HxHxNativeLexer.ml`
- `packages/reflaxe.ocaml/std/runtime/HxHxNativeParser.ml`

The native OCaml code reads Haxe source and sends a compact summary back to the
Haxe-authored compiler. This is a bootstrap bridge: the compiler model and all
decisions about Haxe program behavior remain owned by Haxe code.

## Scope

This protocol is a **bootstrap seam**, not a long-term public API yet:

- It must be **versioned** so its producer and consumer cannot silently disagree.
- A protocol change is a hard cut: update the OCaml producer and Haxe decoder
  together, then regenerate the native compiler. An older decoder is rejected
  instead of guessing what a newer record means.
- It must be **dependency-free** (no JSON libs on the OCaml side; no custom parsers on the Haxe side).

## Bootstrap knobs (non-protocol)

The records below define the wire format. Separately, the native frontend has a couple of **bootstrap-mode**
configuration knobs that do *not* change the protocol version, but do change behavior.

### `HIH_FORCE_HX_PARSER`

When set to `1`/`true`/`yes`, the **Stage 2/3 pipeline** forces the **pure-Haxe** parser (`HxParser`) even if the
compiler was built with `-D hih_native_parser`.

Why this exists:

- The parser protocol is intentionally *summary-oriented*: even in non-`header_only` mode it does **not** transmit full
  statement bodies as a structured AST.
- Some bring-up rungs (notably Stage 3 `--hxhx-emit-full-bodies`) need statement bodies so we can validate
  lowering end-to-end.

Notes:

- This is a bring-up switch, not a long-term architecture commitment.
- The “real” long-term options are either (a) evolve the protocol to carry a richer AST, or (b) reimplement the frontend
  into Haxe fully and remove the native seam.

### `HXHX_NATIVE_FRONTEND_HEADER_ONLY`

When set to `1`/`true`/`yes`, `HxHxNativeParser.parse_module_decl` enables a **best-effort header-only fallback**:

- If the full token-based parser fails (or throws), the native side attempts to still return:
  - `ast package ...` (best-effort)
  - one `ast directive ...` record for each recognized `import` or `using` declaration (best-effort)
  - `ast class ...` (best-effort; may remain `Unknown`)
- It returns `ok` with an empty method list (no `ast method` records) rather than `err`.

Why this exists:

- During Stage 2/Stage 3 bring-up we often only need to traverse the module graph deterministically.
- Upstream-scale class bodies contain syntax we may not support yet (and we don’t want the whole run to stop
  *at the frontend seam*).

Important:

- **Stage 1 remains strict by default**. If you don’t set this env var, parse failures must surface as `err`
  so tests can catch regressions early.

## Versioning

Parser output starts with a header line:

```
hxhx_frontend_v=3
```

Notes:

- The lexer-only stream (`HxHxNativeLexer.tokenize`) still uses `hxhx_frontend_v=1`.
- The parser decoder accepts only version 3. Version 2 reduced imports to path
  strings and therefore lost aliases; accepting both formats would reintroduce
  two meanings for the same compiler input.

Future versions must:

- keep the header (`hxhx_frontend_v=<n>`)
- avoid changing the meaning of an existing version number; and
- change producer, decoder, focused fixtures, and generated bootstrap artifacts
  in the same reviewable slice.

## Records (parser protocol v3)

Records are newline-delimited. Payloads are always **single-line** due to escaping (see below).

### Token record

```
tok <kind> <index> <line> <col> <len>:<payload>
```

Where:

- `<kind>` is one of: `kw`, `ident`, `string`, `regex`, `sym`, `eof`
- `<index>` is a 0-based character index into the original source string
- `<line>` / `<col>` are 1-based for human-friendly diagnostics
- `<payload>` is the token text (escaped; see below)

`regex` notes:

- `regex` is the full Haxe regex literal text (for example `~/[A-Z."-]+/i`).
- This avoids lexer drift on regex bodies that contain quote characters.

### AST summary records

These are appended by the native parser (not the lexer):

```
ast package <len>:<payload>
ast directive <len>:<payload>
ast class <len>:<payload>
ast header_only <len>:<payload>
ast toplevel_main <len>:<payload>
ast static_main 0|1
ast field <len>:<payload>
ast static_final <len>:<payload>
ast method <len>:<payload>
ast method_body <len>:<payload>
```

### Module-directive record

A **module directive** is the compiler's stored description of one top-of-file
`import` or `using` declaration. There is one record per declaration, in source
order. After unescaping, its payload has exactly three lines:

```text
<kind>
<path>
<alias>
```

`<kind>` is one of:

- `import-normal` — an ordinary import, including a static-member path;
- `import-alias` — an import written with `as` or the legacy `in` spelling;
- `import-all` — a wildcard import; or
- `using` — an extension-method provider, not an ordinary imported type.

`<path>` never ends in `.*`; wildcard behavior is carried by the kind. `<alias>`
is non-empty only for `import-alias`. Keeping these meanings separate prevents
valid code such as `import model.Api as Service; new Service()` from losing the
local name before type checking.

The decoder rejects a record when these fields disagree—for example, a normal
import carrying an alias, an alias record with an empty local name, a wildcard
encoded in both the kind and the path, or a path with an empty segment. The
current bootstrap lexer accepts ASCII letters and `_` at the start of each
segment, followed by those characters or digits. This decoder check mirrors
that current lexer subset; it is not a claim that broader Haxe identifier
support is permanently out of scope. Once decoded, the parsed module copies the
ordered directive list and returns copies to callers. Later compiler stages can
read the same facts, but cannot silently change the parser's retained input by
mutating an exposed array.

This wire record preserves what the user wrote; it does not guess what the path
refers to. Shared type checking makes that decision after the referenced module
has been loaded. For example:

```haxe
import model.Api.PI;
```

could name a type called `PI` or the static field `PI` on `model.Api`. The
spelling and capitalization are not enough to decide safely. Type checking
records one of these results instead:

- an exact imported type;
- one named static field or method and its owning type;
- all static members of one type;
- all eligible types from a package;
- an extension-method provider from `using`; or
- unresolved, which later validation can report instead of inventing target
  syntax.

Targets consume that resolved record. For the example above, Java emits
`import static model.Api.PI;` only when shared typing proved that `PI` is a
static member. This keeps Java, C#, OCaml, and the other targets from each
implementing a different capitalization heuristic.

Other AST-summary notes:

- `ast class` reports the **selected “main class”** for the module. Selection is:
  - deterministic when the caller uses `parse_module_decl_with_expected(src, expectedMainClass)`, and
  - best-effort heuristic when the caller uses `parse_module_decl(src)` (currently: last `class` in file).
- `ast header_only` is an optional bootstrap hint:
  - payload is `0` or `1`
  - `1` means the native side fell back to header-only parsing (i.e. method bodies were not parsed)
- `ast toplevel_main` is a bootstrap hint:
  - payload is `0` or `1`
  - `1` means the module contains a toplevel `function main(...)` (no class required)
- `ast field` is the general class-field record:
  - Includes both static and non-static `var` declarations.
  - Payload format (after unescaping):
    - line 1: field name
    - line 2: `public` or `private`
    - line 3: `0` or `1` for `static`
    - line 4: raw type hint text (may be empty)
    - remaining text: initializer expression text (may be empty)
- `ast static_final` is kept as a backward-compat bootstrap record for class-scope constants like:
  - `static final TRIALS = 3;`
  - `static final sep = if (cond) ";" else ":";`
  - `static final x = switch (v) { case 1: "a"; default: "b"; };`
  - Payload format is identical to `ast field`.
- `ast method` is a bootstrap record that encodes a function signature summary as a `|` separated payload:
  `name|vis|static|args|ret|retstr|retid|argtypes|retexpr`
  - `vis` is `public` or `private`
  - `static` is `0` or `1`
  - `args` is a comma-separated list of argument names
    - Rest params are encoded as `...name` (leading `...`), matching Haxe syntax.
    - Haxe-side decoding strips the prefix and sets `isRest=true`, and lowers the parameter type to `Array<T>`.
  - `ret` is the (raw) return type hint text, or empty
  - `retstr` is the first detected string literal returned by the function (if any), or empty
  - `retid` is the first detected `return <ident>` (if any), or empty
  - `argtypes` is a comma-separated list of `name:type` pairs for arguments that have an explicit type hint
  - `retexpr` is a best-effort textual capture of the first returned literal/identifier expression (if any)

Notes:

- `retid`/`argtypes`/`retexpr` are optional fields added in a backward-compatible way: Stage 2 decoders that only
  understand `name|vis|static|args|ret|retstr` will ignore the extra segments.
- `ast method` intentionally transmits only a method **summary** (signature + first-return hints), which keeps the
  protocol stable even while the OCaml-side parser remains minimal.
- Because `ast method` uses `|` as its own field separator, `retid` and `argtypes` must not contain `|` characters.
  The same constraint applies to `retexpr`.

### Method body record

Optional record carrying a raw source slice for the method body:

```
ast method_body <len>:<payload>
```

Payload format (after unescaping):

- First line: method name
- Remaining text: method body source (the text between `{` and `}`), as-is

Why this exists:

- Stage 3 bring-up sometimes needs statement bodies for end-to-end lowering tests, but we do not want to commit to
  an OCaml-side statement AST yet.
- The Haxe-side decoder can parse a small statement subset from this raw source to build `HxFunctionDecl.body`.

### Terminal records

Exactly one terminal record must be present:

```
ok
```

or:

```
err <index> <line> <col> <len>:<message>
```

Notes:

- In strict mode (default), parser failures should generally end the stream with `err ...`.
- In header-only mode (`HXHX_NATIVE_FRONTEND_HEADER_ONLY=1`), failures may still end with `ok` and only include
  the AST header records (see above).

## Escaping

Payload strings use a minimal escape layer to guarantee each record stays on a single physical line:

- `\\` → backslash
- `\n` → newline
- `\r` → carriage return
- `\t` → tab

`<len>` is the length of the **escaped** payload (so decoding can be “slice then unescape”).
