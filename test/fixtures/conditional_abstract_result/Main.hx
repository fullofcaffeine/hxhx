/** An ordinary header conversion preserves the stored integer. */
abstract Count(Int) from Int to Int {}

/** An executable conversion must run once, inside the selected branch. */
abstract Logged(Int) from Int {
	@:to public function asInt():Int {
		Main.conversions = Main.conversions + 1;
		return this + 100;
	}
}

/** Observe declared conditional results and the effects of selected conversions. */
class Main {
	public static var conversions:Int = 0;

	static function choose(flag:Bool, value:Count):Int {
		return flag ? value : 3;
	}

	static function effect(flag:Bool, value:Logged):Int {
		return flag ? value : 3;
	}

	static function branch(flag:Bool, value:Logged):Int {
		final result:Int = if (flag) value else 3;
		return result;
	}

	static function grouped(flag:Bool, value:Logged):Int {
		final result:Int = if (flag) {
			value;
		} else {
			3;
		};
		return result;
	}

	static function nested(flag:Bool, value:Logged):Int {
		return flag ? (flag ? 3 : value) : value;
	}

	static function main():Void {
		Sys.println(choose(true, 7));
		Sys.println(choose(false, 7));
		Sys.println(effect(true, 7));
		Sys.println(conversions);
		Sys.println(effect(false, 7));
		Sys.println(conversions);
		Sys.println(branch(true, 7));
		Sys.println(conversions);
		Sys.println(branch(false, 7));
		Sys.println(conversions);
		Sys.println(grouped(true, 7));
		Sys.println(conversions);
		Sys.println(grouped(false, 7));
		Sys.println(conversions);
		Sys.println(nested(true, 7));
		Sys.println(conversions);
		Sys.println(nested(false, 7));
		Sys.println(conversions);
	}
}
