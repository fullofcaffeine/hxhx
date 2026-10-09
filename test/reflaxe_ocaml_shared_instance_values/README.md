# Nullable instance calls through the shared OCaml target

This fixture preserves the nullable instance-call program from `M14CallArgumentControlTest`.
It constructs `Sink`, calls `put` with an integer and null, and checks the original results.
The original integration test remains required and unchanged.

Run from the repository root:

```sh
node_modules/.bin/haxe test/reflaxe_ocaml_shared_instance_values/test.hxml
```

The test first executes the authored assertions with upstream Haxe.
It requires both host adapters to retain the constructor, instance method, and main function with equal target facts.
It then invokes the native wrapper, builds the emitted OCaml application, and runs those same assertions.
It never calls Stage3 `EmitterStage` and cannot substitute standalone-only execution for native-adapter acceptance.

The shared target does not yet admit this complete program. This is a required failing acceptance fixture, outside the passing aggregate.
The frontend and wrapper run under upstream Haxe's interpreter; a pass alone would not prove a rebuilt native frontend.
Mutable receiver state, stored method identity, dynamic replacement, inheritance, and capture order retain their existing integration contracts under `haxe_ocaml-i1c2c`.

The shared method body has a separate, passing contract:

```sh
npm run test:reflaxe-ocaml:shared-instance-method-body
```

This command compares both adapters' facts and emitted syntax for `Sink.put`.
It rejects use of that method as a static function and verifies the unchanged native typed module.
It then runs the original source under upstream Haxe and through standalone OCaml compilation.
The standalone compiler must use the shared method body, with its existing receiver parameter and class layout.
This route does not require the optional whole-program comparison report.

The fast adapter check is included in `test:reflaxe-ocaml:target-definition`.
Its success does not close construction or instance-call support in the native program wrapper.

Class headers have a separate prerequisite check:

```sh
node_modules/.bin/haxe test/reflaxe_ocaml_shared_instance_values/class-headers.hxml
```

Both adapters must preserve interface and extern flags, secondary-class names, and the applied `Contract<Int>` relationship.
The declaration identity includes these facts and owns a copy of the interface list.
The current program emitter rejects interface relationships and extern or interface main types before selecting a layout.
These checks do not prove interface dispatch, inheritance, or arbitrary generic type arguments.
