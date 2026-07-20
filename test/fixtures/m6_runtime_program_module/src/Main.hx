/** Exercises a generated `Hx*` module reference during runtime planning. **/
class Main {
	static function main():Void {
		if (HxProgramOwned.read() != 42)
			throw "generated program module call returned the wrong value";
	}
}
