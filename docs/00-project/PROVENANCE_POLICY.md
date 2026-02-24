# Provenance Policy (MIT Shipping Path)

This repository keeps a strict clean-room implementation path for `hxhx` and `reflaxe.ocaml`.

## Core rules

- Upstream Haxe compiler code is a **behavior oracle**, not a code source for this repository.
- Upstream tests are run from untracked checkouts (for behavior validation), not copied into this repository.
- Shipping artifacts must be built from **repo-owned source code**.

## ML2HX policy (explicit)

`ML2HX`-style translation experiments are **non-shipping**.

- Allowed:
  - local research,
  - oracle validation,
  - behavior exploration notes.
- Not allowed in MIT shipping artifacts:
  - translated upstream compiler code,
  - mechanically rewritten upstream compiler code,
  - code derived from translation outputs.

If an ML2HX experiment informs implementation, only behavior-level conclusions may be carried over, then reimplemented from scratch in repo-owned code.

## Contribution expectations

- Prefer “reimplement / behavior-driven” wording.
- Avoid “translate / port upstream compiler implementation” language for shipping work.
- Keep provenance evidence reviewable:
  - tests first,
  - small commits,
  - explicit policy references in PR/bead notes for sensitive areas.
