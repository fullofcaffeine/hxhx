# Third-Party Notices

This repository remains MIT-licensed.  
The notices below document third-party sources used as compatibility references and development tools.

## Haxe formatting tools

- **Formatter:** [HaxeCheckstyle/haxe-formatter](https://github.com/HaxeCheckstyle/haxe-formatter), MIT, release 1.18.0 at `93ba289893d515614298f4ce7cee8619c31b420c`.
- **Lexer dependency:** [HaxeCheckstyle/haxeparser](https://github.com/HaxeCheckstyle/haxeparser), BSD as declared in its package metadata, at `a5fce2ecf5fb3bdfebfd7efd8b05329d456ec0d2`.
- **Local change:** `scripts/lint/formatter-lexer-scan.patch` records the authored performance repair tracked by `haxe_ocaml-bwprv`.
- **Use:** development formatting only. Setup fetches the original sources and their notices into an ignored build directory. The generated formatter stays in an ignored local tool directory. Compiler packages do not include these checkouts or this formatter.
- **Identity:** `scripts/lint/formatter-toolchain.lock.json` records source revisions and exact patch and generated-artifact digests. The formatter release supplies its locked build dependencies.

## Unicode Character Database (case-mapping tables)

- **Project:** Unicode Character Database, `UnicodeData.txt` version 8.0.0 (`https://www.unicode.org/Public/8.0.0/ucd/`).
- **License:** Unicode License V3 (`https://www.unicode.org/license.txt`).
- **What was used:** the simple upper- and lower-case mappings for U+0000..U+FFFF, compressed into the `upper_runs` and `lower_runs` tables in `packages/reflaxe.ocaml/std/runtime/HxString.ml`.
- **How:** `scripts/reflaxe-ocaml/generate-hxstring-case-table.js` reads the data file and prints the tables. It writes the full Unicode copyright and permission notice above them. That runtime file is copied into every generated OCaml program, so the notice ships with each copy, as the license requires.

## Haxe Standard Library (`std`)

- **Project:** Haxe
- **Upstream repository:** `https://github.com/HaxeFoundation/haxe`
- **Baseline tag:** `4.3.7`
- **License:** MIT
- **Local scope:** `packages/reflaxe.ocaml/std/ocaml/_std/**` and `packages/hxhx-core/std/cpp/_std/**`
- **Details:** `docs/00-project/STDLIB_PROVENANCE_LEDGER.json`

Notes:
- `_std` files are target overrides for `reflaxe.ocaml` and the bundled native C++ target.
- Some files are selectively synced from upstream stdlib; others are repo-authored overrides guided by upstream behavior.
