# Public Release Preflight

Use this checklist before a public release or major public PR.

## 1) Secret scan (full history)

```bash
npm run guard:gitleaks
```

## 2) Repository guardrails

```bash
npm run ci:guards
```

This includes:

- version/license/provenance checks
- bootstrap snapshot backend-kind parity (`linked-provider` / `ocaml-dynlink`) between source and `packages/hxhx/bootstrap_out`
- legacy path checks
- machine-local absolute path leak checks
- backend/provider boundary checks
- deterministic Haxe formatting checks

For direct parity validation, run:

```bash
npm run guard:bootstrap-plugin-kinds
```

For any `1.0.0` release candidate/tag, this parity guard must be green.

## 3) Combined preflight shortcut

```bash
npm run release:preflight
```

## 4) Final verification before push

```bash
git status --short
```

Expected: no unexpected tracked file changes.
