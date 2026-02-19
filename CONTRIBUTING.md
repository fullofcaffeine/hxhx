# Contributing

This repository is in active compiler bring-up. Keep changes small, testable, and traceable.

## Local setup

```bash
npm install
npx lix download
```

Install local pre-commit hooks:

```bash
npm run hooks:install
```

If `bd` hooks are installed, this chains the repo hook under `.git/hooks/pre-commit.old` so both flows run.

## Required local tools

- `gitleaks` on `PATH` (or repo-local `./gitleaks`)
- `haxelib formatter` (`haxelib install formatter`)

## Guard commands

- Secret scan (full history): `npm run guard:gitleaks`
- Machine-local path leak check: `npm run guard:local-paths`
- Guardrail checks: `npm run ci:guards`
- Deterministic Haxe format check: `npm run guard:hx-format`
- Public release preflight bundle: `npm run release:preflight`

## CI alignment

- CI runs `gitleaks` on full history in `.github/workflows/ci.yml`.
- Local `scripts/ci/gitleaks-history-check.sh` and CI share the same config (`.gitleaks.toml`).
- Keep `README.md` updated in the same PR when workflows or required tools change.
