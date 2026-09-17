package haxe.atomic;

/** An atomic enum provides an independent package-family expectation. */
enum SurfaceEnum<T> {
	Value(value:T);
}
