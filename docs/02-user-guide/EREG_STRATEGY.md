# EReg / Regex Strategy (M11)

Haxe’s `EReg` API is used by:

- user applications directly, and
- parts of the Haxe ecosystem / tooling (and eventually `hxhx`).

Upstream Haxe ships `EReg` as a **target-implemented API**. The fallback
implementation throws a `NotImplementedException`, so the OCaml target must ship
its own runtime.

## Current strategy (stdlib-only dependency)

We implement `EReg` using OCaml’s `Str` library:

- Extern surface: `std/_std/EReg.hx`
- Runtime implementation: `std/runtime/EReg.ml`

### Why `Str`

- `Str` is part of the “standard” OCaml distribution story and is available on
  typical dune/apt/brew installs.
- Avoids pulling a large regex engine dependency early in the project.

### Compatibility model

`Str` uses an Emacs-style regex syntax which differs from Haxe’s commonly used
PCRE-like syntax.

To make the common cases work, the runtime performs a **best-effort translation**
at `new EReg(pattern, options)` time:

- `(...)` → `\(...\)` (capturing groups)
- `+`, `?`, `|`, `{m,n}` operators are escaped as required by `Str`
- Common character classes are mapped:
  - `\d` / `\D`
  - `\w` / `\W`
  - `\s` / `\S`

This is sufficient for many “stdlib-ish” patterns, but it is not a full PCRE
compatibility layer.

## Known limitations (intentional, for now)

Unsupported or not-guaranteed-yet features include:

- lookahead/lookbehind (`(?=...)`, `(?<=...)`, etc.)
- named groups
- many unicode properties / full unicode character classes
- exact parity for edge cases like zero-length global matches

When unsupported patterns are used, behavior is “best effort” and may raise at
runtime.

## Future direction (1.0)

If/when the `Str`-based approach becomes a blocker, the planned path is:

1. Keep the Haxe API surface stable (`EReg` in Haxe stays the same).
2. Swap the OCaml runtime implementation to a more compatible engine
   (e.g. PCRE via an OCaml library), likely behind a feature flag or a documented
   dependency tier.
3. Expand portable fixtures to cover the additional semantics.

