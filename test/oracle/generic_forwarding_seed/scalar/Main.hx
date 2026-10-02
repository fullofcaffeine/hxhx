/** A known scalar bound must not become an object bound through forwarding. */
class Main {
	static function requireObject<T:{}>(value:T):T {
		return value;
	}

	static function forward<U:Int>(value:U):U {
		return requireObject(value);
	}

	static function main():Void {}
}
