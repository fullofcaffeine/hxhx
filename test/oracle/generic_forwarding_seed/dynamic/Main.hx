/** A declared Dynamic bound keeps its existing permissive input rule without erasing U. */
class Main {
	static function requireObject<T:Dynamic>(value:T):T {
		return value;
	}

	static function forward<U>(value:U):U {
		return requireObject(value);
	}

	static function main():Void {
		Sys.println(forward("dynamic"));
	}
}
