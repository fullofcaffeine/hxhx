/**
	`do` with an unbraced body is ordinary Haxe: `do t++ while (t < 3);`. Upstream Haxe 4.3.7
	accepts it, with any single-statement body. The statement parser used to read the body past
	the `while` keyword and then reported `EUnsupported(do)` (haxe_ocaml-ac5i9.9, found by the
	parse oracle).
**/
class M14UnbracedDoWhileParseTest {
	static function bodyOf(source:String):Array<HxStmt> {
		final decl = ParserStage.parse("class Main { static function f() { " + source + " } }", "Main.hx").getDecl();
		return HxFunctionDecl.getBody(HxClassDecl.getFunctions(HxModuleDecl.getClasses(decl)[0])[0]);
	}

	static function expectDoWhile(label:String, source:String, index:Int, bodyCheck:HxStmt->Bool):Void {
		final body = bodyOf(source);
		if (index >= body.length)
			throw label + ": expected at least " + (index + 1) + " statements, got " + body;
		switch body[index] {
			case SDoWhile(loopBody, _, _):
				if (!bodyCheck(loopBody))
					throw label + ": unexpected loop body " + loopBody;
			case other:
				throw label + ": expected a do/while statement, got " + other;
		}
		if (body.length != index + 2)
			throw label + ": the statement after the loop was lost: " + body;
	}

	static function main():Void {
		expectDoWhile("increment", "var t = 0; do t++ while (t < 3); trace(t);", 1, body -> body.match(SExpr(EUnop(_, _, _), _)));
		expectDoWhile("call", "var t = 0; do g(t++) while (t < 3); trace(t);", 1, body -> body.match(SExpr(ECall(_, _), _)));
		expectDoWhile("if body", "var t = 0; do if (t > 1) t += 2 else t++ while (t < 5); trace(t);", 1, body -> body.match(SIf(_, _, _, _)));
		expectDoWhile("braced body", "var t = 0; do { t++; } while (t < 3); trace(t);", 1, body -> body.match(SBlock(_, _)));
		Sys.println("M14_UNBRACED_DO_WHILE_PARSE:PASS");
	}
}
