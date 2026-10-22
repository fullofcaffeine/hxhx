/** Real POSIX child processes observe the native argument conversion and handle cleanup. */
class M14NekoProcessArrayArgumentsTest {
	static function main():Void {
		NekoRuntimeFixture.exercise("test/fixtures/neko_process_array_arguments", true);
	}
}
