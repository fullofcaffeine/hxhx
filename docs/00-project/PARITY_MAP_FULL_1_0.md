# Full 1.0 Parity Map (Haxe 4.3.7)

Last audited: 2026-07-13

This is the canonical Full 1.0 parity registry.

- Machine-readable source: `docs/00-project/PARITY_MAP_FULL_1_0.json`
- Scope contract: `docs/00-project/FULL_1_0_CONTRACT.md`
- Scope manifest: `docs/02-user-guide/compat/full-1.0-scope.json`
- Plain-language target table: `docs/02-user-guide/compat/FULL1_TARGET_SCOPE.md`

## How to read this map

- `enforcement=required_now`: must map to existing workflows and markers today.
- `enforcement=planned`: reserved Full 1.0 markers that become required when their workflows land.

This split keeps the map complete without pretending not-yet-implemented gates already exist.

The first Full1 target set is exactly
`Macro,Js,Neko,Hl,Python,Java,Cs,Cpp,Lua,Php`. The `Cpp` lane includes Cppia,
and the `Hl` lane includes bytecode and C output. JVM bytecode, XML/JSON type
descriptions, and Flash/SWF are not silently hidden behind this shorter CI
label list; their explicit decisions live in the target-scope table.

## Marker policy

- Marker IDs must be unique across the map.
- Every `required_now` marker must be discoverable in its workflow file.
- Every suite listed in `requiredNowSuites` must have at least one `required_now` entry.

Guard checker:

- `scripts/ci/full1-parity-map-check.js`

Success marker:

- `FULL1_PARITY_MAP:PASS`

Target-scope consistency has a separate policy marker:

- `FULL1_TARGET_SCOPE_CONTRACT:PASS`

Both are contract checks. Runtime target support still requires authentic
same-candidate Gate3 evidence.
