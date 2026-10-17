/** Saved methods and aliases must observe the same Array object after a source variable changes. */
class M14NekoArrayMethodValueTest {
	static function main():Void {
		NekoRuntimeFixture.exercise("test/fixtures/native_array_method_value", false);
	}
}
