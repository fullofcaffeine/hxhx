/** Execute declaration-authorized abstract storage views through native code and sanitizers. */
class M14CppNativeAbstractOperatorTest {
	static function main():Void {
		M14CppManagedStartupExecutionTest.runFixture({
			sourceRoot: "test/fixtures/cpp_native_abstract_operator_seed",
			output: ".tmp/cpp-native-abstract-operator",
			observer: "test/cpp_managed_heap/NativeAbstractOperatorObserver.cpp"
		});
		Sys.println("CPP_NATIVE_ABSTRACT_OPERATOR:PASS");
	}
}
