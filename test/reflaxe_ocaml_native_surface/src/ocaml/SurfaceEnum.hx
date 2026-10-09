package ocaml;

/** A native enum whose actual argument must retain normal query order. */
enum SurfaceEnum<T> {
	Value(value:T);
}
