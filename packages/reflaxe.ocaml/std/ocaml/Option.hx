package ocaml;

/**
 * OCaml-native option surface.
 *
 * The compiler special-cases this enum to emit native OCaml `option` constructors (`None`/`Some`).
 */
enum Option<T> {
	None;
	Some(value:T);
}
