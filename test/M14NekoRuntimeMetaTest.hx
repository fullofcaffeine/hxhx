/** Compare meta categories and enum descriptors through real upstream and native Neko startup. */
class M14NekoRuntimeMetaTest {
	static function main():Void {
		NekoRuntimeFixture.exercise("test/neko_runtime_meta", false, true);
	}
}
