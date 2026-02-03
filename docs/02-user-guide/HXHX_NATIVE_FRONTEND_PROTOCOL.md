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
ast static_main 0|1
```

Notes:

- `ast imports` uses a `|` separator for now (bootstrap convenience).
- Longer-term we’ll likely replace this with a structured list record.

### Terminal records

Exactly one terminal record must be present:

```
ok
```

or:

```
err <index> <line> <col> <len>:<message>
```

## Escaping

Payload strings use a minimal escape layer to guarantee each record stays on a single physical line:

- `\\` → backslash
- `\n` → newline
- `\r` → carriage return
- `\t` → tab

`<len>` is the length of the **escaped** payload (so decoding can be “slice then unescape”).

