This fixture checks PHP runtime type values and tests against upstream Haxe.

`Main` distinguishes String and two user classes in a class-valued switch.
`TypeTests` checks primitive, String, and Array predicates, evaluates an operand once,
and carries type values through a static initializer and a nested closure.
It distinguishes class values from instances and checks inheritance and null operands.
Predicates select explicit text branches to isolate type-test behavior from console formatting.

The integration test also rejects copied, foreign, removed, and mutated type occurrences.
A missing nominal provider must fail before creating output or replacing an existing artifact.
These checks validate the exact typed occurrence before PHP rewrites expression nodes.

Run `haxe test/m14_php_runtime_type_operands_integration_test.hxml`.
The test compares native PHP output when PHP is installed and reports source-only coverage otherwise.
The existing numeric runtime helpers are unchanged; this is not a numeric-formatting or Full1 parity claim.
