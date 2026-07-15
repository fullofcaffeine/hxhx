# C++ Abstract-Operator Architecture Decision — 2026-07-15

Status: external GPT-5.5 Pro review accepted with repository-owned corrections

Review candidate: `a2204f4429a1621d18012729b703a9ebd5880b5a`

Review package SHA-256:
`546102496fc277be1a3b87ad6526284c5c746d4c177f10fd3e19af48bd27f419`

Owning and follow-up beads:

- `haxe_ocaml-4vf5p` — preserve structured unary syntax across every active
  consumer;
- `haxe_ocaml-d5ow7` — add canonical semantic identities and the shared
  abstract-operator catalog;
- `haxe_ocaml-g7gyg` — retain enum-abstract member semantics in that catalog;
- `haxe_ocaml-idem2` — carry structural typed function bodies into every
  backend;
- `haxe_ocaml-ass5p` — bind and lower the proven unary subset, then unblock
  strict C++;
- `haxe_ocaml-x9ua7` — retire C++ abstract binary helper-name dispatch;
- `haxe_ocaml-dyom3` — make C++ abstract carrier and conversion policy
  explicit.

## Practical outcome

The review confirms that the current strict C++ failure cannot be repaired
safely inside the C++ renderer. `hxhx` currently loses prefix/postfix syntax
before typing, does not retain typed expression bodies, and asks C++ to infer
some abstract behavior from target types, method names, and small source-body
patterns. Those are three symptoms of the same ownership gap.

The accepted direction is a staged core-compiler repair:

1. preserve what the user wrote;
2. load abstract declarations and operator metadata into one shared semantic
   catalog;
3. retain structurally typed function bodies;
4. select and completely lower abstract operators in the typer;
5. let each backend choose only representation and emission.

C++ must never become a second Haxe typer. It receives an exact call, ordinary
unary operation, or explicit block containing the required reads, writes,
temporaries, and result.

## Repository validation

At review intake, the review's central source claims reproduced on candidate
`a2204f4429a1621d18012729b703a9ebd5880b5a`. The bullets below describe that
pre-migration baseline, not the repository after the numbered beads land:

- `HxParser` retains postfix increment/decrement as string-tagged `EUnop`
  values but rewrites prefix increment/decrement into compound assignment;
- `HxExpr.EUnop` stores only a raw operator string and operand;
- `TyperStage` computes best-effort types but returns the original parsed body;
- `TypedModule` contains only `ParsedModule` plus `TyModuleEnv`;
- active backends still obtain semantic function bodies from parsed
  declarations;
- `TyType` is string-backed, while `TyFunSig` omits declaration identity,
  metadata, and body ownership;
- C++ emits raw unary syntax and has existing abstract behavior selected by
  helper names, target-rendered types, and tiny body recognizers;
- `CppTargetCore.hx` is approximately 26.8k lines, so new semantic ownership
  does not belong there.

The review was based on a 29-file focused bundle. Current repository searches
confirm the supplied audit scale: 26 non-generated Haxe files inspect
`EUnop`, with source, VM, C++, JavaScript, OCaml/bootstrap, macro, diagnostic,
and analysis consumers represented.

## Accepted ownership model

| Responsibility | Owner |
| --- | --- |
| Preserve unary token and prefix/postfix fixity | Parser and shared syntax tree |
| Parse and validate `@:op` declarations | Shared semantic index |
| Select the exact declaration and report ambiguity/failure | Typer |
| Decide call, inline expansion, mutation, evaluation schedule, and result | Shared typed lowering |
| Choose primitive carrier, pointer, direct underlying value, or wrapper | Backend representation layer |
| Print or execute target constructs | Backend emitter |

The shared backend input is a typed semantic body, not a speculative
target-neutral `GenIrProgram`. `GenIrProgram` remains an alias until repeated
cross-backend target normalization proves a separate IR is justified.

## Corrections and refinements

The response is advisory. Eight details were corrected or narrowed before
integration.

### Unary positive is not part of the syntax model

The review listed unary positive among the structured tokens. An original,
ignored black-box fixture run with upstream Haxe `4.3.7` rejected `+value` with
`Expected expression or )`. The public Haxe `4.3.7` macro `Unop` surface also
has no unary-positive constructor.

