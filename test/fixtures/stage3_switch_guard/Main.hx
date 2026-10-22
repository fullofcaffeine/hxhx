/** Payload locals must remain available to both the guard and its selected body. */
enum Token {
	Pair(number:Int, text:String);
	Empty;
}

/** Header conversions must supply the same Boolean guard value as an ordinary Bool. */
abstract Flag(Bool) from Bool to Bool {}

/** A nested alternative must retain the enum declaration selected during typing. */
enum Packet {
	Two(left:Int, right:Int);
}

/** A rejected guard continues to a later case, even when its pattern is identical. */
class Main {
	static function choose(value:Int, enabled:Bool):Int {
		return switch value {
			case 1 if (enabled): 7;
			case 1: 9;
			case _: 11;
		};
	}

	static function input(state:Array<Int>):Int {
		state[0] = state[0] + 1;
		return 2;
	}

	static function guard(state:Array<Int>, digit:Int, result:Bool):Bool {
		state[1] = state[1] * 10 + digit;
		return result;
	}

	static function effects():Void {
		var state = [0, 0];
		var result = switch input(state) {
			case 1 if (guard(state, 1, true)): 10;
			case 2 if (guard(state, 2, false)): 20;
			case 2 if (guard(state, 3, true)): 30;
			case 2 if (guard(state, 4, true)): 40;
			case _: 50;
		};
		Sys.println(result);
		Sys.println(state[0]);
		Sys.println(state[1]);
	}

	static function payload(value:Token):Int {
		return switch value {
			case Pair(number, text) if (number > 3 && text.length == 2): number + text.length;
			case Pair(number, _): number;
			case Empty: -1;
		};
	}

	static function bindings():Void {
		Sys.println(payload(Pair(5, "ab")));
		Sys.println(payload(Pair(2, "ab")));
		var items = [2, 3];
		Sys.println(switch items {
			case [head, tail] if (head > tail): 90;
			case [head, tail] if (head < tail): head + tail;
			case _: 99;
		});
		var item = {value: 6};
		Sys.println(switch item {
			case {value: number} if (number > 5): number;
			case _: 99;
		});
	}

	static function exits():Int {
		var sum = 0;
		for (i in 0...5) {
			switch i {
				case 1 if (true):
					continue;
				case 3 if (true):
					break;
				case _:
					sum += i;
			}
		}
		switch sum {
			case 2 if (true):
				return sum;
			case _:
				return 99;
		}
	}

	static function nested():Int {
		return switch 1 {
			case 1 if (switch 2 {
					case 2: true;
					case _: false;
				}): 17;
			case _: 99;
		};
	}

	static function captured():Void {
		var enabled = false;
		var choose = () -> switch 1 {
			case 1 if (enabled): 7;
			case _: 9;
		};
		Sys.println(choose());
		enabled = true;
		Sys.println(choose());
	}

	static function grouped():Void {
		Sys.println(switch 5 {
			case value = (4 | 5 | 6) if (value == 5): value;
			case _: 99;
		});
		Sys.println(switch 1 {
			case 1 if ({
				var local = 2;
				local > 3;
			}): 99;
			case 1: 19;
			case _: 99;
		});
	}

	static function dynamicGuard(flag:Dynamic):Int {
		return switch 1 {
			case 1 if (flag): 31;
			case _: 32;
		};
	}

	static function abstractGuard(flag:Flag):Int {
		return switch 1 {
			case 1 if (flag): 41;
			case _: 42;
		};
	}

	static function returningGuard():Int {
		return switch 1 {
			case 1 if ({
				return 23;
			}): 99;
			case _: 99;
		};
	}

	/** A false guard retries a matching OR alternative with that alternative's bindings. */
	static function alternativeGuards():Void {
		var state = [0, 0];
		var values = [1, 2];
		var result = switch values {
			case [value, 2] | [1, value] if (guard(state, value, value == 2)): value;
			case _: 0;
		};
		Sys.println(result);
		Sys.println(state[1]);
	}

	/** A closure from a failed attempt retains that attempt's value after the next match. */
	static function alternativeCaptures():Void {
		var saved:Array<Void->Int> = [];
		var values = [1, 2];
		var result = switch values {
			case [value, 2] | [1, value] if ({
				saved.push(() -> value);
				value == 2;
			}): value;
			case _: 0;
		};
		Sys.println(result);
		Sys.println(saved[0]());
		Sys.println(saved[1]());
	}

	static function nestedAlternatives():Void {
		var state = [0, 0];
		var packet = {values: [1, 2]};
		var result = switch packet {
			case {values: ([value, 2] | [1, value])} if (guard(state, value, value == 2)): value;
			case _: 0;
		};
		Sys.println(result);
		Sys.println(state[1]);
	}

	static function enumAlternatives():Void {
		var state = [0, 0];
		var packet = Two(1, 2);
		var result = switch packet {
			case Two(value, 2) | Two(1, value) if (guard(state, value, value == 2)): value;
			case _: 0;
		};
		Sys.println(result);
		Sys.println(state[1]);
	}

	/** A failed guard cannot change values that matching already extracted for later alternatives. */
	static function mutatingAlternatives():Void {
		var values = [1, 2];
		var seen = [0];
		var result = switch values {
			case [value, 2] | [1, value] if ({
				seen[0] = seen[0] * 10 + value;
				values[1] = 3;
				value == 3;
			}): value;
			case _: 0;
		};
		Sys.println(result);
		Sys.println(seen[0]);
	}

	/** Locals declared by a guard belong to each attempt, including another loop iteration. */
	static function repeatedGuardLocals():Void {
		var saved:Array<Void->Int> = [];
		for (i in 0...2) {
			var values = [1, 2];
			var result = switch values {
				case [value, 2] | [1, value] if ({
					var local = value + i * 10;
					saved.push(() -> local);
					false;
				}): 99;
				case _: 0;
			};
		}
		Sys.println(saved[0]());
		Sys.println(saved[1]());
		Sys.println(saved[2]());
		Sys.println(saved[3]());
	}

	/** Guard effects can append callbacks; array growth must update the caller and return its new length. */
	static function pushResult():Void {
		var values = [2];
		var effects = 0;
		var size = values.push({
			effects = effects + 1;
			3;
		});
		Sys.println(size);
		Sys.println(values.length);
		Sys.println(values[1]);
		Sys.println(effects);
	}

	static function main():Void {
		Sys.println(choose(1, true));
		Sys.println(choose(1, false));
		Sys.println(choose(2, true));
		effects();
		bindings();
		Sys.println(exits());
		Sys.println(nested());
		captured();
		grouped();
		Sys.println(dynamicGuard(true));
		Sys.println(dynamicGuard(false));
		Sys.println(abstractGuard(true));
		Sys.println(abstractGuard(false));
		Sys.println(returningGuard());
		alternativeGuards();
		alternativeCaptures();
		nestedAlternatives();
		enumAlternatives();
		mutatingAlternatives();
		repeatedGuardLocals();
		pushResult();
	}
}
