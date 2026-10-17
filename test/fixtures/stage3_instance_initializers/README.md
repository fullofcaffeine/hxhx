# Instance field initialization

Run `haxe test/m14_stage3_instance_initializers_test.hxml`.

The authored program must match `expected.stdout` under upstream Haxe 4.3.7
and native OCaml execution. It observes constructor arguments before field
effects, child fields before the child body, parent fields at `super`, and
fields on a constructor-free descendant before its inherited constructor.
The initialized callable field must execute through the same object.

Haxe 4.3.7 initializes a class's fields in reverse declaration order. The program
checks that order with two observable field effects, a Boolean stored through
Dynamic, block-local name isolation, and a captured counter with independent
state for each object. A same-class factory and an object created during static
initialization exercise helper dependencies. The test rejects foreign class
projections and mutated initializer bodies before emission.
An exception in a field initializer must skip remaining fields and the
constructor body while reaching the surrounding catch.
