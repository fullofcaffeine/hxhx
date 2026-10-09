import sys.FileSystem;
import sys.io.File;

/** The same source behavior must survive ordinary and standard-library namespace placement. */
class M14JsAuthoredNamespaceTest {
	static function main():Void {
		final body = File.getContent("test/fixtures/js_authored_namespace/AuthoredStorage.hx");
		for (namespace in ["example", "haxe", "haxe.ds"]) {
			final output = JsRuntimeFixture.reserveOutput();
			final directory = output + "/" + StringTools.replace(namespace, ".", "/");
			FileSystem.createDirectory(directory);
			final path = directory + "/AuthoredStorage.hx";
			final source = "package " + namespace + ";\n" + body;
			final name = namespace + ".AuthoredStorage";
			File.saveContent(path, source);
			@:privateAccess M14JsFunctionLiteralRuntimeTest.command("haxe", ["-cp", output, "-main", name, "-js", output + "/upstream.js"]);
			@:privateAccess M14JsFunctionLiteralRuntimeTest.command("node", [output + "/upstream.js"]);
			Sys.println("JS_AUTHORED_NAMESPACE:" + namespace + ":upstream:PASS");
			final resolved = new ResolvedModule(name, path, ParserStage.parse(source, path));
			final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
			JsRuntimeFixture.assertRuntime(typed, name, "");
			@:privateAccess JsRuntimeFixture.removeOutput(output);
			Sys.println("JS_AUTHORED_NAMESPACE:" + namespace + ":local:PASS");
		}
		Sys.println("JS_AUTHORED_NAMESPACE:PASS");
	}
}
