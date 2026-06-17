import ParserStageScanHelpers;

class M14ParserStageScanExpressionBodyIntegrationTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function main():Void {
		final source = [
			"abstract LocalVector(Array<Int>) from Array<Int> {",
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

		var fillFn:Null<HxFunctionDecl> = null;
		for (fn in HxClassDecl.getFunctions(localVector)) {
			if (HxFunctionDecl.getName(fn) == "fill") {
				fillFn = fn;
				break;
			}
		}
		assertTrue(fillFn != null, "expected expression-bodied fill method to be retained");
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
	}
}
