class M14HihTryThrowStmtIntegrationTest {
	static function fail(msg:String):Void {
		throw msg;
	}

	static function assertTrue(cond:Bool, msg:String):Void {
		if (!cond)
			fail(msg);
	}

	static function firstMainFn(decl:HxModuleDecl):HxFunctionDecl {
		for (c in HxModuleDecl.getClasses(decl)) {
			if (HxClassDecl.getName(c) != "Main")
				continue;
			for (fn in HxClassDecl.getFunctions(c)) {
				if (HxFunctionDecl.getName(fn) == "main")
					return fn;
			}
		}
		fail("missing Main.main");
		return null;
	}

	static function main() {
		final src = 'class Main {\n' + '  static function main() {\n' + '    try {\n' + '      throw "boom";\n' + '    } catch (message:String) {\n'
			+ '      Sys.println(message);\n' + '    } catch (err:Dynamic) {\n' + '      Sys.println(err);\n' + '    }\n' + '  }\n' + '}\n';

		final decl = new HxParser(src).parseModule("Main");
		final mainFn = firstMainFn(decl);
		final body = HxFunctionDecl.getBody(mainFn);
		assertTrue(body.length > 0, "Main.main body should not be empty");

		switch (body[0]) {
			case STry(tryBody, catches, _):
				assertTrue(catches.length == 2, "expected two catch blocks");
				assertTrue(catches[0].name == "message", "first catch variable name should be parsed");
				assertTrue(catches[0].typeHint == "String", "first catch type hint should be parsed");
				assertTrue(catches[1].name == "err", "second catch variable name should be parsed");
				assertTrue(catches[1].typeHint == "Dynamic", "second catch type hint should be parsed");
				switch (tryBody) {
					case SBlock(stmts, _):
						assertTrue(stmts.length == 1, "try block should contain one statement");
						switch (stmts[0]) {
							case SThrow(EString("boom"), _):
							case _:
								fail("try block should contain throw \"boom\"");
						}
					case _:
						fail("try body should be parsed as SBlock");
				}
			case _:
				fail("first statement should be STry");
		}
	}
}
