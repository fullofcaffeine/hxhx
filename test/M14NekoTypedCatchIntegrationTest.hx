/** Compares typed exception handling with upstream in both Neko layouts. */
class M14NekoTypedCatchIntegrationTest {
	static function main():Void {
		final fixtures = [
			"test/neko_typed_catch",
			"test/neko_exception_provider",
			"test/neko_catch_value_views",
			"test/neko_numeric_catches"
		];
		final requested = Sys.args();
		for (fixture in requested)
			if (fixtures.indexOf(fixture) < 0)
				throw "unknown catch fixture: " + fixture;
		for (fixture in (requested.length == 0 ? fixtures : requested))
			NekoRuntimeFixture.exercise(fixture, true);
	}
}
