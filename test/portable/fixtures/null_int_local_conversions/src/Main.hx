class Main {
	static var effects = 0;

	static function log(value:String):Void {
		#if js
		js.Syntax.code("console.log({0})", value);
		#else
		Sys.println(value);
		#end
	}

	static function observed(label:String, value:Int):Int {
		effects++;
		log("effect:" + label + ":" + value);
		return value;
	}

	static function plusOne(value:Null<Int>):Int {
		return value == null ? -1 : value + 1;
	}

	static function classify(value:Null<Int>):String {
		return switch (value) {
			case null: "null";
			case 3: "3";
			case _: "other";
		};
	}

	static function main() {
		var value:Null<Int> = null;
		log("initial=" + Std.string(value));

		value = 4;
		log("assigned=" + plusOne(value));

		var copy:Null<Int> = value;
		value = null;
		log("copy=" + Std.string(copy));

		{
			var nested:Null<Int> = value;
			log("nested=" + Std.string(nested));
			nested = observed("replacement", 6);
			log("nested-replaced=" + plusOne(nested));
		}

		var mutable:Null<Int> = null;
		if (effects == 1) {
			mutable = 2;
		}
		log("mutable=" + plusOne(mutable));

		var captured:Null<Int> = 1;
		var readCaptured = () -> plusOne(captured);
		var writeCaptured = (next:Null<Int>) -> captured = next;
		log("captured-first=" + readCaptured());
		writeCaptured(null);
		log("captured-null=" + readCaptured());
		var alias:Null<Int> = captured;
		writeCaptured(8);
		log("captured-replaced=" + readCaptured());
		log("alias-stays-null=" + (alias == null));

		var nullableTwelve:Null<Int> = 12;
		var coalesced:Int = nullableTwelve ?? 0;
		log("coalesced=" + coalesced);

		var refined:Null<Int> = 7;
		if (refined != null)
			log("refined=" + (refined + 1));

		var compoundTotal = 1;
		var compoundValue:Null<Int> = 2;
		if (compoundValue != null)
			compoundTotal += compoundValue;
		log("compound=" + compoundTotal);

		var switchValue:Null<Int> = null;
		log("switch-null=" + classify(switchValue));
		switchValue = 3;
		log("switch-value=" + classify(switchValue));

		var ordered:Null<Int> = observed("order", 10);
		log("ordered=" + plusOne(ordered));
		log("effects=" + effects);
		log("OK null_int_local_conversions");
	}
}
