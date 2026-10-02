/** Reusing the callee's parameter spelling supplies no bound evidence. */
class Main {
	static function requireObject<T:{}>(value:T):T {
		return value;
	}

	static function forward<T>(value:T):T {
		return requireObject(value);
	}

	static function main():Void {}
}
