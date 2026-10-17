/** Guard effects, nested retries, and direct returns retain their authored order. */
class Main {
	static function choose(value:Int):Int {
		return switch value {
			case 1 if (false): 7;
			case 1: 9;
			case _: 11;
		};
	}

	static function effects(value:Int):Int {
		var calls = 0;
		final _hx_pattern_0 = 99;
		final selected = switch value {
			case 1 if ({
				calls++;
				false;
			}): 7;
			case 1: 9;
			case _: 11;
		};
		Sys.println(calls);
		return selected + _hx_pattern_0 - 99;
	}

	static function nested(value:Int):Int {
		return switch value {
			case 1 if (switch 2 {
					case 2 if (true): false;
					case _: true;
				}): 7;
			case 1: 9;
			case _: 11;
		};
	}

	static function direct(value:Int):Int {
		switch value {
			case 1 if (false):
				return 7;
			case 1:
				return 9;
			case _:
				return 11;
		}
	}

	/** A statement switch that misses every case continues with the next statement. */
	static function partial(value:Int, enabled:Bool):Int {
		final _hx_bool_argument_0 = 17;
		switch value {
			case 1 if (enabled):
				return 7;
		}
		return _hx_bool_argument_0 - 8;
	}

	/** Erased call arguments become assignable Boolean locals, not casts of assignment targets. */
	static function toggle(flag:Bool):Bool {
		flag = !flag;
		return flag;
	}

	static function describe(flag:Null<Bool>):String {
		return Std.string(flag);
	}

	/** A switch label must not steal the surrounding loop's continue or break. */
	static function loops():Int {
		var index = 0;
		var total = 0;
		while (index < 5) {
			index++;
			switch index {
				case 2 if (true):
					continue;
				case 4 if (true):
					break;
				case _:
					total += index;
			}
		}
		return total;
	}

	static function main():Void {
		Sys.println(choose(1));
		Sys.println(choose(2));
		Sys.println(effects(1));
		Sys.println(effects(2));
		Sys.println(nested(1));
		Sys.println(nested(2));
		Sys.println(direct(1));
		Sys.println(direct(2));
		Sys.println(partial(1, false));
		Sys.println(partial(1, true));
		Sys.println(partial(2, true));
		Sys.println(Std.string(toggle(true)));
		Sys.println(Std.string(toggle(false)));
		Sys.println(describe(null));
		Sys.println(loops());
	}
}
