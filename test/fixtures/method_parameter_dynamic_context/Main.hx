/** Dynamic destinations accept an input without supplying its missing type. */
class Main {
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

	static function explicit(value:Dynamic):Dynamic
		return value;

	static function unused(value):Void {}

	static function main():Void {}
}
