/**
	Exercises the native Neko string boundary through authored Haxe.
	The untyped calls are Neko compiler primitives, whose raw values have no
	portable Haxe type. Only String construction exposes the result to Haxe code.
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
	}
}
