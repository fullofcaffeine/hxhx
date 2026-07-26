class Main {
	static var effects = 0;

	static function log(value:String):Void {
		#if js
		js.Syntax.code("console.log({0})", value);
		#else
		Sys.println(value);
		#end
	}

	static function observed(label:String, value:Bool):Bool {
		effects++;
		log("effect:" + label + ":" + value);
		return value;
	}

	static function classify(value:Null<Bool>):String {
		return switch (value) {
			case null: "null";
			case false: "false";
			case true: "true";
		};
	}

	static function main() {
		var value:Null<Bool> = null;
		log("initial=" + Std.string(value));
		log("initial-condition=" + (value ? "true" : "false"));

		value = false;
		log("false-value=" + Std.string(value));
		log("false-condition=" + (value ? "true" : "false"));

		value = true;
		log("true-value=" + Std.string(value));
		log("true-condition=" + (value ? "true" : "false"));

		var copy:Null<Bool> = value;
		value = null;
		log("copy=" + Std.string(copy));
		log("value-reset=" + Std.string(value));

		{
			var nested:Null<Bool> = value;
			log("nested=" + Std.string(nested));
			nested = false;
			log("nested-replaced=" + Std.string(nested));
		}

		var mutable:Null<Bool> = null;
		if (effects == 0)
			mutable = true;
		log("mutable=" + Std.string(mutable));

		var plannedMutable:Null<Bool> = null;
		if (effects == 0)
			plannedMutable = true;
		log("planned-mutable-condition=" + (plannedMutable ? "true" : "false"));

		var plannedCaptured:Null<Bool> = true;
		var plannedCapturedResult = "";
		var exercisePlannedCaptured:Void->Void = () -> {
			plannedCapturedResult = plannedCaptured ? "true" : "false";
			plannedCaptured = false;
			plannedCapturedResult += "," + (plannedCaptured ? "true" : "false");
		};
		exercisePlannedCaptured();
		log("planned-captured-conditions=" + plannedCapturedResult);

		var captured:Null<Bool> = true;
		var readCaptured = () -> captured;
		var capturedCondition = () -> captured ? "true" : "false";
		var writeCaptured = (next:Null<Bool>) -> captured = next;
		log("captured-first=" + Std.string(readCaptured()));
		log("captured-condition=" + capturedCondition());
		writeCaptured(null);
		log("captured-null=" + Std.string(readCaptured()));
		var alias:Null<Bool> = captured;
		writeCaptured(false);
		log("captured-replaced=" + Std.string(readCaptured()));
		log("alias-stays-null=" + (alias == null));

		var nullableTrue:Null<Bool> = true;
		var coalesced:Bool = nullableTrue ?? false;
		log("coalesced=" + coalesced);

		var switchValue:Null<Bool> = null;
		log("switch-null=" + classify(switchValue));
		switchValue = false;
		log("switch-false=" + classify(switchValue));
		switchValue = true;
		log("switch-true=" + classify(switchValue));

		var nullFlag:Null<Bool> = null;
		log("null-not=" + !nullFlag);
		log("null-and=" + (nullFlag && observed("and-null", true)));
		log("null-or=" + (nullFlag || observed("or-null", true)));

		var trueFlag:Null<Bool> = true;
		log("true-and=" + (trueFlag && observed("and-true", true)));
		var falseFlag:Null<Bool> = false;
		log("false-or=" + (falseFlag || observed("or-false", true)));

		var loop:Null<Bool> = true;
		var loopCount = 0;
		while (loop) {
			loopCount++;
			loop = false;
		}
		log("loop-count=" + loopCount);

		var ordered:Null<Bool> = observed("ordered", true);
		log("ordered-condition=" + (ordered ? "true" : "false"));
		log("effects=" + effects);
		log("OK null_bool_local_truthiness");
	}
}
