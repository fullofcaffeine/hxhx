/**
	An omitted parameter with a `null` default takes its type from later uses, as in Haxe 4.3.7.
	The `null` default only makes the input optional and nullable. The operations live in their
	own class, declared before `Main`, so that calls from `main` cannot supply the evidence.
**/
class Ops {
	public static function assigned(?value = null) {
		value = 5;
		return value;
	}

	public static function implicitOptional(value = null) {
		value = 5;
		return value;
	}

	public static function fallback(?value = null) {
		if (value == null)
			value = "x";
		return value;
	}

	public static function scaled(label:String, ?factor = null) {
		if (factor == null)
			factor = 1.5;
		return label + factor * 2;
	}

	// The shape of `haxe.macro.Printer.printExprWithPositions`: a local function whose omitted
	// input with a `null` default takes a value from the enclosing scope.
	public static function local(base:Int) {
		function add(label:String, ?count = null) {
			if (count == null)
				count = base;
			return label + count;
		}
		return add("y");
	}
}

class Main {
	static function main() {
		Sys.println(Ops.assigned());
		Sys.println(Ops.implicitOptional());
		Sys.println(Ops.fallback());
		Sys.println(Ops.scaled("s"));
		Sys.println(Ops.local(3));
	}
}
