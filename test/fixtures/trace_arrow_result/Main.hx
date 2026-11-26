/**
	An arrow whose body is `trace(...)` returns Void, as in Haxe 4.3.7 (haxe_ocaml-n4s2a, upstream
	issues/Issue7332), also when it is passed for a generic callback such as `f:T->Void`.
**/
class Basic {}

class Sprite extends Basic {
	final name:String;

	public function new(name:String)
		this.name = name;

	public function toString():String
		return "sprite " + name;
}

class Main {
	static function forEach<T:Basic>(items:Array<T>, f:T->Void)
		for (item in items)
			f(item);

	static function each<T>(items:Array<T>, f:T->Void)
		for (item in items)
			f(item);

	static function main() {
		forEach([new Sprite("a"), new Sprite("b")], sprite -> trace(sprite));
		each([1, 2], value -> trace(value));
	}
}
