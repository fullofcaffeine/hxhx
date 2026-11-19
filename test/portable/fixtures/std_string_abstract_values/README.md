# Print abstract values with Std.string

`Std.string` of an abstract value must print the value it stores, as upstream Haxe 4.3.7
does on `--interp` and the JVM: `enum abstract Mime(String)` prints `application/json`, an
abstract over `Int` prints `404`, and over `Bool` and `Float` prints `true` and `1.5`. A
`Null<Mime>` or `Null<Code>` prints its value or `null`. An abstract with its own `toString`
prints through it, because the Haxe typer calls it.

`reflaxe.ocaml` printed the literal `<unsupported>` for an abstract that is not a core type,
and a `Null<Mime>` failed to compile with "static String syntax has no sealed source
occurrence" (`haxe_ocaml-trjbi`). The static string planner now follows such abstracts to
their underlying type, `Int` and `Bool` abstracts print through the same follow, and
`Null<A>` of such an abstract, which is stored as `Obj.t`, prints through the Dynamic path.

Run `PORTABLE_FIXTURE_ALLOWLIST=std_string_abstract_values bash scripts/test-portable.sh`.
The portable runner builds and runs native output against expected.stdout.
The extra test compares the same program with upstream Haxe eval.
