# Stage3 Dynamic method call native-only fixture

`M14Stage3DynamicMethodCallTest` requires the native program to print exactly `expected.stdout`.

- The calls of a method with a rest argument run natively. Upstream's interpreter stops on those calls, so they
  have no upstream result to compare with.
- Every other call in `Main.hx` cannot reach a class method. The native program must catch a named error for each
  call. Upstream runs some of these calls and reports others with its own text.
