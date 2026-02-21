class M14HihExprTextParserIntegrationTest {
	static function fail(msg:String):Void {
		throw msg;
	}

	static function assertTrue(ok:Bool, msg:String):Void {
		if (!ok)
			fail(msg);
	}

	static function main() {
		// Native parser payloads can compact escaped quote strings to `"""`.
		// This should still parse as a normal string literal (`"`).
		final denseArrayRaw = '[" ".code,"(".code,")".code,"%".code,"!".code,"^".code,""".code,"<".code,">".code,"&".code,"|".code,"\\n".code,"\\r".code,",".code,";".code]';
		final denseArrayExpr = HxParser.parseExprText(denseArrayRaw);
		switch (denseArrayExpr) {
			case EArrayDecl(values):
				assertTrue(values.length == 15, "expected 15 array elements");
				switch (values[6]) {
					case EField(EString(v), "code"):
						assertTrue(v == "\"", 'expected index 6 to be quote char, got "' + v + '"');
					case _:
						fail("expected index 6 to parse as quote-char .code access");
				}
			case _:
				fail("expected dense quote payload to parse as EArrayDecl");
		}

		// Block-expression initializers should not degrade to EUnsupported when they
		// appear in dense native payload text with trailing tokens.
		final denseBlockRaw = '{varh=newhaxe.ds.StringMap();h.set("quot",""");h;}staticpublicfunctionparse(){}';
		final denseBlockExpr = HxParser.parseExprText(denseBlockRaw);
		switch (denseBlockExpr) {
			case ETryCatchRaw(raw):
				assertTrue(raw == "opaque_block_expr", "expected opaque block marker");
			case EUnsupported(raw):
				fail("dense block payload parsed as unsupported: " + raw);
			case _:
				fail("dense block payload should parse as opaque block expression");
		}
	}
}
