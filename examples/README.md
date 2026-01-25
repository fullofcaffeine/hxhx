# Examples

These apps exist to:

- Provide real-world usage samples.
- Act as QA/acceptance tests (compile → dune build → run).

Run them all from the repo root:

```bash
npm run test:examples
```

## Included examples

- `mini-compiler`: small parser/evaluator smoke test (compiler-ish workload).
- `loop-control`: exercises `break`/`continue` lowering (prevents infinite-loop regressions).
