import ParserStageScanHelpers;

/** Checks that helper declaration scanning preserves source bodies and following members. */
class M14ParserStageScanExpressionBodyIntegrationTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function main():Void {
		final calls = ParserStageScanHelpers.scanModuleLocalHelperClasses([
			"class CallBodies {",
			"  static function qualified():Void Sys.println(\"qualified\");",
			"  static function bare():Void qualified();",
			"  static function result():Int return 17;",
			"  static function conditional(value:Bool):Void { if (value) qualified(); }",
			"}"
		].join("\n"), null);
		assertTrue(calls.length == 1, "expected the call-expression helper class");
		final methods = HxClassDecl.getFunctions(calls[0]);
		assertTrue(methods.length == 4, "expression bodies must not consume following declarations");
		assertTrue(HxFunctionDecl.getReturnTypeHint(methods[0]) == "Void", "qualified body call must not become return-type text");
		assertTrue(HxFunctionDecl.getBodyText(methods[0]) == 'Sys.println("qualified");', "retain the qualified call body");
		assertTrue(HxFunctionDecl.getBodyText(methods[1]) == "qualified();", "retain the bare call body");
		assertTrue(HxFunctionDecl.getBodyText(methods[2]) == "return 17;", "retain the following return body");
		switch (HxFunctionDecl.getBody(methods[3])) {
			case [HxStmt.SIf(_, _, _, _)]:
			case _:
				throw "a structured static body must not require a final return statement";
		}
		for (scrutinee in ["items", "({values: items}).values"]) {
			final text = "class SwitchBody { static function run(items:Array<Int>):Void switch "
				+ scrutinee
				+ " { case [0, x] | [x, 0]: Sys.println(x); case _: Sys.println(-1); } static function after():Int return 9; }";
			final scanned = ParserStageScanHelpers.scanModuleLocalHelperClasses(text, null)[0];
			final parsed = HxModuleDecl.getMainClass(ParserStage.parse(text, "SwitchBody.hx").getDecl());
			for (cls in [scanned, parsed]) {
				final functions = HxClassDecl.getFunctions(cls);
				assertTrue(functions.length == 2, "switch body consumed the following function");
				assertTrue(HxFunctionDecl.getReturnTypeHint(functions[0]) == "Void", "switch text entered the return type");
				assertTrue(StringTools.startsWith(HxFunctionDecl.getBodyText(functions[0]), "switch "), "switch prefix disappeared");
				switch HxFunctionDecl.getBody(functions[0]) {
					case [HxStmt.SSwitch(_, patterns, bodies, position)]:
						assertTrue(patterns.length == 2 && bodies.length == 2, "switch cases disappeared");
						assertTrue(position.getIndex() == text.indexOf("switch "), "switch source position changed");
					case _:
						throw "unbraced switch did not remain a complete statement";
				}
			}
		}

		final typeCases = [
			{hint: "T", body: "@:privateAccess { return value; }"},
			{hint: "Array<Array<Int>>", body: "@:privateAccess { return [[1]]; }"},
			{hint: "Void->Void", body: "@:privateAccess { return callback; }"},
			{hint: "{value:Int}", body: "@:privateAccess { return {value: 1}; }"},
			{hint: "Void", body: '/* body boundary */ Sys.println("ok");'},
			{hint: "Array<Array<Int>>", body: "return [[1]];"},
			{hint: "Void->Void", body: "return callback;"},
			{hint: "{value:Int}", body: "return {value: 1};"},
			{hint: "haxe.io.Bytes", body: "return null;"}
		];
		for (testCase in typeCases) {
			final text = "class TypeBoundary { static function probe():"
				+ testCase.hint
				+ " "
				+ testCase.body
				+ " static function after():Int return 9; }";
			final scanned = ParserStageScanHelpers.scanModuleLocalHelperClasses(text, null)[0];
			final parsed = HxModuleDecl.getMainClass(new HxParser(text).parseModule("TypeBoundary"));
			for (cls in [scanned, parsed]) {
				final functions = HxClassDecl.getFunctions(cls);
				assertTrue(functions.length == 2, "return type must not consume the following method: " + testCase.hint);
				assertTrue(HxFunctionDecl.getReturnTypeHint(functions[0]) == testCase.hint, "preserve the complete type: " + testCase.hint);
				assertTrue(HxFunctionDecl.getBody(functions[0]).length > 0, "retain the body after type: " + testCase.hint);
				if (StringTools.startsWith(testCase.body, "@:privateAccess")) {
					assertTrue(HxFunctionDecl.getBodyText(functions[0]) == testCase.body, "retain exact body metadata text");
					switch HxFunctionDecl.getBody(functions[0]) {
						case [HxStmt.SExpr(HxExpr.EPrivateAccess(_, position), _)]:
							assertTrue(position.getIndex() == text.indexOf("@:privateAccess"), "retain body permission source position");
						case _:
							throw "return type scanning erased the body permission";
					}
				}
			}
		}

