/** Observe authored throw operands after generated scopes unwind and the native heap collects. */
class M14CppManagedThrowTest {
	static function main():Void {
		M14SourceMapComprehensionManagedTest.runFixture({
			sourceRoot: "test/oracle/managed_throw_seed",
			module: "Thrown",
			observer: "test/cpp_managed_heap/ThrowObserver.cpp",
			output: ".tmp/cpp-managed-throw",
			marker: "CPP_MANAGED_THROW_NATIVE:PASS"
		});
		Sys.println("CPP_MANAGED_THROW:PASS");
	}
}
