/** The real standard providers must see the generated name tree before their startup routines run. */
class M14NekoBootRegistryTest {
	static function main():Void {
		NekoRuntimeFixture.exercise("test/neko_boot_registry", false);
	}
}
