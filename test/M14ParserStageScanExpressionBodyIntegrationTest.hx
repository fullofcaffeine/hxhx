import ParserStageScanHelpers;

class M14ParserStageScanExpressionBodyIntegrationTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function main():Void {
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
