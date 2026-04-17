class M14HxhxStage3GenericFunctionArityIntegrationTest {
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

	static function readOptional(path:String):Null<String> {
		return sys.FileSystem.exists(path) ? sys.io.File.getContent(path) : null;
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

	static function assertBootstrapSnapshotCarriesGenericMethodRepair():Void {
		final snapshotPath = "packages/hxhx/bootstrap_out/HxParser.ml";
		final snapshot = readOptional(snapshotPath);
		assertTrue(snapshot != null, "missing committed bootstrap parser snapshot at " + snapshotPath);
		assertTrue(snapshot.indexOf("let skipBalancedAngles = fun self () ->") >= 0, "bootstrap parser snapshot must define skipBalancedAngles");
		assertTrue(snapshot.indexOf('isOtherChar (Obj.magic self) ("<" : string)') >= 0,
			"bootstrap parser snapshot must detect method type parameters before '('");
		assertTrue(snapshot.indexOf("skipBalancedAngles (Obj.magic self) ()") >= 0, "bootstrap parser snapshot must skip method type parameter groups");
	}

	static function assertBootstrapNativeParserKeepsNestedTypeHintCommas():Void {
		final snapshotPath = "packages/hxhx/bootstrap_out/runtime/HxHxNativeParser.ml";
		final snapshot = readOptional(snapshotPath);
		assertTrue(snapshot != null, "missing committed bootstrap native parser snapshot at " + snapshotPath);
		assertTrue(snapshot.indexOf("let type_hint_top_level () =") >= 0, "bootstrap native parser snapshot must track nested type hints");
		assertTrue(snapshot.indexOf("Sym (',', _)") >= 0 && snapshot.indexOf("type_hint_top_level ()") >= 0,
			"bootstrap native parser snapshot must only split top-level parameter commas");
		assertTrue(snapshot.indexOf("Sym ('<', _) when !reading_type") >= 0, "bootstrap native parser snapshot must track generic type hint angle depth");
	}

	static function assertBootstrapNativeParserAllowsKeywordPathSegments():Void {
		final sourcePath = "packages/reflaxe.ocaml/std/runtime/HxHxNativeParser.ml";
		final source = readOptional(sourcePath);
		assertTrue(source != null, "missing native parser source at " + sourcePath);
		assertTrue(source.indexOf("let read_path_ident () : string =") >= 0, "native parser source must distinguish path identifiers");
		assertTrue(source.indexOf('"macro"') >= 0, "native parser source must accept macro as a path segment");
		assertTrue(source.indexOf('"extern"') >= 0, "native parser source must accept extern as a path segment");

		final snapshotPath = "packages/hxhx/bootstrap_out/runtime/HxHxNativeParser.ml";
		final snapshot = readOptional(snapshotPath);
		assertTrue(snapshot != null, "missing committed bootstrap native parser snapshot at " + snapshotPath);
		assertTrue(snapshot.indexOf("let read_path_ident () : string =") >= 0, "bootstrap native parser snapshot must distinguish path identifiers");
		assertTrue(snapshot.indexOf('"macro"') >= 0, "bootstrap native parser snapshot must accept macro as a path segment");
		assertTrue(snapshot.indexOf('"extern"') >= 0, "bootstrap native parser snapshot must accept extern as a path segment");
	}

	static function assertParsedGenericMethods(decl:HxModuleDecl, sourceLabel:String):Void {
		final cls = findClass(decl, "GenericMethods");

		final map = findFunction(cls, "map");
		assertEqString(HxFunctionDecl.getName(map), "map", sourceLabel + ": map function name");
		assertEqInt(HxFunctionDecl.getArgs(map).length, 1, sourceLabel + ": map arg count");
		assertEqString(HxFunctionArg.getName(HxFunctionDecl.getArgs(map)[0]), "f", sourceLabel + ": map arg name");
		assertEqString(HxFunctionArg.getTypeHint(HxFunctionDecl.getArgs(map)[0]), "T->X", sourceLabel + ": map arg type");
		assertEqString(HxFunctionDecl.getReturnTypeHint(map), "Array<X>", sourceLabel + ": map return type");

		final create = findFunction(cls, "create");
		assertTrue(HxFunctionDecl.getIsStatic(create), sourceLabel + ": create should be static");
		assertEqInt(HxFunctionDecl.getArgs(create).length, 0, sourceLabel + ": create arg count");
		assertEqString(HxFunctionDecl.getReturnTypeHint(create), "GenericMethods<T>", sourceLabel + ": create return type");
	}

	static function assertVendorListParsesWhenAvailable():Void {
		final listPath = "vendor/haxe/std/haxe/ds/List.hx";
		final listSource = readOptional(listPath);
		if (listSource == null)
			return;

		final decl = ParserStage.parse(listSource, listPath).getDecl();
		final listClass = findClass(decl, "List");
		final map = findFunction(listClass, "map");
		assertEqString(HxFunctionDecl.getName(map), "map", "List.map function name");
		assertEqInt(HxFunctionDecl.getArgs(map).length, 1, "List.map arg count");
		assertEqString(HxFunctionDecl.getReturnTypeHint(map), "List<X>", "List.map return type");

		final listNode = findClass(decl, "ListNode");
		final create = findFunction(listNode, "create");
		assertTrue(HxFunctionDecl.getIsStatic(create), "ListNode.create should be static");
		assertEqInt(HxFunctionDecl.getArgs(create).length, 2, "ListNode.create arg count");
		assertEqString(HxFunctionDecl.getReturnTypeHint(create), "ListNode<T>", "ListNode.create return type");
	}

	static function main() {
		assertBootstrapSnapshotCarriesGenericMethodRepair();
		assertBootstrapNativeParserKeepsNestedTypeHintCommas();
		assertBootstrapNativeParserAllowsKeywordPathSegments();

		final src = '@:generic class GenericMethods<T> {\n'
			+ '  public function new() {}\n'
			+ '  public function map<X>(f:T->X):Array<X> { return []; }\n'
			+ '  public static function create<T>():GenericMethods<T> { return new GenericMethods<T>(); }\n'
			+ '}\n'
			+ 'class Main {\n'
			+ '  static function main() {}\n'
			+ '}\n';
		assertParsedGenericMethods(ParserStage.parse(src, "GenericMethods.hx").getDecl(), "ParserStage");
		assertVendorListParsesWhenAvailable();
	}
}
