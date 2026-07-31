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

	static function findScannedClass(classes:Array<HxClassDecl>, name:String):HxClassDecl {
		for (cls in classes) {
			if (HxClassDecl.getName(cls) == name)
				return cls;
		}
		fail("missing scanned class " + name);
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

	static function assertListKeyValueIteratorNextShape(next:HxFunctionDecl, sourceLabel:String):Void {
		assertEqString(HxFunctionDecl.getReturnTypeHint(next), "{key:Int,value:T}", sourceLabel + ": ListKeyValueIterator.next return type");
		switch (HxFunctionDecl.getBody(next)) {
			case [
				SVar("val", _, EField(EIdent("head"), "item"), _),
				SExpr(EBinop("=", EIdent("head"), EField(EIdent("head"), "next")), _),
				SReturn(EAnon(fieldNames, fieldValues), _)
			]:
				assertEqInt(fieldNames.length, 2, sourceLabel + ": ListKeyValueIterator.next return field count");
				assertEqString(fieldNames[0], "value", sourceLabel + ": ListKeyValueIterator.next return field 0");
				assertEqString(fieldNames[1], "key", sourceLabel + ": ListKeyValueIterator.next return field 1");
				switch (fieldValues[0]) {
					case EIdent("val"):
					case other:
						fail(sourceLabel + ": ListKeyValueIterator.next value field should return val, got " + Std.string(other));
				}
				switch (fieldValues[1]) {
					case EUnop(HxUnaryOperator.Increment, HxUnaryFixity.Postfix, EIdent("idx")):
					case other:
						fail(sourceLabel + ": ListKeyValueIterator.next key field should post-increment idx, got " + Std.string(other));
				}
			case body:
				fail(sourceLabel + ": ListKeyValueIterator.next body lost key/value return shape: " + Std.string(body));
		}
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

	static function assertScannedGenericNamedFunctionArg():Void {
		final source = [
			"class LambdaLike {",
			"  public static function mapi<A,B>(it:Iterable<A>, f:(index:Int, item:A) -> B):Array<B> {",
			"    var i = 0;",
			"    return [for (x in it) f(i++, x)];",
			"  }",
			"}"
		].join("\n");
		final helpers = ParserStageScanHelpers.scanModuleLocalHelperClasses(source, null);
		final lambdaLike = findScannedClass(helpers, "LambdaLike");
		final mapi = findFunction(lambdaLike, "mapi");
		assertEqInt(HxFunctionDecl.getArgs(mapi).length, 2, "scanned generic mapi arg count");
		final fArg = HxFunctionDecl.getArgs(mapi)[1];
		assertEqString(HxFunctionArg.getName(fArg), "f", "scanned generic mapi callback arg name");
		assertEqString(HxFunctionArg.getTypeHint(fArg), "(index:Int,item:A)->B", "scanned generic mapi callback arg type");
		assertEqString(HxFunctionDecl.getReturnTypeHint(mapi), "Array<B>", "scanned generic mapi return type");
	}

	static function assertScannedHelpersPreserveConstrainedGenericRelations():Void {
		final source = [
			"class Main {}",
			"class GenericReflection {",
			"  @:generic static function gf3<A:haxe.Constraints.Constructible<String -> Void>, B:Array<A>>(a:A, b:B):B {",
			"    var clone = new A(\"copy\");",
			"    b.push(clone);",
			"    return b;",
			"  }",
			"}"
		].join("\n");
		final helpers = ParserStageScanHelpers.scanModuleLocalHelperClasses(source, "Main");
		final genericReflection = findScannedClass(helpers, "GenericReflection");
		final gf3 = findFunction(genericReflection, "gf3");
		final metadata = HxFunctionDecl.getMetadata(gf3);
		assertTrue(metadata.indexOf("__hxhx_fn_type_params=A,B") >= 0, "scanned constrained gf3 type params should come from the source signature");
		assertTrue(metadata.indexOf("__hxhx_fn_type_constraint=A:haxe.Constraints.Constructible<String->Void>") >= 0,
			"scanned helpers should preserve the Constructible constraint for A");
		assertTrue(metadata.indexOf("__hxhx_fn_type_constraint=B:Array<A>") >= 0, "scanned helpers should preserve the relation between B and Array<A>");
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

		final keyValueIterator = findClass(decl, "ListKeyValueIterator");
		final next = findFunction(keyValueIterator, "next");
		assertListKeyValueIteratorNextShape(next, "ParserStage");

		final scannedHelpers = ParserStageScanHelpers.scanModuleLocalHelperClasses(listSource, "List");
		final scannedKeyValueIterator = findScannedClass(scannedHelpers, "ListKeyValueIterator");
		final scannedNext = findFunction(scannedKeyValueIterator, "next");
		assertListKeyValueIteratorNextShape(scannedNext, "ParserStageScanHelpers");
	}

	static function assertParserStripsUntypedReturnModifier():Void {
		final decl = ParserStage.parse("class BytesBuffer { public function getBytes():Bytes untyped { return null; } }", "BytesBuffer.hx").getDecl();
		final bytesBuffer = findClass(decl, "BytesBuffer");
		final getBytes = findFunction(bytesBuffer, "getBytes");
		assertEqString(HxFunctionDecl.getReturnTypeHint(getBytes), "Bytes", "ParserStage should not merge trailing untyped into the return type");
		final suffixDecl = ParserStage.parse("class BytesuntypedOwner { public function getBytes():Bytesuntyped { return null; } }", "BytesuntypedOwner.hx")
			.getDecl();
		final suffixOwner = findClass(suffixDecl, "BytesuntypedOwner");
		final suffixGetBytes = findFunction(suffixOwner, "getBytes");
		assertEqString(HxFunctionDecl.getReturnTypeHint(suffixGetBytes), "Bytesuntyped",
			"ParserStage should preserve return type names that only end with untyped");
	}

	static function assertScannedHelpersStripUntypedReturnModifier():Void {
		final source = [
			"class Main {}",
			"class BytesBuffer {",
			"  public function getBytes():Bytes",
			"    untyped { return null; }",
			"}",
			"class BytesuntypedOwner { public function getBytes():Bytesuntyped { return null; } }"
		].join("\n");
		final helpers = ParserStageScanHelpers.scanModuleLocalHelperClasses(source, "Main");
		final bytesBuffer = findScannedClass(helpers, "BytesBuffer");
		final getBytes = findFunction(bytesBuffer, "getBytes");
		assertEqString(HxFunctionDecl.getReturnTypeHint(getBytes), "Bytes", "scanned helpers should not merge trailing untyped into the return type");
		final suffixOwner = findScannedClass(helpers, "BytesuntypedOwner");
		final suffixGetBytes = findFunction(suffixOwner, "getBytes");
		assertEqString(HxFunctionDecl.getReturnTypeHint(suffixGetBytes), "Bytesuntyped",
			"scanned helpers should preserve return type names that only end with untyped");
	}

	static function main() {
		assertBootstrapSnapshotCarriesGenericMethodRepair();
		assertParserStripsUntypedReturnModifier();
		assertScannedHelpersStripUntypedReturnModifier();
		assertScannedGenericNamedFunctionArg();
		assertScannedHelpersPreserveConstrainedGenericRelations();

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