Therefore the first structured syntax model covers:

- increment;
- decrement;
- arithmetic negation;
- logical not;
- bitwise not.

Prefix/postfix fixity is a separate value. Postfix is valid only for increment
and decrement. The existing parser acceptance test for unary positive is local
drift and must be replaced with an upstream-compatible rejection test.

Spread remains represented by the existing explicit spread-call seam for this
slice. Reclassifying spread as `EUnop` is outside `haxe_ocaml-4vf5p`.

### Catalog and typed-body migration are separate beads

The response proposed one combined catalog-and-typed-body bead. Current source
shows that the semantic index and the all-backend body-source cutover are each
large enough to need independent tests, bootstrap review, and rollback
boundaries. They are now `haxe_ocaml-d5ow7` and `haxe_ocaml-idem2`, with the
typed-body bead depending on the catalog bead.

This split does not weaken the architecture. `haxe_ocaml-ass5p` remains blocked
until both are complete.

### Stable identity means deterministic structural identity

The review correctly rejects object identity, traversal order, and source
offset as binding keys. It does not require allocation-order integer IDs.
Canonical owner identity plus a deterministic declaration discriminator is a
valid implementation direction and is friendlier to semantic dumps,
snapshots, and reproducible diagnostics.

The catalog bead owns the exact representation. Whatever representation is
chosen must be stable for an unchanged program, independent of backend
traversal, and distinct across overloads.

### Parsed declarations remain available; parsed bodies do not

Backends legitimately use parsed modules for imports, declaration metadata,
source paths, diagnostics, macro quotation, and provenance. The future guard
must prohibit parsed **function-body** reads for semantic emission without
blanket-banning `TypedModule.getParsed()`.

After the typed-body cutover, source and VM backends must obtain function
bodies from `TypedModule`. Parsed declaration access is not itself a violation.

### C++ extraction is an ownership constraint, not a line-count ritual

New catalog, binding, mutation, and evaluation semantics add zero ownership to
`CppTargetCore`. C++ representation and resolved-call emission belong in
extracted modules, with only thin dispatch in the existing core.

A net-zero or net-negative line count in `CppTargetCore` is a useful review
target, not a substitute for responsibility and behavior evidence. Likewise,
the exact native helper namespace/container is provisional until focused C++
ABI and carrier tests select it.

### Reported evaluation counts must be reproduced locally

The review reports that its Haxe `4.3.7` fixtures observed different index
evaluation counts for ordinary and overloaded indexed increment. That is a
valuable lowering constraint, but the prose response is not repository proof.
Before `haxe_ocaml-ass5p` implements place/evaluation lowering, it must rerun a
repo-owned black-box fixture against the local upstream Haxe `4.3.7` oracle on
the interpreter, JavaScript, and Neko lanes and record the exact outputs in the
bead. No reviewed fixture or upstream test source is copied into this repo.

### Operator placeholder names are not semantic identities

The operand expression inside unary `@:op` metadata determines the token and
fixity, but its identifier spelling is not a binding key. Haxe `4.3.7` stdlib
declarations use both uppercase forms such as `@:op(-A)` and lowercase forms
such as `@:op(-a)`. The catalog therefore parses the complete metadata
expression, records only the structured unary token/fixity, and validates the
owning abstract through the declaration's semantic signature.

### Enum-abstract coverage is an explicit follow-up

The current frontend already marks enum abstracts as abstracts and retains
their value fields, but it does not yet retain their complete member-function,
generic-header, and underlying-type surface. The first catalog bead therefore
proves regular Haxe abstracts only. `haxe_ocaml-g7gyg` owns the parser/model
extension needed before the project can claim that all enum-abstract operators
participate in the shared catalog. This does not block the focused regular-
abstract unary C++ frontier.

## Required semantic invariants

- Prefix increment, postfix increment, and source-written compound assignment
  remain distinct from parsing through typed lowering.
- Operator metadata is parsed once into a shared canonical descriptor.
- Abstract semantic identity survives primitive carrier erasure.
- Operator selection uses semantic types and declarations, never generated
  carrier types, local hints, helper names, or source-body patterns.
