# Stage3 Dynamic method call error fixture

Each call in `Main.hx` cannot reach a class method in a native Stage3 program. `M14Stage3DynamicMethodCallTest`
requires the native program to catch a named error for each call and to print exactly `expected.stdout`. Upstream
Haxe runs some of these calls and reports others with its own text, so this fixture is compared with the native
program only.
