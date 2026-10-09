/** Upstream behavior expectations independent of native storage and lowering. */
class MapExecutionOracle {
	static function main():Void {
		final plain = MapExecution.plain();
		if (plain.get(1) != 2 || plain.get(2) != 3)
			throw "plain map";
		final duplicate = MapExecution.duplicates();
		if (duplicate.get(1) != 3 || duplicate.get(0) != 2)
			throw "replacement";
		final guarded = MapExecution.guarded();
		if (guarded.exists(13) || guarded.exists(23) || guarded.get(14) != 4 || guarded.get(24) != 4)
			throw "guard";
		final effects = MapExecution.effects();
		if (effects.get(1) != 19 || effects.get(192) != 1929)
			throw "key/value order";
		final captured = MapExecution.captures();
		if (captured.get(1)() != 1 || captured.get(2)() != 2)
			throw "capture identity";
		final strings = MapExecution.strings();
		if (strings.get("a") != 2 || strings.get("b") != 1)
			throw "string keys";
		Sys.println("SOURCE_MAP_COMPREHENSION_NATIVE:PASS");
	}
}
