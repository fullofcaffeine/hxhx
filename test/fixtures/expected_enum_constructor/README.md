# Expected enum constructor selection

Run `haxe test/m14_expected_enum_constructor_test.hxml` from the repository root.
The existing `test:m14:module-import-alias-targets` command also runs this test.

Two imported enums declare `Build` with different argument types. A written
`First` result selects `First.Build`, regardless of import order. With no result
annotation, the later `Second` import supplies the constructor. Arguments must
match the selected declaration. Local functions and current class methods keep
their existing precedence over enum constructors.

The test compares upstream Haxe behavior with local typing and checks the exact
constructor declaration stored in the typed body. It also covers imported
function collisions, local and class method precedence, nullable results, and
typedef results. A call without an expected type must remain a function when
that function returns an enum.

It compiles the imported `Main` observer to OCaml and compares native
runtime output with `expected.stdout`. All three required source modules remain
in the program, with its entry module first as the compiler API requires. The
observer includes optional record payloads, explicitly qualified constructor
calls, and a switch result. Switch patterns use short constructor names. This
test does not establish macro dispatch or host ABI support.
