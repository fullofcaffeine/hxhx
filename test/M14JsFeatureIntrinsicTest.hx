import sys.io.File;

/** Feature-selected source blocks must survive shared typing before JavaScript lowering. */
class M14JsFeatureIntrinsicTest {
	static function main():Void {
		final path = "test/fixtures/js_feature_intrinsic/Main.hx";
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		M14GenericConstructorArgumentTest.assertRuntime(typed, "Main", "enabled\nbranch\nabsent\n");
		Sys.println("JS_FEATURE_INTRINSIC:PASS");
	}
}
