/** Native aggregate behavior observed independently with Haxe 4.3.7 and hxcpp 4.3.2. */
class AggregateContract {
	static var calls:Int = 0;

	static function expect(actual:String, expected:String):Void {
		if (actual != expected)
			throw "aggregate conversion differs: " + actual + " expected " + expected;
	}

	static function main():Void {
		expect(Std.string({}), "{ }");
		expect(Std.string({
			aa: 1,
			z: 2,
			bb: 3,
			a: 4,
			inner: 5,
			list: 6
		}), "{ inner => 5, a => 4, z => 2, aa => 1, bb => 3, list => 6 }");
		expect(Std.string({
			list: 6,
			inner: 5,
			a: 4,
			bb: 3,
			z: 2,
			aa: 1
		}), "{ inner => 5, a => 4, z => 2, aa => 1, bb => 3, list => 6 }");
		expect(Std.string({
			text: 1,
			z: "two",
			n: false,
			a: "four"
		}), "{ a => four, n => false, z => two, text => 1 }");
		expect(Std.string({inner: {x: 1}, list: ["a", null, "b"]}), "{ inner => { x => 1 }, list => [a,null,b] }");
		expect(Std.string({
			toString: () -> {
				calls++;
				return "custom";
			},
			other: 4
		}), "custom");
		final nullResult = Std.string({
			toString: () -> {
				calls++;
				return (null : String);
			}
		});
		if (nullResult != null)
			throw "native record conversion must preserve a null String";
		var caught = false;
		try {
			Std.string({
				toString: () -> {
					calls++;
					throw "conversion";
					return "";
				}
			});
		} catch (message:String) {
			caught = message == "conversion";
		}
		if (!caught)
			throw "record conversion lost the thrown source value";
		expect(Std.string({toString: (null : Void->String), other: 4}), "{ other => 4, toString => null }");
		expect(Std.string({callback: () -> "unused"}), "{ callback => Object }");
		final record = {a: {toString: () -> "initial"}, z: "before"};
		record.a = {
			toString: () -> {
				calls++;
				record.z = "after";
				return "first";
			}
		};
		expect(Std.string(record), "{ a => first, z => after }");
		final array = [{toString: () -> "first"}, {toString: () -> "second"}];
		array[0] = {
			toString: () -> {
				calls++;
				array[1] = {toString: () -> "changed"};
				return "first";
			}
		};
		expect(Std.string(array), "[first,changed]");
		expect(Std.string([{toString: () -> (null : String)}]), "[null]");
		if (calls != 5)
			throw "aggregate conversion repeated or skipped a callback";
	}
}
