# Stage3 abstract constructors that assign `this`

An abstract has no object of its own. At run time its value is the backing
value, and its constructor picks that value with `this = value`:

```haxe
abstract Bag(Map<String, Int>) {
	public function new() this = new Map();
	public function add(key:String):Void this.set(key, 1);
}
```

`Main.hx` and `Box.hx` build abstracts over `Map`, `Array`, `Float`, `String`,
a class, and a type parameter. The constructors take required, optional, and
default arguments. They assign `this` after other statements, assign it twice,
keep the first value through an early `return`, and call one of the abstract's
own methods after the assignment. Values are built in locals, a static field
initializer, and a static factory method, and every abstract is read back
through its methods.

Before the fix, Stage3 treated `new Bag()` like a class allocation. It returned
an empty `HxAnon` object and dropped the `this = value` statement, so the map
methods received that object. The native program crashed with
`Invalid_argument("Hashtbl: unsupported hash table format")` in `HxMap`. An
abstract declared in another module, such as `Box`, became the placeholder `0`.

`npm run test:m14:stage3-abstract-this-constructor` checks that upstream
Haxe 4.3.7 prints `expected.stdout`. It then builds the program with Stage3 and
requires the native executable to print the same text. It also checks two
programs that upstream Haxe rejects: a constructor that never assigns `this`,
and `this = value` in a method that is not `inline`. Stage3 must reject both
at emit time with a named error.
