/** Checks generic null tests without confusing null, zero, false, or empty values. */
class Main {
	static function main():Void {
		var absentInt:Null<Int> = null;
		var presentInt:Null<Int> = 0;
		var absentBool:Null<Bool> = null;
		var presentBool:Null<Bool> = false;
		var absentBox:Box = null;
		var absentFunction:Void->Int = null;
		var presentFunction:Void->Int = function():Int return 7;
		Probe.observe(absentInt);
		Probe.observe(presentInt);
		Probe.observe(absentBool);
		Probe.observe(presentBool);
		Probe.observe(absentBox);
		Probe.observe(new Box());
		Probe.observe(false);
		Probe.observe("");
		Probe.observe(absentFunction);
		Probe.observe(presentFunction);
		Sys.println(Probe.calls);
	}
}

/** A reference carrier supplies an independently nullable generic instantiation. */
class Box {
	public function new() {}
}

/** Count operand evaluation separately from each comparison's boolean result. */
class Probe {
	public static var calls:Int = 0;

	static function take<T>(value:T):T {
		calls++;
		return value;
	}

	public static function observe<T>(value:T):Void {
		var before = calls;
		var leftEqual = take(value) == null;
		var rightEqual = null == take(value);
		var leftDifferent = take(value) != null;
		var rightDifferent = null != take(value);
		var branchNull = false;
		if (take(value) == null)
			branchNull = true;
		if (branchNull != leftEqual)
			throw "branch folding disagreed with the generic null value";
		if (calls != before + 5)
			throw "null comparison changed operand evaluation count";
		Sys.println((leftEqual ? "1" : "0") + (rightEqual ? "1" : "0") + (leftDifferent ? "1" : "0") + (rightDifferent ? "1" : "0"));
	}
}
