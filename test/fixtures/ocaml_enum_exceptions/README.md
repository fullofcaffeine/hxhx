# Enum exceptions in native OCaml

Throwing an enum must preserve its identity and payload. A typed catch must
select the enum type, even when another enum has the same constructor name.

This observer compares fixed expected output with upstream Haxe and a compiled
native OCaml executable. It covers singleton and payload constructors, wrong-type
handlers, Dynamic rethrows, unmatched inner handlers, mutable catch bindings,
null, operand evaluation count, and return/break/continue destinations.

Run `haxe test/m14_stage3_exception_integration_test.hxml`.
The existing exception command also retains primitive, class, and ownership tests.
These focused tests do not establish full standard-library exception support.
