# Managed native stack capture

Run `npm run test:m14:cpp-native-stack-capture` from the repository root.
The fixture loads the real common `haxe.NativeStackTrace` declaration and keeps
its opaque `Any` result in an ordinary static field after the capturing method
returns. A separate native observer checks the snapshot after collection.

The release build captures an empty frame list. The debug build records the
declared `capture` and `main` methods in that order. Both profiles run normally
and under ASan/UBSan at `-O0` and `-O2`. The test also rejects a same-named local
method as a native binding and rejects a changed declaration signature.

The command also runs `ExceptionMain` through a native catch observer.
Its first `exceptionStack()` result is empty. After an authored throw, a debug
snapshot records `origin` followed by `main`, even after those methods unwind.
A second throw replaces the stored origin without changing the earlier result.
The observer checks thrown values and collection after the roots leave scope.
Run this part alone with `npm run test:m14:cpp-native-exception-stack`.

These checks cover raw capture and managed lifetime through normal compiler
emission. The observer catches the native carrier; it does not exercise Haxe
catch selection or implicit exception wrapping. Public `CallStack` conversion,
source-line positions, closure frames, and full rethrow integration remain part
of `haxe_ocaml-k9scs` and `haxe_ocaml-qrk0u`.

The compiler uses the existing program storage for its synchronous stack context.
There is no global stack singleton. It enables frame recording only when a stack
capture binding is reachable and the debug define is present. Source files and
line positions remain absent until their exact emission plan exists. Debug
closure capture is rejected explicitly instead of silently losing its frames.
