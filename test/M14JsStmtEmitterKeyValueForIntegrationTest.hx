import backend.js.JsFunctionScope;
import backend.js.JsStmtEmitter;
import backend.js.JsWriter;

class M14JsStmtEmitterKeyValueForIntegrationTest {
	static function assertContains(haystack:String, needle:String, label:String):Void {
		if (haystack == null || haystack.indexOf(needle) < 0) {
			throw label + ": expected substring '" + needle + "' in '" + haystack + "'";
		}
	}

	static function main() {
		final body = HxParser.parseFunctionBodyText("var data = ['left' => [1], 'right' => [2]]; for(label => stacks in data) { Sys.println(label + ':' + stacks.length); }");
		final writer = new JsWriter();
		final scope = new JsFunctionScope(new haxe.ds.StringMap<String>());
		JsStmtEmitter.emitFunctionBody(writer, body, scope);
		final js = writer.toString();

		assertContains(js, "var data = {\"left\": [1], \"right\": [2]};", "map literal should lower to JS object");
		assertContains(js, "var __keys_1 = Object.keys(__iter_0);", "key/value for should enumerate object keys");
		assertContains(js, "for (var __i_2 = 0; __i_2 < __keys_1.length; __i_2++) {", "key/value for should emit indexed key loop");
		assertContains(js, "var label = __keys_1[__i_2];", "key binding should read current key");
		assertContains(js, "var stacks = __iter_0[label];", "value binding should read by key");
		assertContains(js, "console.log(((label + \":\") + stacks.length));", "loop body should resolve key and value locals");

		final localFunctionBody = HxParser.parseFunctionBodyText("function collect(r:Array<Int>) { var keys = []; var values = []; for (k => v in r) { keys.push(k); values.push(v); } return {keys: keys, values: values}; } var got = collect([3, 2]);");
		final localFunctionWriter = new JsWriter();
		final localFunctionScope = new JsFunctionScope(new haxe.ds.StringMap<String>());
		JsStmtEmitter.emitFunctionBody(localFunctionWriter, localFunctionBody, localFunctionScope);
		final localFunctionJs = localFunctionWriter.toString();

		assertContains(localFunctionJs, "Object.keys(__iter)", "local key/value function should enumerate keys in expression-lambda lowering");
		assertContains(localFunctionJs, "Array.isArray(__iter)", "local key/value function should normalize array keys to Int values");
		assertContains(localFunctionJs, "function(k, v) {", "local key/value function should emit a two-argument loop callback");
		assertContains(localFunctionJs, "keys.push(k)", "local key/value function should preserve key push side effect");
		assertContains(localFunctionJs, "values.push(v)", "local key/value function should preserve value push side effect");
		assertContains(localFunctionJs, "return {\"keys\": keys, \"values\": values};", "local key/value function should run the continuation after the loop");

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
	}
}
