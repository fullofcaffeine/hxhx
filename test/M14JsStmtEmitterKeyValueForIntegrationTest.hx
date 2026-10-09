import backend.js.JsFunctionScope;
import backend.js.JsStmtEmitter;
import backend.js.JsWriter;

/** Legacy expression adapters and object-backed map iteration retain their runtime contracts. */
class M14JsStmtEmitterKeyValueForIntegrationTest {
	static function assertContains(haystack:String, needle:String, label:String):Void {
		if (haystack == null || haystack.indexOf(needle) < 0) {
			throw label + ": expected substring '" + needle + "' in '" + haystack + "'";
		}
	}

	static function pairs():Void {
		final body = HxParser.parseFunctionBodyText("var data = ['left' => [1], 'right' => [2]]; for(label => stacks in data) { Sys.println(label + ':' + stacks.length); }");
		final writer = new JsWriter();
		final scope = new JsFunctionScope(new haxe.ds.StringMap<String>());
		JsStmtEmitter.emitFunctionBody(writer, body, scope);
		final js = writer.toString();

		assertContains(js, "var data = {\"left\": [1], \"right\": [2]};", "map literal should lower to JS object");
		assertContains(js, "var __keys_2 = __array_1 ? null : Object.keys(__iter_0);", "objects should retain a key snapshot");
		assertContains(js, "for (var __i_3 = 0; __i_3 < (__array_1 ? __iter_0.length : __keys_2.length); __i_3++) {", "arrays should observe current length");
		assertContains(js, "var label = __array_1 ? __i_3 : __keys_2[__i_3];", "arrays supply integer keys while objects retain string keys");
		assertContains(js, "var stacks = __iter_0[label];", "value binding should read by key");
		assertContains(js, "console.log(", "loop body should emit the println call");
		assertContains(js, "__hx_op_add", "loop body should use abstract-aware addition lowering");
		assertContains(js, "stacks.length", "loop body should resolve the value local field access");

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
		final objectWriter = new JsWriter();
		JsStmtEmitter.emitFunctionBody(objectWriter,
			HxParser.parseFunctionBodyText("var seen = []; var data = ['01' => 2, 'alpha' => 3]; for (key => value in data) seen.push(key);"),
			new JsFunctionScope(new haxe.ds.StringMap<String>()));
		checkRuntime(objectWriter.toString(), 'if (seen.join(",") !== "01,alpha" || typeof seen[0] !== "string") throw "object keys changed";');
	}

	static function main():Void {
		pairs();
		final switchBody = HxParser.parseFunctionBodyText("var result = {}; switch item { case FilePos(s, f, l, _): result.file = f; result.line = l; switch s { case Method(_, m): result.method = m; case _: } case _: } return result;");
		final switchWriter = new JsWriter();
		final switchScope = new JsFunctionScope(new haxe.ds.StringMap<String>());
		JsStmtEmitter.emitFunctionBody(switchWriter, switchBody, switchScope);
		final switchJs = switchWriter.toString();

		assertContains(switchJs, "__sw_0.__hx_ctor === \"FilePos\"", "enum extractor should compare constructor name");
		assertContains(switchJs, "var s = __sw_0.__hx_params[0];", "enum extractor should bind first constructor arg");
		assertContains(switchJs, "var f = __sw_0.__hx_params[1];", "enum extractor should bind second constructor arg");
		assertContains(switchJs, "var l = __sw_0.__hx_params[2];", "enum extractor should bind third constructor arg");
		assertContains(switchJs, "__sw_1.__hx_ctor === \"Method\"", "nested enum extractor should compare nested constructor");
		assertContains(switchJs, "var m = __sw_1.__hx_params[1];", "nested enum extractor should bind nested arg");

		final objectPatternBody = HxParser.parseFunctionBodyText("var out = null; switch payload { case EParenthesis({ expr : EConst(CString(s)) }) | EUntyped({ expr : EConst(CString(s)) }): out = s; case EArray(_, { expr : EConst(CInt(i) | CFloat(i)) }): out = Std.string(i); case _: out = \"none\"; } return out;");
		final objectPatternWriter = new JsWriter();
		final objectPatternScope = new JsFunctionScope(new haxe.ds.StringMap<String>());
		JsStmtEmitter.emitFunctionBody(objectPatternWriter, objectPatternBody, objectPatternScope);
		final objectPatternJs = objectPatternWriter.toString();

		assertContains(objectPatternJs, "__sw_0.__hx_ctor === \"EParenthesis\"", "OR object pattern should test first constructor");
		assertContains(objectPatternJs, "__sw_0.__hx_ctor === \"EUntyped\"", "OR object pattern should test second constructor");
		assertContains(objectPatternJs, "__sw_0.__hx_params[0].expr.__hx_ctor === \"EConst\"", "object pattern should match nested expr field");
		assertContains(objectPatternJs, "var s = __sw_0.__hx_params[0].expr.__hx_params[0].__hx_params[0];",
			"OR alternatives with identical bind paths should bind shared string value");
		assertContains(objectPatternJs, "__sw_0.__hx_ctor === \"EArray\"", "object pattern should keep following enum extractor cases");
		assertContains(objectPatternJs, "__sw_0.__hx_params[1].expr.__hx_params[0].__hx_ctor === \"CInt\"", "nested OR should test first numeric constructor");
		assertContains(objectPatternJs, "__sw_0.__hx_params[1].expr.__hx_params[0].__hx_ctor === \"CFloat\"",
			"nested OR should test second numeric constructor");
		assertContains(objectPatternJs, "var i = __sw_0.__hx_params[1].expr.__hx_params[0].__hx_params[0];",
			"nested OR alternatives with identical bind paths should bind shared numeric value");

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
