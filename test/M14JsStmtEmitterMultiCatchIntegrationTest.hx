import backend.js.JsFunctionScope;
import backend.js.JsStmtEmitter;
import backend.js.JsWriter;

class M14JsStmtEmitterMultiCatchIntegrationTest {
	static function assertContains(haystack:String, needle:String, label:String):Void {
		if (haystack == null || haystack.indexOf(needle) < 0) {
			throw label + ": expected substring '" + needle + "' in '" + haystack + "'";
		}
	}

	static function main() {
		final pos = HxPos.unknown();
		final tryStmt:HxStmt = STry(
			SBlock([SThrow(EString("boom"), pos)], pos),
			[
				{
					name: "code",
					typeHint: "Int",
					body: SBlock([SExpr(ECall(EField(EIdent("Sys"), "println"), [EIdent("code")]), pos)], pos)
				},
				{
					name: "msg",
					typeHint: "String",
					body: SBlock([SExpr(ECall(EField(EIdent("Sys"), "println"), [EIdent("msg")]), pos)], pos)
				},
				{
					name: "fallback",
					typeHint: "Dynamic",
					body: SBlock([SExpr(ECall(EField(EIdent("Sys"), "println"), [EIdent("fallback")]), pos)], pos)
				}
			],
			pos
		);

		final writer = new JsWriter();
		final scope = new JsFunctionScope(new haxe.ds.StringMap<String>());
		JsStmtEmitter.emitFunctionBody(writer, [tryStmt], scope);
		final js = writer.toString();

		assertContains(js, "if ((typeof __hx_err === \"number\" && ((__hx_err | 0) === __hx_err))) {", "first catch should guard Int values");
		assertContains(js, "else if ((typeof __hx_err === \"string\" || __hx_err instanceof String)) {", "second catch should guard String values");
		assertContains(js, "else if (true) {", "dynamic catch should be emitted as catch-all");
		assertContains(js, "var code = __hx_err;", "first catch should bind its catch variable");
		assertContains(js, "var msg = __hx_err;", "second catch should bind its catch variable");
		assertContains(js, "var fallback = __hx_err;", "fallback catch should bind its catch variable");
		assertContains(js, "else {", "multi-catch dispatch should include fallback branch");
		assertContains(js, "throw __hx_err;", "multi-catch dispatch should preserve rethrow fallback");
	}
}
