/** Later callback annotations constrain every return path through its original lexical input. */
class M14SourceCallbackReturnInferenceTest {
	public static function main():Void {
		for (entry in [
			{
				name: "same_input",
				body: 'var fn=function(value,flag:Bool){if(flag)return value;return value;};var typed:(Int,Bool)->Int=fn;Sys.println(typed(7,true));Sys.println(typed(9,false));'
			},
			{
				name: "distinct_inputs",
				body: 'var fn=function(left,right,flag:Bool){if(flag)return left;return right;};var typed:(Int,Int,Bool)->Int=fn;Sys.println(typed(7,9,true));Sys.println(typed(7,9,false));'
			},
			{
				name: "aliased_input",
				body: 'var fn=function(value,flag:Bool){var other=value;if(flag)return other;return value;};var typed:(Int,Bool)->Int=fn;Sys.println(typed(7,true));Sys.println(typed(9,false));'
			}
		]) {
			final source = program(entry.body);
			final path = "CallbackReturn_" + entry.name + ".hx";
			final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
			JsRuntimeFixture.assertRuntime(TyperStage.typeResolvedModule(module, TyperIndex.build([module])), "Main", "7\n9\n");
			@:privateAccess M14NekoClosureControlTest.assertSource("callback_return_" + entry.name, source, "7\n9\n");
			Sys.println("SOURCE_CALLBACK_RETURN:PASS " + entry.name);
		}
		final source = program('var fn=function(left,right,flag:Bool){if(flag)return left;return right;};var typed:(Int,String,Bool)->Int=fn;');
		final root = ".tmp/source_callback_return_conflict";
		sys.FileSystem.createDirectory(root);
		final path = root + "/Main.hx";
		sys.io.File.saveContent(path, source);
		final upstream = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "-js", root + "/upstream.js"]);
		final errors = upstream.stderr.readAll().toString();
		final code = upstream.exitCode();
		upstream.close();
		if (code == 0 || errors.indexOf("should be") < 0)
			throw "upstream accepted conflicting callback return paths: " + errors;
		var rejected = false;
		try {
			final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
			TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		} catch (error:TyperError) {
			rejected = error.filePath == path && error.message.indexOf("conflicts with its expected type") >= 0;
		}
		if (!rejected)
			throw "callback annotation lost a conflicting return path";
		Sys.println("SOURCE_CALLBACK_RETURN:PASS conflict");
	}

	static function program(body:String):String
		return 'class Main{static function main():Void{' + body + '}}';
}
