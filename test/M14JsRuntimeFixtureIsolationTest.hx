/** Adjacent allocations must own separate directories and preserve each other's files. */
class M14JsRuntimeFixtureIsolationTest {
	static function main():Void {
		final first = JsRuntimeFixture.reserveOutput();
		final second = JsRuntimeFixture.reserveOutput();
		if (first == second)
			throw "JavaScript fixture allocations share a directory";
		sys.io.File.saveContent(second + "/owner.txt", "second fixture");
		sys.FileSystem.deleteDirectory(first);
		if (sys.io.File.getContent(second + "/owner.txt") != "second fixture")
			throw "removing one allocation changed its neighbor";
		sys.FileSystem.deleteFile(second + "/owner.txt");
		sys.FileSystem.deleteDirectory(second);
		Sys.println("JS_RUNTIME_FIXTURE_ISOLATION:PASS");
	}
}
