# Full 1.0 Parity Map (Haxe 4.3.7)

Last audited: 2026-03-05

This is the canonical Full 1.0 parity registry.

- Machine-readable source: `docs/00-project/PARITY_MAP_FULL_1_0.json`
- Scope contract: `docs/00-project/FULL_1_0_CONTRACT.md`
- Scope manifest: `docs/02-user-guide/compat/full-1.0-scope.json`

## How to read this map

- `enforcement=required_now`: must map to existing workflows and markers today.
- `enforcement=planned`: reserved Full 1.0 markers that become required when their workflows land.

This split keeps the map complete without pretending not-yet-implemented gates already exist.

## Marker policy

- Marker IDs must be unique across the map.
- Every `required_now` marker must be discoverable in its workflow file.
- Every suite listed in `requiredNowSuites` must have at least one `required_now` entry.

Guard checker:

- `scripts/ci/full1-parity-map-check.js`

Success marker:

- `FULL1_PARITY_MAP:PASS`
