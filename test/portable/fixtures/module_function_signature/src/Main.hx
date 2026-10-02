/** Exercises retained static and constructor signatures without a module cycle. */
class Main {
	static function main() {
		if (new ConstructorProbe(7).seed != 7)
			throw "constructor result changed";
		if (new UnrepresentedConstructorProbe(5, 2).seed != 7)
			throw "unrepresented constructor behavior changed";
		Sys.println(CycleLeft.value(3));
	}
}
