package haxe.io;

/**
	OCaml target override for `haxe.io.BytesData`.

	`BytesData` remains an opaque carrier in the portable lane so upstream stdlib
	code can keep using target-specific storage internals without forcing a public
	representation contract in Haxe types.
**/
typedef BytesData = Dynamic;
