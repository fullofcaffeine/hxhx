class M14HihGenericFunctionDeclIntegrationTest {
	static function fail(msg:String):Void {
		throw msg;
	}

	static function assertTrue(ok:Bool, label:String):Void {
		if (!ok)
			fail(label);
	}

	static function assertEqString(actual:String, expected:String, label:String):Void {
		if (actual != expected)
			fail(label + ": expected " + expected + ", got " + actual);
	}

	static function assertEqInt(actual:Int, expected:Int, label:String):Void {
		if (actual != expected)
			fail(label + ": expected " + expected + ", got " + actual);
	}

	static function findClass(decl:HxModuleDecl, name:String):HxClassDecl {
		for (cls in HxModuleDecl.getClasses(decl)) {
			if (HxClassDecl.getName(cls) == name)
				return cls;
		}
		fail("missing class " + name);
		return null;
	}

	static function findFunction(cls:HxClassDecl, name:String):HxFunctionDecl {
		for (fn in HxClassDecl.getFunctions(cls)) {
			if (HxFunctionDecl.getName(fn) == name)
				return fn;
		}
		fail("missing function " + HxClassDecl.getName(cls) + "." + name);
		return null;
	}

	static function assertArg(fn:HxFunctionDecl, index:Int, name:String, typeHint:String):Void {
		final args = HxFunctionDecl.getArgs(fn);
		assertTrue(index >= 0 && index < args.length, HxFunctionDecl.getName(fn) + ": missing arg " + index);
		final arg = args[index];
		assertEqString(HxFunctionArg.getName(arg), name, HxFunctionDecl.getName(fn) + ": arg name " + index);
		assertEqString(HxFunctionArg.getTypeHint(arg), typeHint, HxFunctionDecl.getName(fn) + ": arg type " + index);
	}

	static function main() {
		final src = '@:generic class GenericMethods<T> {\n'
			+ '  public function new() {}\n'
			+ '  public function map<X>(f:T->X):Array<X> { return []; }\n'
			+ '  public static function create<T>():GenericMethods<T> { return new GenericMethods<T>(); }\n'
			+ '  public function fold<A>(init:A, f:A->T->A):A { return init; }\n'
			+ '}\n'
			+ 'class Main {\n'
			+ '  static function main() {}\n'
			+ '}\n';

		final decl = new HxParser(src).parseModule("Main");
		final cls = findClass(decl, "GenericMethods");

		final map = findFunction(cls, "map");
		assertEqString(HxFunctionDecl.getName(map), "map", "method type parameters must not become part of the function name");
		assertTrue(!HxFunctionDecl.getIsStatic(map), "map should remain an instance method");
		assertEqInt(HxFunctionDecl.getArgs(map).length, 1, "map arg count");
		assertArg(map, 0, "f", "T->X");
		assertEqString(HxFunctionDecl.getReturnTypeHint(map), "Array<X>", "map return type");

		final create = findFunction(cls, "create");
		assertTrue(HxFunctionDecl.getIsStatic(create), "create should remain static");
		assertEqInt(HxFunctionDecl.getArgs(create).length, 0, "create arg count");
		assertEqString(HxFunctionDecl.getReturnTypeHint(create), "GenericMethods<T>", "create return type");

		final fold = findFunction(cls, "fold");
		assertEqInt(HxFunctionDecl.getArgs(fold).length, 2, "fold arg count");
		assertArg(fold, 0, "init", "A");
		assertArg(fold, 1, "f", "A->T->A");
		assertEqString(HxFunctionDecl.getReturnTypeHint(fold), "A", "fold return type");
	}
}