		final source = [
			"abstract LocalVector<T>(Array<T>) from Array<T> {",
			"  inline public function fill(value:Int):Void for (i in 0...this.length) this[i] = value;",
			"}"
		].join("\n");
		final classes = ParserStageScanHelpers.scanModuleLocalHelperAbstracts(source, null);
		var localVector:Null<HxClassDecl> = null;
		for (cls in classes) {
			if (HxClassDecl.getName(cls) == "LocalVector") {
				localVector = cls;
				break;
			}
		}
		assertTrue(localVector != null, "expected helper abstract scanner to discover LocalVector");
		assertTrue(HxClassDecl.getMetadata(localVector).indexOf("__hxhx_type_params=T") >= 0, "expected helper abstract scanner to retain type parameters");

		var fillFn:Null<HxFunctionDecl> = null;
		for (fn in HxClassDecl.getFunctions(localVector)) {
			if (HxFunctionDecl.getName(fn) == "fill") {
				fillFn = fn;
				break;
			}
		}
		assertTrue(fillFn != null, "expected expression-bodied fill method to be retained");
		assertTrue(HxFunctionDecl.getMetadata(fillFn).indexOf("inline") >= 0, "expected helper abstract scanner to retain the inline modifier");
		assertTrue(HxFunctionDecl.getBodyText(fillFn) == "for (i in 0...this.length) this[i] = value;",
			"expected scanner to start the body after the return type hint");

		switch (HxFunctionDecl.getBody(fillFn)) {
			case [
				HxStmt.SForIn("i", HxExpr.ERange(HxExpr.EInt(0), HxExpr.EField(HxExpr.EThis, "length")),
					HxStmt.SExpr(HxExpr.EBinop("=", HxExpr.EArrayAccess(HxExpr.EThis, HxExpr.EIdent("i")), HxExpr.EIdent("value")), _), _)
			]:
			case [HxStmt.SExpr(HxExpr.EUnsupported(raw), _)]:
				throw "expression-bodied for assignment parsed as unsupported: " + raw;
			case _:
				throw "expected expression-bodied for assignment to parse into a for-in array-access assignment";
		}

		final returnedBlockSource = [
			"class ShapeTools {",
			"  static function make(info:Dynamic, inputs:Array<Dynamic>):Dynamic",
			"    return {",
			"      var owner = info.owner;",
			"      {",
			"        owner: owner,",
			"        label: info.label,",
			"        params: [for (item in inputs) wrap(item)],",
			"      }",
			"    }",
			"}",
		].join("\n");
		final returnedBlockClasses = ParserStageScanHelpers.scanModuleLocalHelperClasses(returnedBlockSource, null);
		assertTrue(returnedBlockClasses.length == 1, "expected returned-block helper class to be retained");
		var makeFn:Null<HxFunctionDecl> = null;
		for (fn in HxClassDecl.getFunctions(returnedBlockClasses[0]))
			if (HxFunctionDecl.getName(fn) == "make")
				makeFn = fn;
		assertTrue(makeFn != null, "expected returned-block function to be retained");
		assertTrue(StringTools.startsWith(HxFunctionDecl.getBodyText(makeFn), "return {"), "returned block should retain its source-level return boundary");
		assertTrue(!ParserStageScanHelpers.hasUnsupportedStmtList(HxFunctionDecl.getBody(makeFn)),
			"returned block and its array comprehension should remain structural");
		switch (HxFunctionDecl.getBody(makeFn)) {
			case [HxStmt.SReturn(_, _)]:
			case _:
				throw "expected returned block to remain one return statement";
		}

		final typedefSource = [
			"typedef LikeStatus = {",
			"  var expectedValue:Dynamic;",
			"  var actualValue:Dynamic;",
			"  var error:String;",
			"  var path:String;",
			"  var recursive:Bool;",
			"}"
		].join("\n");
		final typedefs = ParserStageScanHelpers.scanModuleLocalHelperTypedefs(typedefSource, null);
		assertTrue(typedefs.length == 1, "expected one structural typedef helper");
		final status = typedefs[0];
		assertTrue(HxClassDecl.getName(status) == "LikeStatus", "expected LikeStatus helper typedef");
		final fields = HxClassDecl.getFields(status);
		assertTrue(fields.length == 5, "expected LikeStatus structural fields to be retained");
		assertTrue(HxFieldDecl.getName(fields[0]) == "expectedValue" && HxFieldDecl.getTypeHint(fields[0]) == "Dynamic",
			"expected Dynamic expectedValue field");
		assertTrue(HxFieldDecl.getName(fields[4]) == "recursive"
			&& HxFieldDecl.getTypeHint(fields[4]) == "Bool", "expected Bool recursive field");

