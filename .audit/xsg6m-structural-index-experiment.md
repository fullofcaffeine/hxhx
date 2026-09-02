# Structural-index experiment for `haxe_ocaml-xsg6m.3`

## Outcome

The structural index did not enter production. It preserved output, but it did
not reduce CPU use for the selected planner cohort. The complete prototype and
its public test surface were removed.

The experiment compared three target planners. These planners find integer
unary operations, `Std.isOfType` calls, and `String.fromCharCode` calls. Each
planner currently walks the same typed function body.

## Why the experiment started

Native snapshot regeneration still exceeds its 5,400-second emission budget.
The independent architecture review identified repeated typed-tree walks as a
possible source of the cost.

The proposed index walked each typed body once. It kept request-local source
expressions, their order, lexical boundaries, and syntax-constructor lists.
The existing planners still owned all type checks, decisions, diagnostics,
runtime requirements, and stable identities.

## Correctness result

The prototype covered ordinary functions, nested functions, and standalone
expressions. Focused contracts passed for all three planners. A separate
fixture proved stable preorder, lexical isolation, subtree boundaries, stale
binding rejection, and copied public views.

The current prototype and exact parent commit `1c795b44b` compiled the same
portable fixture with Haxe 4.3.7. The following outputs matched byte for byte:

- 43 common generated OCaml modules
- `ocaml_lowering_report.json`
- `ocaml_profile_report.json`
- `ocaml_runtime_plan_report.json`
- `ocaml_runtime_requirement_report.json`
- `ocaml_runtime_selection_shadow_report.json`

The current run also created one Dune entry module because of its output-name
hook. That file was outside the planner comparison.

## Performance result

The benchmark loaded the exact typed body of
`backend.cpp.CppTargetCore.collectAnonStructs`. It also measured the 19 nested
function bodies under that method. Five samples used `Sys.cpuTime`, which
excludes scheduler wait on the shared host.

The first prototype indexed all 210 ordinary nodes. It increased the ordinary
median from 1.132 ms to 2.157 ms. It also increased the nested median from
18.443 ms to 36.165 ms.

The second prototype stored only 45 ordinary constructor candidates. It
reduced the cost of an 8,003-node synthetic index build from 2,784 ms to
600 ms on the observed runs. However, the representative result remained
mixed:

| Workload | Parent recursive planners | Candidate-only index | New/parent |
| --- | ---: | ---: | ---: |
| Ordinary root | 1.132 ms | 1.303 ms | 1.151 |
| 19 nested roots | 18.443 ms | 18.161 ms | 0.985 |

The ordinary path was 15.1 percent slower. The nested change was only
1.5 percent lower and remained inside the sample spread. This result did not
prove a useful CPU reduction.

## Decision and next step

The experiment followed the review sequence, but the production hard cut was
rejected. The code now uses the original planner APIs and traversal paths.
There is no compatibility flag, unused index module, or second planner path.

The next full-class probe will use the committed function-preparation
telemetry. It must identify the unfinished method and dominant phase before a
new shared traversal or cache is proposed. This keeps one semantic authority
and avoids paying index memory for functions that do not benefit.
