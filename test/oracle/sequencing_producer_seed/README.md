# Sequencing producer behavior

A field initializer increments the counter once before producing 11.
A function increments it twice, then returns an authored local whose name resembles a compiler temporary.
The final counter value is 3.
Both sequences call a function that returns `Void`; discarding its result must preserve its effect.

Run the upstream Haxe 4.3.7 baseline:

```sh
haxe -cp test/oracle/sequencing_producer_seed/src --run Main
```

Compare its three lines with `expected.stdout`.
Run generated target code with:

```sh
haxe test/m14_sequencing_native_integration_test.hxml js
```

The driver also accepts `python`, `php`, `cpp`, `neko`, `java`, and `lua`.
JavaScript, Python, and PHP currently pass this complete observer.
C++ native validation remains incomplete.
Neko static initialization is tracked by `haxe_ocaml-1wi5b`.
Java and Lua class emission is tracked by `haxe_ocaml-2x217`.
Keep this fixture's full expectation while those target repairs proceed.
