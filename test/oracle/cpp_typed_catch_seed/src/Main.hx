/** Exercise Haxe throw/catch behavior without deriving expectations from the candidate runtime. */
class Main {
	/** Dynamic is the deliberate boundary for arbitrary thrown Haxe values; handlers narrow it immediately. */
	static function category(value:Dynamic):String {
		try {
			throw value;
		} catch (value:Bool) {
			return "bool";
		} catch (value:Int) {
			return "int";
		} catch (value:Float) {
			return "float";
		} catch (value:String) {
			return "string";
		} catch (value:ChildValue) {
			return "child";
		} catch (value:BaseValue) {
			return "base";
		} catch (value:Dynamic) {
			return "dynamic";
		}
	}

	static function main():Void {
		Sys.println("bool=" + category(true));
		Sys.println("int=" + category(7));
		Sys.println("integral-float=" + category(7.0));
		Sys.println("fraction=" + category(7.5));
		Sys.println("wide-float=" + category(2147483648.0));
		Sys.println("nan=" + category(Math.NaN));
		Sys.println("infinity=" + category(Math.POSITIVE_INFINITY));
		Sys.println("negative-zero=" + category(-0.0));
		Sys.println("text=" + category("problem"));
		Sys.println("null=" + category(null));
		final child = new ChildValue(17);
		Sys.println("object=" + category(child));
		Sys.println("base=" + category(new BaseValue(9)));
		try {
			throw child;
		} catch (value:ReadableValue) {
			Sys.println("interface-value=" + value.read());
			Sys.println("interface-identity=" + (value == child));
		}
		try {
			try {
				throw child;
			} catch (base:BaseValue) {
				Sys.println("subtype-identity=" + (base == child));
				base.value++;
				throw base;
			}
		} catch (again:ChildValue) {
			Sys.println("rethrow-identity=" + (again == child));
			Sys.println("shared-mutation=" + again.value);
		}
		try {
			try {
				throw "unmatched";
			} catch (number:Int) {
				Sys.println("wrong-handler");
			}
		} catch (text:String) {
			Sys.println("propagated=" + text);
		}
		try {
			try {
				throw 7;
			} catch (number:Int) {
				throw "from-handler";
			} catch (text:String) {
				Sys.println("wrong-sibling-handler");
			}
		} catch (text:String) {
			Sys.println("handler-propagated=" + text);
		}
		final captured:Array<Void->Int> = [];
		for (index in 0...3) {
			try {
				throw index;
			} catch (number:Int) {
				captured.push(function():Int {
					return number++;
				});
			}
		}
		Sys.println("captured-first=" + [for (read in captured) read()].join(","));
		Sys.println("captured-second=" + [for (read in captured) read()].join(","));
		var continued = "";
		for (index in 0...4) {
			try {
				if (index == 1)
					throw "skip";
				continued += index;
			} catch (text:String) {
				continue;
			}
		}
		Sys.println("continued=" + continued);
		var stopped = "";
		for (index in 0...4) {
			try {
				if (index == 1)
					throw "stop";
				stopped += index;
			} catch (text:String) {
				break;
			}
		}
		Sys.println("stopped=" + stopped);
		try {
			throw child;
		} catch (error) {
			Sys.println("default-wrapper=" + Std.isOfType(error, haxe.ValueException));
			final wrapper = Std.downcast(error, haxe.ValueException);
			Sys.println("default-payload=" + (wrapper != null && wrapper.value == child));
		}
		final exception = new haxe.Exception("message");
		try {
			throw exception;
		} catch (error:haxe.Exception) {
			Sys.println("exception-identity=" + (error == exception));
			Sys.println("exception-message=" + error.message);
		}
	}
}

/** Ordinary object identity must survive thrown-value wrapping and subtype catch selection. */
class BaseValue {
	public var value:Int;

	public function new(value:Int)
		this.value = value;
}

/** A subtype rethrow must retain its original object even through a base-typed catch local. */
class ChildValue extends BaseValue implements ReadableValue {
	public function new(value:Int)
		super(value);

	public function read():Int
		return value;
}

/** Interface matching must preserve the concrete thrown object and its callable methods. */
interface ReadableValue {
	function read():Int;
}
