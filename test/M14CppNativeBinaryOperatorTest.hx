/** Execute selected native and body-bearing operators with independent effect and storage observations. */
class M14CppNativeBinaryOperatorTest {
	static function main():Void {
		M14CppManagedStartupExecutionTest.runFixture({
			sourceRoot: "test/fixtures/cpp_native_binary_operator_seed",
			output: ".tmp/cpp-native-binary-operator",
			observer: "test/cpp_managed_heap/NativeBinaryOperatorObserver.cpp"
		});
		Sys.println("CPP_NATIVE_BINARY_OPERATOR:PASS");
	}
}
