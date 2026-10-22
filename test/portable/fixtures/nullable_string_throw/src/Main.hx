/** Observes null, text, catch order, and evaluation count across nullable throws. */
class Main {
	static var evaluations:Int = 0;

	static function value(text:Null<String>):Null<String> {
		evaluations++;
		return text;
	}

	static function throwValue(text:Null<String>):Void {
		throw value(text);
	}

	static function direct(text:Null<String>):Void {
		throw text;
	}

	static function relay(text:Null<String>):Void {
		try {
			throwValue(text);
		} catch (caught:String) {
			final nullable:Null<String> = caught;
			throw nullable;
		}
	}

	static function observe(text:Null<String>):Void {
		try {
			relay(text);
		} catch (caught:String) {
			Sys.println("string:" + caught);
		} catch (caught:Dynamic) {
			Sys.println(caught == null ? "dynamic:null" : "unexpected");
		}
	}

	static function dynamicFirst(text:Null<String>):Void {
		try {
			direct(value(text));
		} catch (caught:Dynamic) {
			Sys.println(caught == null ? "first:null" : "first:" + Std.string(caught));
		}
	}

	static function checked(text:Null<String>):Void {
		final error = value(text);
		if (error != null)
			throw error;
	}

	static function main():Void {
		observe(null);
		observe("message");
		observe("");
		dynamicFirst(null);
		dynamicFirst("text");
		checked(null);
		try {
			checked("bad");
		} catch (caught:String) {
			Sys.println("checked:" + caught);
		}
		Sys.println("evaluations:" + evaluations);
	}
}
