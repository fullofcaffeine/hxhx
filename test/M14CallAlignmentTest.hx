import TyCallAlignment.TyCallOperandKind;
import TyCallAlignment.TyCallAlignmentResult;

/** Test the pinned operand mapping separately from type inference and target rendering. */
class M14CallAlignmentTest {
	static function describe(result:TyCallAlignmentResult):String {
		return switch (result) {
			case Aligned(slots): [
					for (slot in slots)
						switch (slot) {
							case Omitted:
								"omit";
							case Supplied(index):
								Std.string(index);
							case RestElements(indices):
								"rest:" + indices.join(",");
							case RestSpread(index):
								"spread:" + index;
						}
				].join("|");
			case Rejected(failure): Std.string(failure);
		};
	}

	/** Compatibility is a small independent fixture table, not a second compiler type checker. */
	static function check(signature:String, actual:Array<String>, expected:String, ?spread:Array<Int>):Void {
		final parameters = TyType.fromHintText(signature).getFunctionParameters();
		final operands:Array<TyCallOperandKind> = [
			for (index in 0...actual.length)
				spread != null && spread.indexOf(index) >= 0 ? Spread : Value
		];
		final result = TyCallAlignment.align(parameters, operands, (source, parameter, isSpread) -> {
			if (actual[source] == "unknown")
				return Unknown;
			final wanted = parameters[parameter].type.getCanonicalDisplay();
			return actual[source] == (isSpread ? "Array<" + wanted + ">" : wanted)
				|| (!isSpread && actual[source] == "null") ? Compatible : Incompatible;
		});
		final observed = describe(result);
		if (observed != expected)
			throw signature + " with " + actual.join(",") + ": expected " + expected + ", got " + observed;
	}

	static function main():Void {
		check("()->Int", [], "");
		check("()->Int", ["Int"], "TooManyArguments(0)");
		check("(value:Int,?text:String)->Int", [], "MissingRequired(0)");
		check("(value:Int,?text:String)->Int", ["Int"], "0|omit");
		check("(value:Int,?text:String)->Int", ["String"], "IncompatibleArgument(0,0)");
		check("(value:Int,?text:String)->Int", ["Int", "String", "Bool"], "TooManyArguments(2)");
		check("(?first:Int,value:Int)->Int", ["Int"], "MissingRequired(1)");
		check("(?text:String,value:Int)->Int", ["Int"], "omit|0");
		check("(?text:String,value:Int)->Int", ["null", "Int"], "0|1");
		check("(?text:String,value:Int)->Int", ["unknown"], "UnprovedArgument(0,0)");
		final optional = "(?text:String,?flag:Bool,value:Int)->Int";
		check(optional, ["Int"], "omit|omit|0");
		check(optional, ["Int", "Int"], "IncompatibleArgument(0,0)");
		check(optional, ["Bool", "Int"], "omit|0|1");
		final rest = "(?text:String,?flag:Bool,value:Int,...tail:Int)->Int";
		check(rest, ["Int"], "omit|omit|0|rest:");
		check(rest, ["Int", "Int"], "omit|omit|0|rest:1");
		check(rest, ["Int", "Int", "Int"], "IncompatibleArgument(0,0)");
		check(rest, ["Bool", "Int", "Int"], "omit|0|1|rest:2");
		check(rest, ["Bool", "Int", "Int", "Int"], "IncompatibleArgument(0,0)");
		check(rest, ["null", "Bool", "Int", "Int"], "0|1|2|rest:3");
		final suffix = "(?text:String,value:Int,flag:Bool)->Int";
		check(suffix, ["Int", "Int"], "IncompatibleArgument(0,0)");
		check(suffix, ["Int", "Bool"], "omit|0|1");
		check(suffix, ["null", "Int", "Int"], "IncompatibleArgument(2,2)");
		check(suffix, ["Int"], "MissingRequired(2)");
		check("(value:Int,...tail:Int)->Int", ["Int", "Int", "String"], "IncompatibleArgument(2,1)");
		check("(value:Int,...tail:Int)->Int", ["Int", "Array<Int>"], "0|spread:1", [1]);
		check("(...tail:Int)->Int", ["Int"], "IncompatibleArgument(0,0)", [0]);
		check("(...tail:Int)->Int", ["Int", "Array<Int>"], "MixedRestSpread(1)", [1]);
		check("(...tail:Int)->Int", ["Array<Int>", "Int"], "MixedRestSpread(0)", [0]);
		check("(value:Int)->Int", ["Array<Int>"], "UnexpectedSpread(0,0)", [0]);
		check("(...tail:Int,value:Int)->Int", [], "UnsupportedRestPosition(0)");
		Sys.println("CALL_ALIGNMENT:PASS");
	}
}
