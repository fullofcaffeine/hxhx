/** Compare typed rest packing and reflection with the upstream Neko runtime. */
class M14NekoRestArgumentsTest {
	static function main():Void {
		NekoRuntimeFixture.exercise("test/fixtures/neko_rest_arguments", true);
	}
}
