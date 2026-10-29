/** Run full-function defaults through native C++ and the existing optimized sanitizer observer. */
class M14SourceFunctionDefaultNativeTest {
	static function main():Void {
		if (Sys.command("haxe", ["-cp", "test/oracle/source_arrow_return_seed", "--run", "FullFunctionDefaults"]) != 0)
			throw "upstream full-function default contract failed";
		M14SourceArrowParameterEntryTest.run("FullFunctionDefaults");
	}
}
