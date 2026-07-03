# Cpp Helper Rendering Policy

This note records the strict Cpp Gate3 helper-rendering checkpoint for
`haxe_ocaml-bhzg`. It is an execution policy for reducing helper body rendering
pressure without weakening upstream Haxe 4.3.7 behavior evidence.

Strict Cpp Gate3 remains red. Local helper, render, and cache improvements are
blocker burn-down evidence only; they do not move README or North Star
production-readiness bars unless strict gates and public usability evidence
change.

## Buckets

Reachable helper classes are classified into four coarse buckets before helper
rendering:

- `full_body`: render parsed helper fields, constructors, and method bodies.
  This is the current default and the expensive path.
- `declaration_only`: emit no body or only a signature/interface surface. This
  is appropriate when C++ only needs the type boundary, not the helper's parsed
  implementation body.
- `runtime_module`: emit target-owned runtime support, a source template, or an
  intrinsic/module body instead of rendering the parsed helper implementation.
  This requires behavior scope and provenance review when the surface is
  semantic rather than mechanical.
- `unsupported_diagnostic`: refuse or diagnose unsupported helper semantics
  explicitly. This bucket exists so missing behavior does not become fake parity
  through default/no-op support.

The initial implementation reports class-level counts through the existing Cpp
trace channel:

```text
cpp_target_phase=render_helper_classes_classification total=<n> full_body=<n> declaration_only=<n> runtime_module=<n> unsupported_diagnostic=<n>
```

For architecture/debug runs that need the actual inventory, enable
`HXHX_TRACE_STAGE3_CPP_HELPER_CLASSIFICATION_DETAILS=1`. It emits one opt-in
line per ordered helper:

```text
cpp_target_phase=render_helper_classes_classification_detail index=<n> kind=<bucket> name=<rendered-helper> [raw=<source-name>] [package=<package>]
```

Use the same strict Cpp Gate3 command and timeout when comparing counts across
slices. Timing/frontier changes are meaningful only when paired with helper
counts, generated size, and the failure mode.

## Movement Rules

A helper may move from `full_body` to `declaration_only` only when the current
program needs a type/signature boundary and not inline body semantics.

A helper may move from `full_body` to `runtime_module` only when the support is
target-owned, provenance-safe, deterministic, and behavior-scoped. Broad
runtime/stdlib semantics also need
[`CPP_TARGET_RUNTIME_POLICY.md`](CPP_TARGET_RUNTIME_POLICY.md) and upstream Haxe
4.3.7 oracle evidence where applicable.

Current bounded examples include stdlib `List` / `haxe.ds.List`, which is
package/source-gated to the real stdlib class and emitted from target-owned C++
runtime support to avoid re-rendering the parsed List body in strict-gate
diagnostics. This does not generalize to user-defined classes named `List`.

Reachability and ordering should scan parsed field initializers and method
bodies only for `full_body` helpers. `declaration_only` and `runtime_module`
helpers keep signature/type dependencies, but their parsed bodies must not pull
body-only helpers into the render set.

Sensitive surfaces require separate behavior review before implementation:
Serializer/Unserializer, Float/NaN/Infinity/Math, JSON, binary float encoding,
Reflect/Dynamic, comparisons, and default/no-op runtime support.

If a helper cannot be rendered faithfully yet, prefer an explicit unsupported
diagnostic over fake generated classes or silent default returns.

## Checkpoint Exit

This architecture checkpoint can exit when:

- helper rendering is classified in strict Cpp logs;
- declaration-only versus body-needed decisions have focused evidence;
- runtime-helper invariants and default-stub audit exist for semantic support;
- strict Cpp timing can be interpreted as reduced body pressure, not only as a
  moved timeout frontier;
- README/North Star progress bars remain unchanged unless production readiness
  actually changes.
