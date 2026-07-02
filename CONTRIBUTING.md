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
The repo pre-commit hook enforces staged local-path checks, staged secret scanning, and staged Haxe formatting.

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

## Documentation expectations

- Treat docs as part of the change. Update `README.md`, getting-started docs, or the relevant technical doc when behavior, workflows, flags, required tools, or production-readiness claims change.
- Write for capable beginners who are new to this repo: define terms, prefer concrete commands and expected outcomes, and link to deeper docs instead of relying on internal shorthand.
- Be precise about limits. Do not oversimplify away prerequisites, unsupported cases, evidence gaps, or current production-readiness status.
- Avoid Dunning-Kruger-style confidence: simplified docs must not make complex, incomplete, or risky areas sound solved.

## Upstream stdlib policy (required)

- Follow `docs/00-project/STD_LIB_POLICY.md` for upstream sync boundaries.
- Upstream Haxe is used as a behavior oracle; direct reuse is limited to stdlib scope.
- Do not copy upstream compiler or test sources into this repository.

## Provenance policy (required)

- Follow `docs/00-project/PROVENANCE_POLICY.md` for shipping-path provenance rules.
- ML2HX/translation workflows are research-only and non-shipping in this repo.
- If a translation experiment is used for exploration, only behavior-level conclusions may be reused; implementation must be fresh repo-owned code.
