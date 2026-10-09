import haxe.macro.Expr;

/** Preserve for bindings and authored bodies before iterator typing or execution lowering. */
class M14SourceForSyntaxTest {
	static function convert(source:HxExpr):Expr {
		final mapped = HxSourceMacroSyntax.definition(source, convert, _ -> null);
		final definition:ExprDef = mapped != null ? mapped : switch source {
			case EIdent(name): EConst(CIdent(name));
			case EBool(value): EConst(CIdent(value ? "true" : "false"));
			case EField(object, field): EField(convert(object), field);
			case EBinop("==", left, right): EBinop(OpEq, convert(left), convert(right));
			case EReturn(value): EReturn(value == null ? null : convert(value));
			case _: throw "unexpected source-for fixture leaf";
		};
		return {expr: definition, pos: null};
	}

	public static function run():Void {
		final source = HxParser.parseCompleteExprText("for (entry in entries) if (entry.name == name) return true");
		switch convert(source).expr {
			case EFor({expr: EBinop(OpIn, {expr: EConst(CIdent("entry"))}, {expr: EConst(CIdent("entries"))})}, {
				expr: EIf({expr: EBinop(OpEq, {expr: EField({expr: EConst(CIdent("entry"))}, "name")}, {expr: EConst(CIdent("name"))})},
					{expr: EReturn({expr: EConst(CIdent("true"))})}, null)
			}):
			case _:
				throw "source for changed the public macro return structure";
		}
		final keyed = HxParser.parseCompleteExprText("for (key => value in values) value");
		switch convert(keyed).expr {
			case EFor({
				expr: EBinop(OpArrow, {expr: EConst(CIdent("key"))}, {
					expr: EBinop(OpIn, {expr: EConst(CIdent("value"))}, {expr: EConst(CIdent("values"))})
				})
			}, {expr: EConst(CIdent("value"))}):
			case _:
				throw "key/value for bindings lost their authored shape";
		}
		final valueOnly = HxParser.parseCompleteExprText("for (value in values) value");
		final quoted = TypedBodyBuilder.buildExpression(EMacroExpr(valueOnly, []), HxPos.unknown(), null).getExpressions()[0];
		if (quoted.getTag() != SourceFor || quoted.getControlTarget() != null || quoted.getLocalBindings().length != 0)
			throw "quoted for acquired an executing loop or runtime declaration";
		if (TypedBodyFingerprint.forExpression(TypedSourceSyntax.expression(quoted)) != TypedBodyFingerprint.forExpression(valueOnly))
			throw "quoted for changed its authored iterable or body";
		if (TypedBodyFingerprint.forExpression(valueOnly) == TypedBodyFingerprint.forExpression(keyed))
			throw "for binding kinds collided in the source fingerprint";
		final visited = new Array<String>();
		TypedBackendSourceWalk.expression(valueOnly, expression -> switch expression {
			case EIdent(name): visited.push(name);
			case _:
		});
		if (visited.join(",") != "values,value")
			throw "source-for traversal changed iterable/body order";
		switch HxParser.parseCompleteExprText("for (index in 0...3) index") {
			case ESourceFor(Value("index"), ERange(EInt(0), EInt(3)), EIdent("index"), _):
			case _:
				throw "source for lost a range iterable";
		}
		for (malformed in ["for (value values) value", "for (value in values)", "for (key => in values) key"]) {
			var rejected = false;
			try {
				HxParser.parseCompleteExprText(malformed);
			} catch (_:HxParseError) {
				rejected = true;
			}
			if (!rejected)
				throw "malformed for was accepted: " + malformed;
		}
		Sys.println("SOURCE_FOR_SYNTAX:PASS");
	}

	static function main():Void
		run();
}
