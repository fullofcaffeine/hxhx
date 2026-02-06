# Provenance (Licensing Hygiene)

This repository’s long-term goal is to remain **permissively licensed**.

## What this repo is (and is not)

- The code in this repository is intended to be an original implementation of a Haxe → OCaml backend (`reflaxe.ocaml`) and an eventual Haxe-in-Haxe compiler (`hxhx`).
- Upstream Haxe is used as a **behavioral oracle** (test suites, observed CLI/runtime behavior), not as a source tree to copy from.

## Rules we follow

- **Do not copy or transcribe** upstream compiler sources into this repository.
  - Reading upstream code to understand behavior/constraints is fine.
  - Reproducing the implementation line-by-line (even in another language) is not.
- Upstream checkouts live under `vendor/haxe` and are **not tracked by git**.
  - CI enforces that no files under `vendor/haxe` are committed.
- Prefer “spec/tests first”: write down expected behavior (tests, docs, notes), then implement.

## Third-party code

- If third-party code is ever incorporated into this repository (beyond untracked local checkouts under `vendor/`), we must:
  - ensure the license is compatible with our distribution goals, and
  - preserve any required notices (either in-file or in a `THIRD_PARTY_NOTICES` document).
