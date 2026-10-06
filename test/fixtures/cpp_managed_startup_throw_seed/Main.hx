/** The native observer must receive the startup exception before main can execute. */
class Main {
	static function main():Void {
		throw "main ran";
	}
}

/** Loaded classes run startup even when ordinary source does not call their methods. */
class Unused {
	static function __init__():Void {
		throw "startup";
	}
}
