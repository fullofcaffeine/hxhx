# Expected red: direct Array bracket reads

Command: `npm run test:reflaxe-ocaml:array-read-plan`

Expected result: the compiler reports that `OcamlArrayReadPlan` and
`OcamlArrayReadPlanner` do not exist.

Observed result: the command exited with status 1 for those missing types. This
proves that the new focused contract does not pass through the old printer-only
`HxArray.get` branch.
