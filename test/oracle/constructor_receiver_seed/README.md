# Constructor receiver observations

These programs examine what constructor closures retain and how an unassigned
receiver crosses ordinary value boundaries. They use upstream Haxe 4.3.7 through
its public CLI. The runner records acceptance, diagnostics, runtime output,
commands, and source hashes for eval and Neko.

```sh
python3 test/oracle/constructor_receiver_seed/check_upstream.py .tmp/constructor-receiver-upstream
```

The primitive case invokes closures inside and after construction, then writes
through an escaped closure. It compares capture before and after assignment.
The array case separates a captured receiver binding, its current array, and a
saved earlier array. It compares element mutation with receiver rebinding.
The transport case observes a skipped assignment through an Int return, generic
function, class field, record, array, and validated erased-value boundary.
It also observes explicit null and zero with a nullable backing type.

The expected stdout files come from the initial public eval and Neko observations.
Both targets agree. The runner now checks these expectations and the initialization
warning for capture before assignment. Its records distinguish the combined eval
compile/run command from Neko's separate compile and runtime commands.

The captured receiver binding survives construction. Later rebinding changes the
closure's result but leaves the previously returned primitive or array unchanged.
Array element mutation remains visible through aliases to that same array.
The skipped assignment remains null through every observed transport boundary,
including the declared Int return. Explicit null remains distinct from zero.

Run the native candidate contract with its real dependency closure:

```sh
haxe test/m14_constructor_receiver_test.hxml
```

This candidate test requires every program to compile and match the retained
output. It collects all three failures instead of hiding later failures behind
the first. These profiles do not establish portable behavior for other upstream
targets or native hxhx readiness.
