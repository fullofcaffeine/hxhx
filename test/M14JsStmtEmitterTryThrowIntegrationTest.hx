import backend.js.JsFunctionScope;
import backend.js.JsStmtEmitter;
import backend.js.JsWriter;

class M14JsStmtEmitterTryThrowIntegrationTest {
	static function assertContains(haystack:String, needle:String, label:String):Void {
		if (haystack == null || haystack.indexOf(needle) < 0) {
			throw label + ": expected substring '" + needle + "' in '" + haystack + "'";
		}
	}

	static function assertNotContains(haystack:String, needle:String, label:String):Void {
		if (haystack != null && haystack.indexOf(needle) >= 0) {
			throw label + ": unexpected substring '" + needle + "' in '" + haystack + "'";
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

		final functionBody = HxParser.parseFunctionBodyText("function negativeOnly(i:Int) { if(i >= 0) throw new ArgumentException('i'); } negativeOnly(10);");
		final functionWriter = new JsWriter();
		final classRefs = new haxe.ds.StringMap<String>();
		classRefs.set("ArgumentException", "ArgumentException");
		final functionScope = new JsFunctionScope(classRefs);
		JsStmtEmitter.emitFunctionBody(functionWriter, functionBody, functionScope);
		final functionJs = functionWriter.toString();

		assertContains(functionJs, "var negativeOnly = function(i)", "local function should lower to a JS function value");
		assertContains(functionJs, "((i >= 0) ? (function(){ throw new ArgumentException(\"i\"); })() : null)",
			"if/throw body should lower to a throw expression");
		assertContains(functionJs, "negativeOnly(10);", "local function call should emit after declaration");

		final superWriter = new JsWriter();
		final superScope = new JsFunctionScope(new haxe.ds.StringMap<String>());
		JsStmtEmitter.emitFunctionBody(superWriter, [SExpr(ECall(ESuper, [EIdent("message"), EIdent("previous")]), pos)], superScope);
		final superJs = superWriter.toString();
		assertContains(superJs, "base constructor call omitted", "function-style constructors should lower super calls to valid JS");
		assertNotContains(superJs, "super(", "function-style constructors cannot emit raw JS super syntax");
	}
}