- Static helpers have no invented writeback.
- Prefix/postfix spelling does not invent old-value or new-value semantics;
  the selected declaration or inline body determines the result.
- Inline mutation reaches the original assignable place rather than a detached
  carrier temporary.
- Receiver, index, getter, setter, helper, and operand evaluation occurrences
  required by upstream-compatible lowering are structurally explicit.
- The strict profile preserves locally reproduced upstream Haxe `4.3.7`
  evaluation counts, including repeated overloaded array-index evaluation if
  the required black-box revalidation confirms the review's observation.
- Unsupported, missing, generic, ambiguous, or unrepresentable operator cases
  fail deterministically before native C++ compilation. There is no carrier
  fallback.
- Every backend receives the same exact declaration and lowered semantic tree.
- Parsed and typed bodies belong to one immutable program revision; later body
  mutation requires explicit invalidation and retyping.

## Migration sequence

### 1. Structured syntax — `haxe_ocaml-4vf5p`

Replace raw unary strings with a structured token plus fixity. Update parser,
all shared traversals, macro conversion, macro quotation, diagnostics, every
active backend, focused tests, and required bootstrap snapshots together.

This bead claims syntax identity and ordinary operator compatibility only.

### 2. Semantic identities and catalog — `haxe_ocaml-d5ow7`

Introduce canonical nominal/declaration identities, `TyAbstractInfo`, and a
shared operator catalog reachable through `TyperIndex`. Parse and validate
unary `@:op` metadata once. Do not change target operator behavior yet.

### 3. Typed function bodies — `haxe_ocaml-idem2`

Add a structurally recursive typed-body spine and hard-cut active backends from
parsed function bodies to typed function bodies. Preserve parsed declaration
and provenance access. Add an invariant scan so bindable operators or mutation
cannot hide in opaque leaves.

### 4. Shared unary binding and C++ unblock — `haxe_ocaml-ass5p`

Bind the oracle-proven non-generic exact unary subset. Lower each selection to
an exact call, ordinary unary node, inline body, or explicit typed block. Prove
the same semantic decision on at least two non-C++ targets, then add extracted
C++ representation/helper emission and rerun the exact strict frontier.

### 5. Binary semantic ownership — `haxe_ocaml-x9ua7`

Migrate existing binary and compound abstract behavior from C++ helper-name
selection into the shared catalog, binder, and lowering. Freeze the existing
name-driven cases until deletion; do not add new ones.

### 6. Carrier and conversion cleanup — `haxe_ocaml-dyom3`

Audit wrappers versus direct underlying carriers per abstract, move conversion
selection toward the shared semantic model, remove semantic dependence on
local type hints, and delete remaining primitive helper/body recognizers.

## Rejected shortcuts

- recovering prefix syntax from `value += 1`;
- encoding `pre++` and `post++` as permanent strings;
- resolving `@:op` independently in each backend;
- using C++ carrier types or local source hints as semantic types;
- selecting arbitrary operator helpers by method name;
- carrying only a helper ID and making the backend decide mutation/result;
- assigning every helper result back or passing every instance helper by
  reference;
- imposing a target-local exactly-once evaluation policy;
- binding through object identity, traversal index, or source offset;
- rebranding `GenIrProgram` as a speculative compiler-wide IR;
- parsing inline helper bodies inside C++;
- falling back to a raw carrier operator for unsupported abstract behavior;
- adding generated stub classes or runtime string fragments to hide the
  semantic failure.

## Validation and claim boundary

Each behavior bead starts with original repo-owned failing coverage, then uses
the narrowest relevant gate before broader current-source, bootstrap, strict
suite, and CI evidence. Snapshot regeneration must be allowlisted from the
known consumer inventory and reviewed semantically. Generated snapshots are
never hand-edited.

Upstream Haxe remains a black-box behavior oracle. No upstream compiler or test
source was copied into this decision or requested implementation.

This review changes the implementation plan, not current user capability.
README Goals progress bars remain unchanged. `NORTH_STAR_GOALS.md` links this
decision from the strict C++ checkpoint but does not increase readiness.
