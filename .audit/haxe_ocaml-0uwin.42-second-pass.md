# Second-pass review: anonymous literal runtime ownership

## Outcome

The change is safe to commit for the bounded bug. A field initializer now
evaluates its source value once into a local variable, then performs the exact
checked `HxAnon.set` call using that local. Helpers inside the field value no
longer appear to belong to the outer initializer.

This fixes the real `haxe.Template` failure without relaxing private-runtime
checks, changing Haxe behavior, or claiming broader anonymous-object support.

## Review findings and dispositions

1. **A separate validation-only tree could drift from generated code.**
   The first draft used a small helper skeleton for checking. The final design
   instead places the same `HxAnon.set` expression value in the generated tree
   and the runtime-operation inventory. This follows the existing array-literal
   pattern and removes the duplicate representation.
2. **The source expression must still run once and in source order.**
   Each field value is bound by one OCaml `let` immediately before its store.
   The portable fixture checks the generated shape, upstream Haxe 4.3.7 output,
   native OCaml output, and the existing side-effect order.
3. **Narrower ownership must not weaken corruption detection.**
   The focused plan fixture retains a nested plain `HxAnon.get` in the complete
   generated expression but excludes it from the outer helper call. It then
   rejects missing, duplicated, and reordered outer calls. Existing checks
   reject stale plans, wrong symbols, wrong owners, and wrong profiles.
4. **This does not migrate the nested legacy anonymous read.**
   The nested `HxAnon.get` remains tracked by the runtime-reference migration
   inventory. The inventory stays at 389 entries, and runtime authority remains
   explicitly partial. This task fixes ownership scope only.
5. **No product-readiness claim changes.**
   The focused anonymous fixture and the original `haxe_core_bucket02_basic`
   portfolio case pass, but the parent runtime migration remains open. README
   Goals therefore stay unchanged.

## Evidence reviewed

- exact Haxe 4.3.7 behavior oracle in `anon_struct_basic`;
- standalone OCaml compile, Dune build, native execution, and generated-shape
  checks for `anon_struct_basic`;
- the original `haxe.Template` path in `haxe_core_bucket02_basic`;
- anonymous-structure plan and corruption checks;
- runtime-reference inventory, changed-file and repository-wide formatting,
  mega-file, local-path, and diff checks.
