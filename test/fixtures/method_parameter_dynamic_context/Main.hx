/** Dynamic destinations accept an input without supplying its missing type. */
class Main {
	static function alias(value):Dynamic {
		var copy = value;
		return explicit(copy);
	}

	static function call(value):Dynamic
		return explicit(value);

	static function direct(value):Dynamic
		return value;

	static function local(value):Void {
		var erased:Dynamic = value;
	}

	static function later(value):Dynamic {
		var erased:Dynamic = value;
		var selected:Int = value;
		return selected;
	}

	static function explicit(value:Dynamic):Dynamic {
		Sys.println("consume");
		return value;
	}

	static function unused(value):Void {}

	static function main():Void {
		var direct:Dynamic->Dynamic = call;
		var indirect:Dynamic->Dynamic = alias;
		var number:Dynamic = 7;
		var text:Dynamic = "ok";
		var boolean:Dynamic = true;
		Sys.println(direct(number));
		Sys.println(indirect(text));
		Sys.println(direct(boolean));
	}
}
