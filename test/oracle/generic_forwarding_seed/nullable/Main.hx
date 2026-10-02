/** Nullable wrappers preserve the caller's object guarantee. */
class Main {
	static function requireObject<T:{}>(value:T):T {
		return value;
	}

	static function forward<U:{}>(value:Null<U>):Null<U> {
		return requireObject(value);
	}

	static function main():Void {
		Sys.println(forward("nullable"));
	}
}
