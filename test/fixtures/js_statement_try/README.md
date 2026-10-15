# JavaScript statement try and throw

Run `haxe test/m14_js_stmt_emitter_try_throw_integration_test.hxml` from the repository root.
The same authored source runs through upstream Haxe and the candidate JavaScript backend.
Assertions check a local conditional throw, its constructor argument, normal and typed-catch returns,
and a Dynamic fallback. Reader controls the I/O outcomes while checking the captured buffer,
offset, length, and exactly three invocations. The actual Eof and Std providers remain required.
The enclosing test also retains direct throw/catch and super-call emission assertions.
