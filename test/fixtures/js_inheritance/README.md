# JavaScript inheritance

Run `haxe test/m14_js_inheritance_test.hxml` from the repository root.
The test compares upstream Haxe output with generated JavaScript executed by Node.

The child appears before its parent. It passes two effectful arguments through
its constructor, prints before and after `super`, and overrides a parent method.
The expected output proves argument order, parent initialization, and override dispatch.
A native JavaScript observer also checks the child class marker and parent prototype.

The fixture also checks a child of `GenericParent<String>` and its inherited method.
Broader generic-interface integration remains tracked under `haxe_ocaml-7bjsd`.
Passing these focused tests does not
establish full JavaScript compatibility or change README Goals status.

The main fixture also checks omitted constructors across two inheritance levels.
They must forward supplied arguments and let the declaring parent apply its default.

Run `haxe test/m14_js_static_inheritance_cycle_test.hxml` to check a parent whose
static field reads its child's field. Upstream warns about the initialization cycle.
The parent observes the value before initialization, so the Haxe null comparison
is true. Class creation must finish before static values are initialized.
The fixture also retains a bare static-field read inside an instance method.
