package haxe.io;

/**
	OCaml target override for `haxe.io.BytesData`.

	`BytesData` is the target-native mutable OCaml `bytes` value stored inside
	`HxBytes.t`. It remains opaque to portable Haxe code. The Haxe-authored
	target type mapper gives this exact abstract the native `bytes` carrier, so
	`getData()`, `ofData()`, and the private `Bytes(length, data)` constructor
	preserve one shared data alias without exposing `ocaml.*` to portable code.
**/
abstract BytesData(Dynamic) {}
