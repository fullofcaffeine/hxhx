# Second-pass review: nullable String `Reflect.compare`

## Practical result under review

Before this change, native OCaml generation stopped when ordinary Haxe code
called `Reflect.compare(previous, current)` with `previous:Null<String>` and
`current:String`. The compiler now selects a typed nullable-String comparison
before printing OCaml. It does not fall back to comparing arbitrary OCaml
objects.

## Independent behavior source

The pinned Haxe 4.3.7 public contract guarantees that two null values compare as
equal, but deliberately leaves the ordering of one-null pairs to each target.
The retained oracle fixture records interpreter, JavaScript, and Neko behavior
instead of treating the new OCaml output as its own expected result.

Because those stock targets do not share one antisymmetric one-null order, the
OCaml target uses a documented target choice: null sorts before non-null text.
This yields a total order suitable for sorting and inventory checks while
remaining inside Haxe's documented target-defined case.

## Architecture and type review

- The decision lives in the existing sealed `Reflect.compare` plan. Here,
  "sealed" means target syntax can only emit the already-recorded typed choice;
  it cannot guess a comparator from generated text.
- Explicit `Null<String>` gets the new `nullable-string` domain. Exact `String`
  remains a different domain and keeps its prior one-null error.
- A direct call checks the contextual function type before inspecting its two
  argument expressions. This preserves `(Null<String>, Null<String>) -> Int`
  when one actual argument is a concrete `String`.
- The generated comparator parameters remain OCaml `string`. Null checks happen
  before native `<` or `>` comparisons.
- `Dynamic`, `Bool`, unrelated nullable types, and mixed domains remain
  unsupported. No `Obj.compare`, `Stdlib.compare`, `Pervasives.compare`, or
  general `Obj.t` comparison was introduced.
- The existing Haxe null sentinel still enters the String carrier through the
  target's established representation boundary. That pre-existing carrier
  mechanism is not new comparator authority.

## Evidence sensitivity

The focused fixture first failed with the intended unsupported-domain error.
After implementation it proves direct calls, stored function values, all four
null/present pairs, and the guarded compiler-scale call shape. Its report checks
six `nullable-string` decisions separately from five exact-String decisions,
then deliberately corrupts a proof identifier and requires public inspection to
reject it.

All six revision-bound lowering reports were regenerated twice. Their semantic
inventories stayed unchanged; only the expected comparator model and enclosing
pipeline identities changed. The complete portable portfolio then compiled,
built, and checked all 107 fixtures successfully.

## Review conclusion

The implementation is narrow enough for the proven String-null case and keeps
the previous fail-closed boundaries. No architecture escalation is needed for
this slice: the existing typed-plan seam was clear, Haxe 4.3.7 supplied the
behavior boundary, and the broader portable portfolio passed. The current
`hxhx` sources also generated a complete OCaml tree, built a native compiler,
and passed the compiler-scale numeric-literals workload. The former nullable
comparison diagnostic is therefore closed on both the focused and real routes.
