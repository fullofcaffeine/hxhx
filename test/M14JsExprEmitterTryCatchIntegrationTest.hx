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

		final typedBlock = JsExprEmitter.emit(ETryCatchRaw("opaque_block_expr:{ var x:TypedefToStringMap<String>; x; }"), exprScope);
		assertContains(typedBlock, "(function () { var x; return x; })()", "typed block expression should lower to returning IIFE");
		assertNotContains(typedBlock, "opaque_block_expr", "typed block expression should erase parser marker");
		assertNotContains(typedBlock, "TypedefToStringMap<String>", "typed block expression should erase local var type hint");

		final nestedValueBlock = JsExprEmitter.emit(ETryCatchRaw('opaque_block_expr:{ var test = { append("3"); 99; }; test; }'), exprScope);
		assertContains(nestedValueBlock, 'var test = (function () { append("3"); return 99; })();',
			"nested block expressions used as values should lower to returning IIFEs");
		assertNotContains(nestedValueBlock, 'var test = { append("3");', "nested block expressions should not leak as invalid JS object literals");

		final objectLiteral = JsExprEmitter.emit(ETryCatchRaw("opaque_block_expr:{ var obj = { value: 1 }; obj.value; }"), exprScope);
		assertContains(objectLiteral, "var obj = { value: 1 }; return obj.value;", "object literals should remain object literals inside raw block rewrites");

		final blockWithIf = JsExprEmitter.emit(ETryCatchRaw('opaque_block_expr:{ append("1"); if (cond2(getInt())) { append("2"); } else { append("3"); } buf.toString(); }'),
			exprScope);
		assertContains(blockWithIf, 'append("1"); if (cond2(getInt())) {', "raw block expressions should preserve the side-effect if statement");
		assertContains(blockWithIf, "return buf.toString();", "raw block expressions should return the final value after side-effect if statements");
		assertNotContains(blockWithIf, "return if", "raw block expressions should not emit invalid return-if syntax");

		final blockWithTerminalWhile = JsExprEmitter.emit(ETryCatchRaw("opaque_block_expr:{ var next = change; while (next.next != null) { next = next.next; } }"),
			exprScope);
		assertContains(blockWithTerminalWhile, "while (next.next != null)", "raw block expressions should preserve terminal while statements");
		assertContains(blockWithTerminalWhile, "return null;", "raw block expressions should return null after a terminal while statement");
		assertNotContains(blockWithTerminalWhile, "return while", "raw block expressions should not emit invalid return-while syntax");
	}
}
