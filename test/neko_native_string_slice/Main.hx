/**
	Exercises the native Neko string boundary through authored Haxe.
	The untyped calls are Neko compiler primitives, whose raw values have no
	portable Haxe type. String construction and nullable integer reads contain
	those values before ordinary Haxe code observes them.
**/
class Main {
	static function main():Void {
		var native = untyped __dollar__string(12345);
		var slice = untyped __dollar__ssub(native, 1, 3);
		Sys.println(new String(slice));
		var failed = try {
			untyped __dollar__ssub(native, 6, 1);
			false;
		} catch (error:Dynamic) {
			true;
		};
		Sys.println(failed);
		var validFailed = try {
			untyped __dollar__ssub(native, 1, 3);
			false;
		} catch (error:Dynamic) {
			true;
		};
		Sys.println(validFailed);
		var empty = untyped __dollar__ssub(native, 5, 0);
		Sys.println("empty:" + new String(empty));
		final first:Null<Int> = untyped __dollar__sget(native, 0);
		final last:Null<Int> = untyped __dollar__sget(native, 4);
		final end:Null<Int> = untyped __dollar__sget(native, 5);
		Sys.println(first);
		Sys.println(last);
		Sys.println(end == null);
		final code:Null<Int> = untyped __dollar__sget(nextString().__s, nextIndex());
		Sys.println(code);
		final object = {__s: "ordinary"};
		Sys.println(object.__s);
	}

	/** The source observer precedes the index observer and must run once. */
	static function nextString():String {
		Sys.println("string");
		return "AZ";
	}

	/** The index observer must run exactly once before the byte read. */
	static function nextIndex():Int {
		Sys.println("index");
		return 1;
	}
}
