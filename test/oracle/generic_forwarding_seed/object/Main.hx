/** Forwarding retains the caller's declared object bound under a different binder name. */
class Main {
	static function requireObject<T:{}>(value:T):T {
		return value;
	}

	static function forward<U:{}>(value:U):U {
		return requireObject(value);
	}

	static function main():Void {
		final value = forward("forwarded");
		Sys.println(value);
	}
}
