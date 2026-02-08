class M14HihForInIntegrationTest {
	static function assertEquals(actual:String, expected:String, label:String):Void {
		if (actual != expected) throw label + ": expected '" + expected + "' but got '" + actual + "'";
	}

	static function findLocalType(fn:TyFunctionEnv, name:String):String {
		for (l in fn.getLocals()) if (l.getName() == name) return l.getType().getDisplay();
		for (p in fn.getParams()) if (p.getName() == name) return p.getType().getDisplay();
		return "<missing>";
	}

	static function main() {
		final src = 'class Main {\n'
			+ '  static function main() {\n'
			+ '    var xs = ["A", "B"];\n'
			+ '    for (x in xs) trace(x);\n'
			+ '    for (i in 0...3) trace(i);\n'
			+ '  }\n'
			+ '}\n';

		final decl = new HxParser(src).parseModule("Main");
		final pm = new ParsedModule(src, decl, "<m14_hih_forin>");
		final tm = TyperStage.typeModule(pm);
		final cls = tm.getEnv().getMainClass();
		final fns = cls.getFunctions();

		var mainFn:Null<TyFunctionEnv> = null;
		for (f in fns) if (f.getName() == "main") mainFn = f;
		if (mainFn == null) throw "missing typed main()";

		assertEquals(findLocalType(mainFn, "xs"), "Array<String>", "xs array literal infers element type");
		assertEquals(findLocalType(mainFn, "x"), "String", "for-in over Array<String> binds String loop var");
		assertEquals(findLocalType(mainFn, "i"), "Int", "for-in over range binds Int loop var");
	}
}
