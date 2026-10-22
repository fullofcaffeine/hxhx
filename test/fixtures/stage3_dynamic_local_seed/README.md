This program stores Bool, Int, String, and null values in Dynamic locals.
It checks initialization, reassignment, copying, branch results, and compound assignment.
The output also distinguishes Boolean values from integers and counts observable calls.
Authored locals with the generated temporary names check that conversion does not shadow source bindings.

Run `haxe test/m14_stage3_dynamic_local_storage_test.hxml` to compare native OCaml output with upstream Haxe and the independent expected output.
The test also checks that projected writes reject foreign and mutated operands.

Static initializer blocks run before `main`. Their local declarations and writes
use the field initializer's own type information, including Bool-to-Dynamic storage.
The initial `observed` and `amount` lines prove each helper runs once.
The initializer ownership checks reject operands from another projection, a wrong
destination, and an operand changed after projection.
