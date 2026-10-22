/** Omitted String values use their field names, including lowercase names. */
enum abstract Word(String) to String {
	var First;
	final Second;
	var lower = "small";
	var Explicit = "chosen";
	var Next;
}

/** Omitted Int values follow the preceding value in declaration order. */
enum abstract Number(Int) to Int {
	var Zero;
	final One;
	var Jump = 7;
	var After;
	var Back = -2;
	var Following;
}

/** The constant's abstract identity selects this helper before target emission. */
enum abstract Flavor(String) {
	var Bold = "bold";

	public function label():String {
		return switch this {
			case "bold": "strong";
			case _: "unknown";
		};
	}

	public function unused():String {
		return "must-stay-unused";
	}

	/** Defaults apply after the backing receiver occupies the helper's first slot. */
	public function combine(first:String, ?second:String = "default"):String {
		return this + ":" + first + ":" + second;
	}

	/** A mutually recursive helper pair must retain both declarations in either output layout. */
	public function repeat(count:Int):String {
		if (count <= 0)
			return this;
		var __hxhx_exact_helpers = count;
		var __hxhx_exact_helpers_1 = __hxhx_exact_helpers - 1;
		return next(__hxhx_exact_helpers_1);
	}

	function next(count:Int):String {
		return repeat(count);
	}

	/** A local function keeps precedence over the abstract method with the same name. */
	public function shadow():String {
		var next = function(count:Int):String return "local:" + count;
		return next(2);
	}
}

/** Shared upstream and Neko observer for values and an exact abstract helper. */
class Main {
	static function receiver():Flavor {
		Sys.println("receiver");
		return Flavor.Bold;
	}

	static function argument(value:String):String {
		Sys.println(value);
		return value;
	}

	static function keep(value:String):String {
		return value;
	}

	static function main():Void {
		Sys.println(Word.First);
		Sys.println(Word.Second);
		Sys.println(Word.lower);
		Sys.println(Word.Explicit);
		Sys.println(Word.Next);
		Sys.println(Number.Zero);
		Sys.println(Number.One);
		Sys.println(Number.Jump);
		Sys.println(Number.After);
		Sys.println(Number.Back);
		Sys.println(Number.Following);
		Sys.println(Flavor.Bold.label());
		Sys.println(receiver().combine(argument("first"), argument("second")));
		Sys.println(Flavor.Bold.combine("only"));
		Sys.println(Flavor.Bold.combine("null", null));
		var recovered = try {
			throw "caught";
		} catch (error:String) {
			error;
		};
		Sys.println(recovered);
		var kept = try {
			untyped keep("kept");
		} catch (error:String) {
			"unexpected";
		};
		Sys.println(kept);
		Sys.println(Flavor.Bold.repeat(3));
		Sys.println(Flavor.Bold.shadow());
	}
}
