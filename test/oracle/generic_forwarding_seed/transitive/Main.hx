/** Related caller parameters retain both object and parameter-to-parameter guarantees. */
class Main {
	static function requireObject<T:{}, S:T>(value:S, base:T):S {
		return value;
	}

	static function forward<A:{}, B:A>(value:B, base:A):B {
		return requireObject(value, base);
	}

	static function main():Void {
		Sys.println(forward("transitive", "base"));
	}
}
