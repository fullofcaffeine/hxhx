# Third-Party Notices

This repository remains MIT-licensed.  
The notices below document third-party sources used as compatibility references and development tools.

## Haxe formatting tools

- **Formatter:** [HaxeCheckstyle/haxe-formatter](https://github.com/HaxeCheckstyle/haxe-formatter), MIT, release 1.18.0 at `93ba289893d515614298f4ce7cee8619c31b420c`.
- **Lexer dependency:** [HaxeCheckstyle/haxeparser](https://github.com/HaxeCheckstyle/haxeparser), BSD as declared in its package metadata, at `a5fce2ecf5fb3bdfebfd7efd8b05329d456ec0d2`.
- **Local change:** `scripts/lint/formatter-lexer-scan.patch` records the authored performance repair tracked by `haxe_ocaml-bwprv`.
- **Use:** development formatting only. Setup fetches the original sources and their notices into an ignored build directory. The generated formatter stays in an ignored local tool directory. Compiler packages do not include these checkouts or this formatter.
- **Identity:** `scripts/lint/formatter-toolchain.lock.json` records source revisions and exact patch and generated-artifact digests. The formatter release supplies its locked build dependencies.

## Haxe Standard Library (`std`)

- **Project:** Haxe
- **Upstream repository:** `https://github.com/HaxeFoundation/haxe`
- **Baseline tag:** `4.3.7`
- **License:** MIT
- **Local scope:** `packages/reflaxe.ocaml/std/ocaml/_std/**`
- **Details:** `docs/00-project/STDLIB_PROVENANCE_LEDGER.json`

Notes:
- `_std` files are target overrides for `reflaxe.ocaml`.
- Some files are selectively synced from upstream stdlib; others are repo-authored overrides guided by upstream behavior.
