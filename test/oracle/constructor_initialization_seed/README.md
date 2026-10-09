# Abstract constructor initialization

These twenty cases record Haxe 4.3.7 constructor-initialization diagnostics.
They cover branches, throws, loops, catches, short-circuit expressions, and
nested functions. The accepted set is not proof of definite initialization:
Haxe accepts a short-circuit assignment and a do-loop with an early break.
A capture before assignment produces a warning rather than a rejection.

Check the independent expectations through upstream Haxe's public CLI:

```sh
python3 test/oracle/constructor_initialization_seed/check_upstream.py .tmp/constructor-initialization-upstream
```

The runner records each complete source, command, exit status, and diagnostic.
It checks compilation without running the intentional throwing cases.

Observe the accepted edge cases through upstream eval and Neko:

```sh
python3 test/oracle/constructor_initialization_seed/check_runtime.py .tmp/constructor-initialization-runtime
```

The runtime observer uses `Null<Int>` so a static target can compile its null comparison.
Eval and Neko return null when the short-circuit assignment or do-loop assignment does not run.
The runner records observations; it does not assert portable behavior across other targets.
An hxcpp 4.3.2 probe emitted an uninitialized C++ integer for the skipped short-circuit assignment.
Its observed value is undefined behavior and cannot establish an expected runtime result.

Check the shared candidate typer:

```sh
haxe test/m14_abstract_constructor_initialization_test.hxml
```

The candidate currently accepts seven cases that upstream rejects.
Acceptance parity and safe native constructor storage need separate evidence.
These checks do not replace the full constructor effects, capture, or native representation fixtures.