		final optionalTypedefSource = [
			"typedef MetadataDescription = {",
			"  final metadata:String;",
			"  final doc:String;",
			"  @:optional final links:Array<String>;",
			"  @:optional final params:Array<String>;",
			"  @:optional final platforms:Array<Platform>;",
			"  @:optional final targets:Array<MetadataTarget>;",
			"}"
		].join("\n");
		final optionalTypedefs = ParserStageScanHelpers.scanModuleLocalHelperTypedefs(optionalTypedefSource, null);
		assertTrue(optionalTypedefs.length == 1, "expected optional metadata structural typedef helper");
		final optionalFields = HxClassDecl.getFields(optionalTypedefs[0]);
		assertTrue(optionalFields.length == 6, "expected metadata structural fields to be retained");
		assertTrue(HxFieldDecl.getName(optionalFields[0]) == "metadata", "expected metadata field");
		assertTrue(HxFieldDecl.getName(optionalFields[1]) == "doc", "expected doc field");
		assertTrue(HxFieldDecl.getName(optionalFields[2]) == "links", "expected @:optional links field name");
		assertTrue(HxFieldDecl.getName(optionalFields[3]) == "params", "expected @:optional params field name");
		assertTrue(HxFieldDecl.getName(optionalFields[4]) == "platforms", "expected @:optional platforms field name");
		assertTrue(HxFieldDecl.getName(optionalFields[5]) == "targets", "expected @:optional targets field name");
		for (field in optionalFields)
			assertTrue(HxFieldDecl.getName(field) != "optional", "metadata name should not become a typedef field name");

		final shiftedInitializerSource = [
			"abstract ShiftedBits(Int) {",
			"  private static var mask = (17 >>> 2) | (3 << 4);",
			"  @:op(~A) private function complement():ShiftedBits;",
			"  private function intentionallyEmpty():Void {}",
			"}",
		].join("\n");
		final shiftedAbstracts = ParserStageScanHelpers.scanModuleLocalHelperAbstracts(shiftedInitializerSource, null);
		assertTrue(shiftedAbstracts.length == 1, "expected abstract after shift-heavy static initializer to be retained");
		var complement:Null<HxFunctionDecl> = null;
		for (fn in HxClassDecl.getFunctions(shiftedAbstracts[0]))
			if (HxFunctionDecl.getName(fn) == "complement")
				complement = fn;
		assertTrue(complement != null, "bit shifts in a static initializer must not hide a later bodyless function");
		assertTrue(HxFunctionDecl.getMetadata(complement).indexOf("op(~A)") >= 0,
			"bodyless operator declaration should retain its metadata after a shift-heavy initializer");
		assertTrue(!HxFunctionDecl.getHasBody(complement), "semicolon declaration should retain target-native bodyless status");
		var intentionallyEmpty:Null<HxFunctionDecl> = null;
		for (fn in HxClassDecl.getFunctions(shiftedAbstracts[0]))
			if (HxFunctionDecl.getName(fn) == "intentionallyEmpty")
				intentionallyEmpty = fn;
		assertTrue(intentionallyEmpty != null && HxFunctionDecl.getHasBody(intentionallyEmpty),
			"an intentionally empty braced function must not be mistaken for target-native behavior");

		final parsedShiftedModule = ParserStage.parse(shiftedInitializerSource, "ShiftedBits.hx");
		var parsedComplement:Null<HxFunctionDecl> = null;
		for (cls in HxModuleDecl.getClasses(parsedShiftedModule.getDecl()))
			if (HxClassDecl.getName(cls) == "ShiftedBits")
				for (fn in HxClassDecl.getFunctions(cls))
					if (HxFunctionDecl.getName(fn) == "complement")
						parsedComplement = fn;
		assertTrue(parsedComplement != null, "ParserStage enrichment must retain bodyless declarations after shift-heavy static initializers");
		assertTrue(!HxFunctionDecl.getHasBody(parsedComplement), "ParserStage enrichment changed bodyless declaration status");
	}
}
