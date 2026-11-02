# Stage3 inline structural method types

`Main.hx` writes structure types in place, in the declaration form that a
typedef uses, and fills them with object literals and with class instances:

```haxe
static function provide():{ function value():Int; }
	return new Answer();

if (provide().value() != 7) throw "result";
```

Upstream Haxe 4.3.7 prints `ok`. Two problems hid behind each other:

1. The parser keeps a written annotation as compact text, and it joined the
   words `function value` into `{functionvalue():Int;}`. The return type stayed
   unresolved, while the same structure written as a named typedef resolved.
   Inline `{ var value:Void->Int; }` hit the same problem.
2. Once the type resolved, the native program still crashed with a signal. A
   Stage3 class instance keeps its fields in its object storage, but its
   methods are module-level OCaml functions. Reading `value` through the
   structure type found no stored field, and the call jumped through a null
   value. This happened with a named typedef too.

The program calls each method field directly, stores it in a local, passes
the value to a function, and reads it from an array. It covers a method
without arguments, a method with arguments, an overriding subclass, a mixed
structure with a variable and a method, and a variable field that holds a
function.

`npm run test:m14:stage3-inline-structural-methods` checks that upstream Haxe
prints `expected.stdout`, then builds the program with Stage3 and requires
the native executable to print the same text. The typed facts for the inline
and named forms are compared by `npm run test:m14:inline-structural-method-typing`.

Lambdas in the fixture declare their argument types. An untyped lambda such
as `{add: (a, b) -> a * b}` passed to a structural parameter is still rejected
by the typer, with a named typedef too (`haxe_ocaml-4feof`).
