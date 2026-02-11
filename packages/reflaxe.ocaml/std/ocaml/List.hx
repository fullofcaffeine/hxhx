package ocaml;

/**
 * OCaml-native list surface.
 *
 * The compiler special-cases this enum to emit native OCaml `[]` / `(::)` constructs.
 */
enum List<T> {
	Nil;
	Cons(head:T, tail:List<T>);
}

