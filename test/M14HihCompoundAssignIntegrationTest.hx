class M14HihCompoundAssignIntegrationTest {
	static function assertTrue(ok:Bool, label:String):Void {
		if (!ok) throw label;
	}

	static function findTypedMain(tm:TypedModule):TyFunctionEnv {
		final cls = tm.getEnv().getMainClass();
		for (f in cls.getFunctions()) if (f.getName() == "main") return f;
		throw "missing typed main()";
	}

	static function findLocalType(fn:TyFunctionEnv, name:String):String {
		for (l in fn.getLocals()) if (l.getName() == name) return l.getType().getDisplay();
		for (p in fn.getParams()) if (p.getName() == name) return p.getType().getDisplay();
		return "<missing>";
	}

	static function main() {
		final src = 'class Main {\n'
			+ '  static function main() {\n'
			+ '    var acc:Int = 1;\n'
			+ '    acc += 5;\n'
			+ '    acc <<= 1;\n'
			+ '    acc >>>= 1;\n'
			+ '  }\n'
			+ '}\n';

		final decl = new HxParser(src).parseModule("Main");
		final cls = HxModuleDecl.getMainClass(decl);
		var parsedMain:Null<HxFunctionDecl> = null;
		for (fn in HxClassDecl.getFunctions(cls)) {
			if (HxFunctionDecl.getName(fn) == "main") {
				parsedMain = fn;
				break;
			}
		}
		if (parsedMain == null) throw "missing parsed main()";

		var sawPlusEq = false;
		var sawShiftLeftEq = false;
		var sawUnsignedShiftRightEq = false;
		for (stmt in HxFunctionDecl.getBody(parsedMain)) {
			switch (stmt) {
				case SExpr(EBinop(op, EIdent("acc"), _), _):
					switch (op) {
						case "+=":
							sawPlusEq = true;
						case "<<=":
							sawShiftLeftEq = true;
						case ">>>=":
							sawUnsignedShiftRightEq = true;
						case _:
					}
				case _:
			}
		}

		assertTrue(sawPlusEq, "parser should keep '+=' as EBinop");
		assertTrue(sawShiftLeftEq, "parser should keep '<<=' as EBinop");
		assertTrue(sawUnsignedShiftRightEq, "parser should keep '>>>=' as EBinop");

		final pm = new ParsedModule(src, decl, "<m14_hih_compound_assign>");
		final tm = TyperStage.typeModule(pm);
		final typedMain = findTypedMain(tm);
		assertTrue(findLocalType(typedMain, "acc") == "Int", "compound assignment keeps local type stable");
	}
}
