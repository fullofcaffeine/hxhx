class M14HihCompoundAssignIntegrationTest {
	static function assertTrue(ok:Bool, label:String):Void {
		if (!ok)
			throw label;
	}

	static function findTypedMain(tm:TypedModule):TyFunctionEnv {
		final cls = tm.getEnv().getMainClass();
		for (f in cls.getFunctions())
			if (f.getName() == "main")
				return f;
		throw "missing typed main()";
	}

	static function findLocalType(fn:TyFunctionEnv, name:String):String {
		for (l in fn.getLocals())
			if (l.getName() == name)
				return l.getType().getDisplay();
		for (p in fn.getParams())
			if (p.getName() == name)
				return p.getType().getDisplay();
		return "<missing>";
	}

	static function main() {
		final src = 'class Main {\n' + '  static function main() {\n' + '    var acc:Int = 1;\n' + '    acc += 5;\n' + '    acc -= 1;\n'
			+ '    acc <<= 1;\n' + '    acc >>>= 1;\n' + '    acc++;\n' + '    ++acc;\n' + '    acc--;\n' + '    --acc;\n' + '  }\n' + '}\n';

		final decl = new HxParser(src).parseModule("Main");
		final cls = HxModuleDecl.getMainClass(decl);
		var parsedMain:Null<HxFunctionDecl> = null;
		for (fn in HxClassDecl.getFunctions(cls)) {
			if (HxFunctionDecl.getName(fn) == "main") {
				parsedMain = fn;
				break;
			}
		}
		if (parsedMain == null)
			throw "missing parsed main()";

		var plusEqCount = 0;
		var minusEqCount = 0;
		var sawShiftLeftEq = false;
		var sawUnsignedShiftRightEq = false;
		var sawPreInc = false;
		var sawPreDec = false;
		var sawPostInc = false;
		var sawPostDec = false;
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
				case SExpr(EUnop(HxUnaryOperator.Increment, HxUnaryFixity.Prefix, EIdent("acc")), _):
					sawPreInc = true;
				case SExpr(EUnop(HxUnaryOperator.Decrement, HxUnaryFixity.Prefix, EIdent("acc")), _):
					sawPreDec = true;
				case SExpr(EUnop(HxUnaryOperator.Increment, HxUnaryFixity.Postfix, EIdent("acc")), _):
					sawPostInc = true;
				case SExpr(EUnop(HxUnaryOperator.Decrement, HxUnaryFixity.Postfix, EIdent("acc")), _):
					sawPostDec = true;
				case _:
			}
		}

		assertTrue(plusEqCount == 1, "parser should keep only source-written '+=' as compound assignment");
		assertTrue(minusEqCount == 1, "parser should keep only source-written '-=' as compound assignment");
		assertTrue(sawPreInc, "parser should preserve prefix '++' with prefix fixity");
		assertTrue(sawPreDec, "parser should preserve prefix '--' with prefix fixity");
		assertTrue(sawPostInc, "parser should preserve postfix '++' with postfix fixity");
		assertTrue(sawPostDec, "parser should preserve postfix '--' with postfix fixity");
		assertTrue(sawShiftLeftEq, "parser should keep '<<=' as EBinop");
		assertTrue(sawUnsignedShiftRightEq, "parser should keep '>>>=' as EBinop");

		var rejectedUnaryPositive = false;
		try {
			HxParser.parseExprText("+value");
		} catch (_:HxParseError) {
			rejectedUnaryPositive = true;
		}
		assertTrue(rejectedUnaryPositive, "parser should reject unary positive like upstream Haxe 4.3.7");
		var rejectedInvalidPostfix = false;
		try {
			HxUnaryOperatorTools.requireValidFixity(HxUnaryOperator.Negate, HxUnaryFixity.Postfix);
		} catch (_:Dynamic) {
			rejectedInvalidPostfix = true;
		}
		assertTrue(rejectedInvalidPostfix, "structured unary syntax should reject postfix-only invalid token/fixity pairs");

		final pm = new ParsedModule(src, decl, "<m14_hih_compound_assign>");
		final tm = TyperStage.typeModule(pm);
		final typedMain = findTypedMain(tm);
		assertTrue(findLocalType(typedMain, "acc") == "Int", "compound assignment keeps local type stable");

		final previousMutableRefs = @:privateAccess EmitterStage.currentMutableLocalRefNames;
		@:privateAccess EmitterStage.currentMutableLocalRefNames = ["acc"];
		var prefixOcaml = "";
		var postfixOcaml = "";
		try {
			prefixOcaml = @:privateAccess EmitterStage.exprToOcaml(EUnop(HxUnaryOperator.Increment, HxUnaryFixity.Prefix, EIdent("acc")));
			postfixOcaml = @:privateAccess EmitterStage.exprToOcaml(EUnop(HxUnaryOperator.Increment, HxUnaryFixity.Postfix, EIdent("acc")));
		} catch (error:Dynamic) {
			@:privateAccess EmitterStage.currentMutableLocalRefNames = previousMutableRefs;
			throw error;
		}
		@:privateAccess EmitterStage.currentMutableLocalRefNames = previousMutableRefs;
		assertTrue(prefixOcaml.indexOf(":= __hx_next; __hx_next") >= 0, "OCaml prefix increment should return the updated value");
		assertTrue(postfixOcaml.indexOf(":= __hx_next; __hx_old") >= 0, "OCaml postfix increment should return the old value");
	}
}
