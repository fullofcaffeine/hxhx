import backend.js.JsExprEmitter;
import backend.js.JsFunctionScope;

class M14JsExprEmitterTryCatchIntegrationTest {
	static function assertContains(haystack:String, needle:String, label:String):Void {
		if (haystack == null || haystack.indexOf(needle) < 0)
			throw label + ": expected substring '" + needle + "' in '" + haystack + "'";
	}

	static function assertNotContains(haystack:String, needle:String, label:String):Void {
		if (haystack != null && haystack.indexOf(needle) >= 0)
			throw label + ": unexpected substring '" + needle + "' in '" + haystack + "'";
	}

	static function main() {
		final scope = new JsFunctionScope(new haxe.ds.StringMap<String>());
		final exprScope = scope.exprScope();

		final simple = JsExprEmitter.emit(HxParser.parseExprText("try throw new Exception('') catch(e:Exception) e.stack"), exprScope);
		assertContains(simple, "(function () { try { throw new Exception(\"\"); } catch (e) {", "single-expression try/catch should lower to IIFE");
		assertContains(simple, "return e.stack;", "single-expression catch body should return stack expression");

		final privateAccess = JsExprEmitter.emit(HxParser.parseExprText("try throw @:privateAccess (Exception.thrown(''):Exception) catch(e:Exception) e.stack"),
			exprScope);
		assertContains(privateAccess, "catch (e) {", "typed catch should erase type hint");
		assertContains(privateAccess, "return e.stack;", "typed catch body should return stack expression");
		assertNotContains(privateAccess, "@:privateAccess", "try raw should erase expression metadata for JS");
		assertNotContains(privateAccess, ":Exception", "try raw should erase cast and catch type hints for JS");
	}
}
