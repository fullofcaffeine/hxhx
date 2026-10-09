/** Reuses production loading and both native layouts to check object conversion without a catch. */
class M14NekoObjectStringConversionIntegrationTest {
	static function main():Void {
		NekoRuntimeFixture.exercise("test/neko_object_string_conversion", false);
	}
}
