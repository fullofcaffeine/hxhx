# JavaScript class startup captures

Run `haxe test/m14_js_class_initialization_scope_test.hxml`.
The command compiles this authored fixture with upstream Haxe and the local
JavaScript backend, then executes both artifacts with Node. Success has no
fixture output; assertion failures stop the test.

Class startup bodies share the generated JavaScript program scope. A host
declaration must remain visible to sibling methods. Two startup bodies that
declare the same local name must retain upstream Haxe's shared binding: both
callbacks observe the later value, 11. Fields assigned during startup must not
be cleared by subsequent declarations without initial values.

Declarations inside a startup loop have a different lifetime. Callbacks from
one iteration share later writes, while callbacks from different iterations
retain separate values. The fixture also observes recursive callbacks after
the loop has finished.
