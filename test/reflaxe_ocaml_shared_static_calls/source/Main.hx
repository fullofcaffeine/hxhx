/** A same-class call chain whose names require declaration-aware OCaml emission. **/
class Main {
	static function main():Void {
		var hx_type:Int = 3;
		hx_type;
		middle();
		type();
		ignore();
	}

	static function middle():Void {
		type();
	}

	static function type():Void {
		var value:Int = 7;
		value;
		ignore();
	}

	static function ignore():Void {}
}
