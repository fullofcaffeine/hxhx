/** Compare the real standard-library backing-array operations in both Neko artifact layouts. */
class M14NekoNativeArrayPrimitivesTest {
	static function main():Void {
		NekoRuntimeFixture.exercise("test/fixtures/neko_native_array_primitives", false);
	}
}
