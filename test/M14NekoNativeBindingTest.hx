/** Compare native binding startup with upstream while retaining real target standard-library providers. */
class M14NekoNativeBindingTest {
	static function main():Void {
		NekoRuntimeFixture.exercise("test/neko_native_bindings", false);
	}
}
