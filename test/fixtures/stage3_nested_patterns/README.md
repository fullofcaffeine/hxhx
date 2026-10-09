# Match arrays and object fields in native OCaml output

Matching values select their branch. A different element, field, or array
length selects the fallback branch. This ordinary program reduces a failure
found while compiling a real macro that inspects syntax.

Run `npm run test:m14:stage3-nested-patterns` from the repository root.
The test compares upstream Haxe and generated native OCaml output with
`expected.stdout`. A successful compile alone does not satisfy this contract.

The native check includes array lengths, object fields, nested arrays, null access,
and captures in expression and statement switches.
For `[0, result] | [result, 0]`, either matching alternative must return its own captured value.
The fixture checks both alternatives, fallback, nested alternatives, object-field alternatives,
and captures of an entire nested array.

The companion null-pattern fixture checks which later null cases protect nested accesses.
Full non-null enum payload behavior and unsupported guard execution remain unfinished.
These checks support `haxe_ocaml-yhvzj`; they do not prove complete switch parity.

Boolean captures are checked at the root, in an array, and in a record field.
Record storage uses a Boolean box; the captured Bool must read the value inside it.
A record capture and a root binding work without an artificial default case.
The test driver also rejects incomplete array, record-literal, guarded, and
static-constant patterns before a value switch can use an unassigned result.
