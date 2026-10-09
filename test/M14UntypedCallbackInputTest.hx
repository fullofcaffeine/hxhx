/** Callback parameters retain later constraints when the callback crosses an untyped call boundary. */
class M14UntypedCallbackInputTest {
	public static function main():Void {
		M14UntypedHostIdentityTest.main();
		M14SourceCallbackReturnInferenceTest.main();
		for (entry in [
			{
				name: "unused_input",
				constrained: false,
				identity: false,
				expected: "7\n"
			},
			{
				name: "later_constraint",
				constrained: true,
				identity: false,
				expected: "7\n7\n"
			},
			{
				name: "identity_result",
				constrained: true,
				identity: true,
				expected: "7\n9\n"
			}
		]) {
			final constrained = entry.constrained;
			final name = entry.name;
			final source = program('var callback=function(value){return '
				+ (entry.identity ? 'value' : '7')
				+ ';};var fn=untyped handle.run;Sys.println(fn(callback));'
				+ (constrained ? 'var typed:(Int)->Int=callback;Sys.println(typed(9));' : ''));
			final expected = entry.expected;
			final root = ".tmp/untyped_callback_input_" + name;
			sys.FileSystem.createDirectory(root);
			final path = root + "/Main.hx";
			sys.io.File.saveContent(path, source);
			final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
			final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
			var callbacks = 0;
			function expression(value:TypedExpr):Void {
				if (value.getTag() == SourceFunction) {
					callbacks++;
					final arguments = value.getType().getFunctionArguments();
					if (arguments.length != 1 || arguments[0].getSemanticKey() != (constrained ? "primitive:Int" : "dynamic"))
						throw "callback input lost its final inference contract";
				}
				for (child in value.getExpressions())
					expression(child);
			}
			function statement(value:TypedStmt):Void {
				for (child in value.getExpressions())
					expression(child);
				for (child in value.getStatements())
					statement(child);
			}
			for (owner in typed.getTypedClasses())
				for (fn in owner.getFunctions())
					for (child in fn.getBody().getStatements())
						statement(child);
			if (callbacks != 1)
				throw "callback input fixture missed its authored function";
			JsRuntimeFixture.assertRuntime(typed, "Main", expected);
			@:privateAccess M14NekoClosureControlTest.assertSource("untyped_callback_" + name, source, expected);
			Sys.println("UNTYPED_CALLBACK_INPUT:PASS " + name);
		}
		final source = program('var callback=function(value){return 7;};var fn=untyped handle.run;fn(callback);'
			+ 'var typed:(Int)->Int=callback;var wrong:(String)->Int=callback;');
		final root = ".tmp/untyped_callback_input_conflict";
		sys.FileSystem.createDirectory(root);
		final path = root + "/Main.hx";
		sys.io.File.saveContent(path, source);
		final upstream = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "-neko", root + "/upstream.n"]);
		final errors = upstream.stderr.readAll().toString();
		final code = upstream.exitCode();
		upstream.close();
		if (code == 0 || errors.indexOf("should be") < 0)
			throw "upstream did not reject conflicting callback inputs: " + errors;
		var rejected = false;
		try {
			final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
			TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		} catch (error:TyperError) {
			rejected = error.message.indexOf("not compatible") >= 0;
		}
		if (!rejected)
			throw "untyped invocation erased a later callback input conflict";
		Sys.println("UNTYPED_CALLBACK_INPUT:PASS conflict");
	}

	/** The Dynamic boundary models an external host that invokes the supplied callback. */
	static function program(body:String):String {
		return 'abstract Handle(Dynamic){}class Main{static function invoke(callback:Dynamic):Int{return callback(7);}'
			+ 'static function main():Void{var handle:Handle=cast {run:invoke};'
			+ body
			+ '}}';
	}
}
