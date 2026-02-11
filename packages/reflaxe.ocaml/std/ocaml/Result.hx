package ocaml;

/**
 * OCaml-native result surface.
 *
 * The compiler special-cases this enum to emit native OCaml `result` constructors (`Ok`/`Error`).
 */
enum Result<T, E> {
	Ok(value:T);
	Error(error:E);
}

