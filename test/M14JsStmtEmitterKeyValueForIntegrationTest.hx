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
	}
}
