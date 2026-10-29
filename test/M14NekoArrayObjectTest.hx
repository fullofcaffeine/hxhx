/** Compare Array objects and native storage boundaries with the real Neko provider. */
class M14NekoArrayObjectTest {
	static function main():Void {
		NekoRuntimeFixture.exercise("test/fixtures/neko_array_objects", false);
	}
}
