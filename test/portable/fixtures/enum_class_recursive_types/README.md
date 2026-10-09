# Enum and class type dependencies

This fixture checks a class field whose enum can contain another instance of
that class. Haxe accepts both source declaration orders. OCaml must declare
each mutually dependent pair together with `type ... and ...`.

The third case checks an enum payload that depends on a class without recursion.
The expected runtime output is `2`, `2`, then `7`, one value per line.

Run `npm run test:reflaxe-ocaml:type-declaration-order` from the repository root.
The command also retains the existing rejection test for cycles between class
records. It does not establish support for cycles between separate modules.
