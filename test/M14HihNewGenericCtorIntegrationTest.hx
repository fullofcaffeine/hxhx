class M14HihNewGenericCtorIntegrationTest {
	static function fail(msg:String):Void {
		throw msg;
	}

	static function findMainFunction(decl:HxModuleDecl):HxFunctionDecl {
		for (cls in HxModuleDecl.getClasses(decl)) {
			if (HxClassDecl.getName(cls) != "Main")
				continue;
			for (fn in HxClassDecl.getFunctions(cls))
				if (HxFunctionDecl.getName(fn) == "main")
					return fn;
		}
		fail("missing Main.main");
		return null;
	}

	static function findVarInit(stmts:Array<HxStmt>, name:String):Null<HxExpr> {
		for (s in stmts) {
			switch (s) {
				case SVar(n, _typeHint, init, _):
					if (n == name)
						return init;
				case _:
			}
		}
		return null;
	}

	static function assertGenericNew(init:Null<HxExpr>, varName:String):Void {
		switch (init) {
			case ENew(typePath, args):
				if (typePath != "MyGeneric")
					fail(varName + ": expected constructor type path MyGeneric, got " + typePath);
				if (args == null || args.length != 1)
					fail(varName + ": expected one constructor arg");
			case _:
				fail(varName + ": expected ENew, got " + Std.string(init));
		}
	}

	static function main() {
		final src = 'private typedef MyAnon = { a:Int };\n' + '@:generic class MyGeneric<T> {\n' + '  public var t:T;\n'
			+ '  public function new(t:T) { this.t = t; }\n' + '}\n' + 'class Main {\n' + '  static function main() {\n'
			+ '    var a = new MyGeneric<MyAnon>({a: 1});\n' + '    var b = new MyGeneric<String>("x");\n' + '  }\n' + '}\n';

		final decl = new HxParser(src).parseModule("Main");
		final mainFn = findMainFunction(decl);
		final body = HxFunctionDecl.getBody(mainFn);

		final initA = findVarInit(body, "a");
		final initB = findVarInit(body, "b");
		assertGenericNew(initA, "a");
		assertGenericNew(initB, "b");

		switch (initA) {
			case ENew(_, args):
				switch (args[0]) {
					case EAnon(fieldNames, fieldValues):
						if (fieldNames.length != 1 || fieldNames[0] != "a")
							fail("a: expected anon field a");
						switch (fieldValues[0]) {
							case EInt(v): if (v != 1) fail("a: expected value 1");
							case _: fail("a: expected int field initializer");
						}
					case _: fail("a: expected anonymous-struct constructor arg");
				}
			case _:
		}
	}
}
