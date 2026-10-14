# JavaScript abstract values

Run `haxe test/m14_js_abstract_value_test.hxml` from the repository root.
The test compares generated JavaScript with the specified stdout and upstream Haxe 4.3.7 eval.

An abstract must expose its backing value after construction and header conversion.
The fixture observes String and class-backed identity, null receivers, captured methods,
generic and nested abstracts, field initialization, conversion effects, and ordinary object casts.
Reading an abstract method twice creates two distinct closures.
An ordinary field named `__hx_value` must never trigger value extraction.

The driver also rejects copied operations, foreign executable owners, and stale authored bodies.
Replacing a projected cast with an equal copy invalidates the original cast in shared lookup.
It checks the declared source and destination of the retained header conversion.
JavaScript erases the cast annotation because the abstract already has its backing representation.
Executable conversion methods remain explicit calls in the shared typed body.
The existing output-method and conditional-result tests supply additional conversion-priority and branch-effect coverage.
