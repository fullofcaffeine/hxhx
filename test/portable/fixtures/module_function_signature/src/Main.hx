/** Exercises retained static and constructor signatures without a module cycle. */
class Main {
	static function main() {
		if (new ConstructorProbe(5, 2).seed != 7)
			throw "constructor result changed";
		if (new ArrayConstructorProbe(5, [2]).seed != 7)
			throw "array constructor behavior changed";
		if (new UnrepresentedConstructorProbe(5, value -> value + 2).seed != 7)
			throw "unrepresented constructor behavior changed";
		final words = new Int32ConstructorProbe(5, 2);
		if (words.high != 5 || words.low != 2 || Int32ConstructorProbe.retain(words.low) != 2)
			throw "Int32 constructor or retained alias changed";
		Sys.println(CycleLeft.value(3));
	}
}
