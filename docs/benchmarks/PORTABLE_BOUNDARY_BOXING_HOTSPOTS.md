# Portable Boundary Boxing Hotspots (Stage3 OCaml)

This inventory tracks high-frequency portable lowering boundaries where avoidable dynamic
boxing/unboxing can be reduced without changing portable semantics.

## Scope

- Backend: `hxhx` Stage3 OCaml (`packages/hxhx-core/src/EmitterStage.hx`)
- Profile: `-D ocaml_profile=portable`
- Strategy: apply typed fast-paths only in planner-approved metal-safe regions, keep
  semantic fallbacks for non-safe regions.

## Hotspot inventory

1. `Array.map` call lowering
   - Boundary site: call lowering in `EmitterStage` (`EField(obj, "map")`)
   - Legacy portable path: `HxBootArray.map_dyn (Obj.magic ...) (Obj.repr ...)`
   - Typed fast-path strategy: use `HxBootArray.map` when region is auto-metalized and
     receiver is `Array<String>`-shaped.
   - Report code: `array_map_typed`
   - Status: implemented.

2. `Array.join` call lowering
   - Boundary site: call lowering in `EmitterStage` (`EField(obj, "join")`)
   - Legacy portable path: `HxBootArray.join` / `join_dyn` (dynamic stringification seam)
   - Typed fast-path strategy: use `HxBootArray.join_strict` when region is auto-metalized
     and receiver is `Array<String>`-shaped.
   - Report code: `array_join_typed`
   - Status: implemented.

3. Numeric division fallback in portable metalized regions
   - Boundary site: binary-op division handling in `EmitterStage`
   - Legacy path: poison/runtime fallback when lowering cannot safely choose numeric lane
   - Typed fast-path strategy: metal-style numeric division in auto-metalized regions with
     existing semantic guards.
   - Report code: `numeric_division_typed`
   - Status: implemented.

## Tracking and validation

- Planner report artifact:
  - `ocaml_portable_metalization_plan_report.json`
- Validation test:
  - `test/M14PortableAutoMetalizationPlannerIntegrationTest.hx`
- Bench visibility:
  - `scripts/bench/m14.py` portable-vs-metal lanes and ratio output

## Next candidates

- `Array.filter` typed fast-path in auto-metalized regions.
- `Array.push/concat/copy` boundary reductions where typed receiver shape is stable.
- Boundary boxing minimization at call-site argument marshalling for known typed callees.
