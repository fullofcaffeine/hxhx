import pk.Mode;

/**
	A bare value of an enum abstract from another module resolves through the expected type, as in
	Haxe 4.3.7: `Speeds.speed(fast ? Fast : Slow)` with `speed(mode:Mode)`. eval's `sys.ssl.Socket` calls
	`conf.defaults(SSL_IS_CLIENT, ...)` this way. The operations live in their own class, declared
	before `Main`, so that calls from `main` cannot supply the evidence.
**/
class Speeds {
	public static function speed(mode:Mode):Int
		return mode;
}

/** The observed operations take simple inputs; `Speeds` holds the enum-typed parameter. **/
class Ops {
	public static function pick(fast:Bool)
		return Speeds.speed(fast ? Fast : Slow);

	public static function direct(flag:Bool)
		return flag ? Speeds.speed(Fast) : Speeds.speed(Slow);
}

class Main {
	static function main() {
		Sys.println(Ops.pick(true));
		Sys.println(Ops.pick(false));
		Sys.println(Ops.direct(false));
	}
}
