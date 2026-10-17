# Guarded switch behavior

These Haxe methods define the input for the upstream observer and the native C++ heap checks. Run `npm run test:m14:cpp-guarded-control` from the repository root.

The expected output records case order, rejected guards, retained array and enum observations, separate captured locals, and loop exits. It also checks returns after a guard with side effects, both outcomes of a runtime guard, and returns inside nested conditions. A non-exhaustive switch must still reach its following statement when its guard rejects the input.

The native observer forces collection inside guards and checks cleanup under address and undefined-behavior sanitizers. Both this fixture and the complete shared forty-output fixture reject missing-return warnings in the generated C++.
