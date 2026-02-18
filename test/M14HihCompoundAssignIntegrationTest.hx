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
			+ '    var a:Int = 1;\n'
			+ '    var b:Int = 2;\n'
			+ '    var x = a + +b;\n'
			+ '    acc += 5;\n'
			+ '    acc -= 1;\n'
			+ '    acc <<= 1;\n'
			+ '    acc >>>= 1;\n'
			+ '    acc++;\n'
			+ '    ++acc;\n'
			+ '    acc--;\n'
			+ '    --acc;\n'
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

		var plusEqCount = 0;
		var minusEqCount = 0;
		var sawShiftLeftEq = false;
		var sawUnsignedShiftRightEq = false;
		var sawBinaryPlusUnaryPlus = false;
		for (stmt in HxFunctionDecl.getBody(parsedMain)) {
			switch (stmt) {
				case SExpr(EBinop(op, EIdent("acc"), _), _):
					switch (op) {
						case "+=":
							plusEqCount += 1;
						case "-=":
							minusEqCount += 1;
						case "<<=":
							sawShiftLeftEq = true;
						case ">>>=":
							sawUnsignedShiftRightEq = true;
						case _:
					}
				case SVar("x", _, EBinop("+", EIdent("a"), EUnop("+", EIdent("b"))), _):
					sawBinaryPlusUnaryPlus = true;
				case _:
			}
		}

		assertTrue(plusEqCount == 3, "parser should lower explicit '+=' plus '++' forms to '+='");
		assertTrue(minusEqCount == 3, "parser should lower explicit '-=' plus '--' forms to '-='");
		assertTrue(sawBinaryPlusUnaryPlus, "parser should keep 'a + +b' as binary-plus with unary-plus rhs");
		assertTrue(sawShiftLeftEq, "parser should keep '<<=' as EBinop");
		assertTrue(sawUnsignedShiftRightEq, "parser should keep '>>>=' as EBinop");

		final pm = new ParsedModule(src, decl, "<m14_hih_compound_assign>");
		final tm = TyperStage.typeModule(pm);
		final typedMain = findTypedMain(tm);
		assertTrue(findLocalType(typedMain, "acc") == "Int", "compound assignment keeps local type stable");
	}
}
