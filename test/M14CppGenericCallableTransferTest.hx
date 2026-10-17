/** Execute callback identity, scalar entry, and null-preserving aliases through normal C++ generation. */
class M14CppGenericCallableTransferTest {
	static function main():Void {
		M14CppManagedStartupExecutionTest.runFixture({
			sourceRoot: "test/fixtures/cpp_generic_callable_transfer_seed",
			output: ".tmp/cpp-generic-callable-transfer",
			observer: "test/cpp_managed_heap/GenericCallableObserver.cpp"
		});
		Sys.println("CPP_GENERIC_CALLABLE_TRANSFER:PASS");
	}
}
