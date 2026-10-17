/** Execute the selected annotation conversions with forced collection and native sanitizers. */
class M14CppTypeAnnotationTest {
	static function main():Void {
		M14CppManagedStartupExecutionTest.runFixture({
			sourceRoot: "test/fixtures/cpp_type_annotation_seed",
			output: ".tmp/cpp-type-annotation",
			observer: "test/cpp_managed_heap/TypeAnnotationObserver.cpp"
		});
		Sys.println("CPP_TYPE_ANNOTATION:PASS");
	}
}
