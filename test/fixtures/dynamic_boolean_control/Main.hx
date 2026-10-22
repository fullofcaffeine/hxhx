/** Exercise Boolean use of Dynamic values at native control and local storage boundaries. */
class Main {
	/** Dynamic is intentional: this fixture checks the compiler's runtime conversion. */
	static function read(label:String, value:Dynamic):Dynamic {
		Sys.println(label);
		return value;
	}

	static function both(left:Dynamic, right:Dynamic):Bool
		return read("left", left) && read("right", right);

	static function either(left:Dynamic, right:Dynamic):Bool
		return read("left", left) || read("right", right);

	static function storage(value:Dynamic):Void {
		var result:Bool = value;
		Sys.println(result);
		result = read("write", value);
		Sys.println(result);
	}

	static function branch(value:Dynamic):Void {
		if (read("condition", value))
			Sys.println("yes");
		else
			Sys.println("no");
		Sys.println(value ? "true-branch" : "false-branch");
	}

	static function loops(value:Dynamic):Void {
		var active:Dynamic = value;
		while (read("while", active)) {
			Sys.println("body");
			active = false;
		}
		do {
			Sys.println("do-body");
		} while (read("do-condition", false));
	}

	static function main():Void {
		Sys.println(both(false, false));
		Sys.println(both(false, true));
		Sys.println(both(true, false));
		Sys.println(both(true, true));
		Sys.println(either(false, false));
		Sys.println(either(false, true));
		Sys.println(either(true, false));
		Sys.println(either(true, true));
		storage(false);
		storage(true);
		branch(false);
		branch(true);
		loops(false);
		loops(true);
	}
}
