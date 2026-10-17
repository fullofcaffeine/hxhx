/** Quoted expressions and types expose real public arrays while enum payload storage stays internal. */
class M14NekoMacroArrayFieldsTest {
	static function main():Void {
		NekoRuntimeFixture.exercise("test/fixtures/neko_macro_array_fields", true);
	}
}
