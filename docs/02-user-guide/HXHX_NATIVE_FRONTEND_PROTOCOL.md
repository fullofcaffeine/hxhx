# HXHX Native Frontend Protocol (Lexer/Parser Hook Wire Format)

This document defines the **wire format** used by the “native frontend” hook in:

- `std/runtime/HxHxNativeLexer.ml`
- `std/runtime/HxHxNativeParser.ml`

The goal is to keep the lexer/parser in **native OCaml** initially (as suggested by upstream Haxe bootstrapping plans),
while letting the rest of the compiler pipeline live in **Haxe**.

## Scope

This protocol is a **bootstrap seam**, not a long-term public API yet:

- It must be **stable enough** to iterate quickly without breaking Stage 2.
- It must be **versioned** so we can evolve it compatibly.
- It must be **dependency-free** (no JSON libs on the OCaml side; no custom parsers on the Haxe side).

## Bootstrap knobs (non-protocol)

The records below define the wire format. Separately, the native frontend has a couple of **bootstrap-mode**
configuration knobs that do *not* change the protocol version, but do change behavior.

### `HXHX_NATIVE_FRONTEND_HEADER_ONLY`

When set to `1`/`true`/`yes`, `HxHxNativeParser.parse_module_decl` enables a **best-effort header-only fallback**:

- If the full token-based parser fails (or throws), the native side attempts to still return:
  - `ast package ...` (best-effort)
  - `ast imports ...` (best-effort)
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

Every output starts with a header line:

```
hxhx_frontend_v=1
```

Future versions must:

- keep the header (`hxhx_frontend_v=<n>`)
- only add new record types or optional fields in a backward-compatible way
- avoid changing the meaning of existing records for the same version number

## Records (v=1)

Records are newline-delimited. Payloads are always **single-line** due to escaping (see below).

### Token record

```
tok <kind> <index> <line> <col> <len>:<payload>
```

Where:

- `<kind>` is one of: `kw`, `ident`, `string`, `sym`, `eof`
- `<index>` is a 0-based character index into the original source string
- `<line>` / `<col>` are 1-based for human-friendly diagnostics
- `<payload>` is the token text (escaped; see below)

### AST summary records

These are appended by the native parser (not the lexer):

```
ast package <len>:<payload>
ast imports <len>:<payload>
ast class <len>:<payload>
ast header_only <len>:<payload>
ast toplevel_main <len>:<payload>
ast static_main 0|1
ast method <len>:<payload>
```

Notes:

- `ast imports` uses a `|` separator for now (bootstrap convenience).
- Longer-term we’ll likely replace this with a structured list record.
- `ast header_only` is an optional bootstrap hint:
  - payload is `0` or `1`
  - `1` means the native side fell back to header-only parsing (i.e. method bodies were not parsed)
- `ast toplevel_main` is a bootstrap hint:
  - payload is `0` or `1`
  - `1` means the module contains a toplevel `function main(...)` (no class required)
- `ast method` is a bootstrap record that encodes a function signature summary as a `|` separated payload:
  `name|vis|static|args|ret|retstr|retid|argtypes|retexpr`
  - `vis` is `public` or `private`
  - `static` is `0` or `1`
  - `args` is a comma-separated list of argument names
  - `ret` is the (raw) return type hint text, or empty
  - `retstr` is the first detected string literal returned by the function (if any), or empty
  - `retid` is the first detected `return <ident>` (if any), or empty
  - `argtypes` is a comma-separated list of `name:type` pairs for arguments that have an explicit type hint
  - `retexpr` is a best-effort textual capture of the first returned literal/identifier expression (if any)

Notes:

- `retid`/`argtypes`/`retexpr` are optional fields added in a backward-compatible way: Stage 2 decoders that only
  understand `name|vis|static|args|ret|retstr` will ignore the extra segments.
- Because `ast method` uses `|` as its own field separator, `retid` and `argtypes` must not contain `|` characters.
  The same constraint applies to `retexpr`.

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
