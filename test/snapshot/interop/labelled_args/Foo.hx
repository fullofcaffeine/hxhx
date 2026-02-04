@:native("Native.Mod")
extern class Foo {
	// Mixed labelled + unlabelled + optional labelled (Haxe has no labelled-arg syntax,
	// so we express it via metadata for extern interop).
	static function f(@:ocamlLabel("x") x:Int, y:Int, @:ocamlLabel("z") ?z:Int):Int;
}
