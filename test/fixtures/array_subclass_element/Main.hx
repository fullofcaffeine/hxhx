/**
	Array literals whose expected element type is a superclass or an interface accept
	subclass and implementing elements, as upstream Haxe 4.3.7 does (haxe_ocaml-h9hun).
**/
class Base {
	public function new() {}

	public function name():String
		return "base";
}

class Sub extends Base {
	public function new()
		super();

	override public function name():String
		return "sub";
}

interface Named {
	function label():String;
}

class Thing implements Named {
	public function new() {}

	public function label():String
		return "thing";
}

class Main {
	static function names(items:Array<Base>):String
		return [for (item in items) item.name()].join(",");

	static function main() {
		final declared:Array<Base> = [new Sub(), new Base()];
		final labels:Array<Named> = [new Thing()];
		Sys.println(names(declared) + " " + labels[0].label() + " " + names([new Sub()]));
	}
}
