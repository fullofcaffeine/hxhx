/** Compare public array ownership and system calls with the upstream Neko runtime. */
class M14NekoArrayBoundaryTest {
	static function main():Void {
		NekoRuntimeFixture.exercise("test/fixtures/neko_array_boundaries", false, true, null, null, ["original"]);
	}
}
