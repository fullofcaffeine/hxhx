@:native("Native.Mod")
extern class Foo {
	static function f(@:ocamlLabel("x") x:Int, @:ocamlLabel("y") ?y:Int):Int;
}
