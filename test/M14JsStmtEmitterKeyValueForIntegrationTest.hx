import backend.js.JsFunctionScope;
import backend.js.JsStmtEmitter;
import backend.js.JsWriter;

/** Real-provider iteration and extractor behavior share validation with legacy adapter and diagnostic contracts. */
class M14JsStmtEmitterKeyValueForIntegrationTest {
	static function assertContains(haystack:String, needle:String, label:String):Void {
		if (haystack == null || haystack.indexOf(needle) < 0) {
			throw label + ": expected substring '" + needle + "' in '" + haystack + "'";
		}
	}

	static function pairs():Void {
		M14JsKeyValueRuntimeTest.run();

		// Source functions now require shared control lowering. Exercise this older
		// expression adapter at its actual input boundary; the typed runtime fixture
		// separately covers authored local functions through the normal pipeline.
		final localFunctionScope = new JsFunctionScope(new haxe.ds.StringMap<String>());
		final localFunctionJs = backend.js.JsExprEmitter.emit(ECall(EIdent("__hxhx_for_key_value"), [
			EArrayDecl([EInt(3), EInt(2)]),
			ELambda(["k", "v"], ECall(EIdent("observe"), [EIdent("k"), EIdent("v")])),
			EIdent("pairs")
		]), localFunctionScope.exprScope());

		assertContains(localFunctionJs, "Object.keys(__iter)", "local key/value function should enumerate keys in expression-lambda lowering");
		assertContains(localFunctionJs, "Array.isArray(__iter)", "local key/value function should normalize array keys to Int values");
		assertContains(localFunctionJs, "function(k, v) {", "local key/value function should emit a two-argument loop callback");
		assertContains(localFunctionJs, "return pairs;", "expression iteration should run its continuation after the loop");
		checkRuntime('var pairs=[]; function observe(k,v) { if(typeof k!=="number") throw "non-numeric key"; pairs.push(k+":"+v); } var got='
			+ localFunctionJs
			+ ';',
			'if (got.join(",") !== "0:3,1:2") throw "adapter pair values";');
	}

	static function main():Void {
		M14KeyValueProtocolFactsTest.run();
		M14KeyValueProtocolDiagnosticsTest.run();
		M14JsIterationCaptureTest.run();
		M14JsIterationBoundariesTest.run();
		@:privateAccess M14KeyValueProtocolTest.main();
		@:privateAccess M14KeyValueComprehensionTest.main();
		pairs();
		final typeErrorBody = HxParser.parseFunctionBodyText("var s = HelperMacros.typeErrorText(for (key => value in 1) { }); t(HelperMacros.typeError(for (key => value in new MyNotIterator()) { }));");
		final typeErrorWriter = new JsWriter();
		final typeErrorScope = new JsFunctionScope(new haxe.ds.StringMap<String>());
		JsStmtEmitter.emitFunctionBody(typeErrorWriter, typeErrorBody, typeErrorScope);
		final typeErrorJs = typeErrorWriter.toString();

		assertContains(typeErrorJs, "var s = \"Int has no field keyValueIterator\";",
			"HelperMacros.typeErrorText key/value for probe should fold to diagnostic text");
		assertContains(typeErrorJs, "t(true);", "HelperMacros.typeError key/value for probe should fold to true");

		final blockTypeErrorBody = HxParser.parseFunctionBodyText('f(typeError({ var b:{v:Dynamic} = {v:"foo"}; })); t(typeError({ var b:{v:Int} = {v:1.2}; }));');
		final blockTypeErrorWriter = new JsWriter();
		final blockTypeErrorScope = new JsFunctionScope(new haxe.ds.StringMap<String>());
		JsStmtEmitter.emitFunctionBody(blockTypeErrorWriter, blockTypeErrorBody, blockTypeErrorScope);
		final blockTypeErrorJs = blockTypeErrorWriter.toString();

		assertContains(blockTypeErrorJs, "f(false);", "HelperMacros.typeError valid opaque block probe should fold to false");
		assertContains(blockTypeErrorJs, "t(true);", "HelperMacros.typeError invalid opaque block probe should fold to true");
		Sys.println("JS_KEY_VALUE_INTEGRATION:PASS");
	}

	/** A separate JavaScript assertion observes generated values without modifying the generated loop. */
	static function checkRuntime(javascript:String, assertion:String):Void {
		final output = JsRuntimeFixture.reserveOutput();
		final path = output + "/main.js";
		sys.io.File.saveContent(path, javascript + "\n" + assertion);
		final process = new sys.io.Process("node", [path]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0)
			throw "pair iteration differs; retained " + output + ": " + stdout + stderr;
		@:privateAccess JsRuntimeFixture.removeOutput(output);
	}
}
