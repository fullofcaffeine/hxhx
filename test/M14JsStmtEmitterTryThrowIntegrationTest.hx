import backend.js.JsFunctionScope;
import backend.js.JsStmtEmitter;
import backend.js.JsWriter;

class M14JsStmtEmitterTryThrowIntegrationTest {
	static function assertContains(haystack:String, needle:String, label:String):Void {
		if (haystack == null || haystack.indexOf(needle) < 0) {
			throw label + ": expected substring '" + needle + "' in '" + haystack + "'";
		}
	}

	static function main() {
		final pos = HxPos.unknown();
		final tryStmt:HxStmt = STry(SBlock([SThrow(EString("boom"), pos)], pos), [
			{
				name: "err",
				typeHint: "Dynamic",
				body: SBlock([SExpr(ECall(EField(EIdent("Sys"), "println"), [EIdent("err")]), pos)], pos)
			}
		], pos);

		final writer = new JsWriter();
		final scope = new JsFunctionScope(new haxe.ds.StringMap<String>());
		JsStmtEmitter.emitFunctionBody(writer, [tryStmt], scope);
		final js = writer.toString();

		assertContains(js, "try {", "try statement should emit try block");
		assertContains(js, "throw \"boom\";", "throw statement should emit throw expression");
		assertContains(js, "} catch (__hx_err) {", "try statement should emit catch block");
		assertContains(js, "if (true) {", "dynamic catch should be treated as a catch-all clause");
		assertContains(js, "var err = __hx_err;", "catch block should bind catch variable");
		assertContains(js, "console.log(err);", "catch body should emit contained statements");
		assertContains(js, "throw __hx_err;", "catch dispatch should preserve fallback rethrow");
	}
}
