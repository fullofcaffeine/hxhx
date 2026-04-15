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
	}
}
