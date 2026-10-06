import hxhxmacrohost.api.RuntimeMacroExprs;

/** Keep every authored comprehension wrapper visible through the public runtime macro parser. */
class M14SourceComprehensionSyntaxTest {
	/** Quoted loops carry authored syntax, never executing loop targets or local bindings. */
	static function assertQuoted(expression:TypedExpr):Void {
		if (expression.getControlTarget() != null || expression.getLocalBindings().length != 0)
			throw "quoted comprehension acquired executing control or local ownership";
		for (child in expression.getExpressions())
			assertQuoted(child);
	}

	static function main():Void {
		final expected = ComprehensionContract.expected().split("\n");
		final sources = ComprehensionContract.sources();
		final failures = new Array<String>();
		for (index in 0...sources.length) {
			var actual = "";
			try {
				actual = ComprehensionContract.shape(RuntimeMacroExprs.parse(sources[index], null));
				final parsed = HxParser.parseCompleteExprText(sources[index]);
				final quoted = TypedBodyBuilder.buildExpression(EMacroExpr(parsed, []), HxPos.unknown(), null).getExpressions()[0];
				assertQuoted(quoted);
				final rebuilt = TypedSourceSyntax.expression(quoted);
				final rebuiltShape = ComprehensionContract.shape(@:privateAccess RuntimeMacroExprs.convert(rebuilt, null));
				if (rebuiltShape != actual || TypedBodyFingerprint.forExpression(parsed) != TypedBodyFingerprint.forExpression(rebuilt))
					throw "typed quotation changed comprehension source structure";
				switch parsed {
					case EArrayDecl([ESourceFor(_, _, _, position)]):
						if (position.index != 1 || position.line != 1 || position.column != 2)
							throw "comprehension lost its authored for position";
					case _:
						throw "comprehension is not an authored array containing a for loop";
				}
			} catch (error:haxe.Exception) {
				actual = "rejected: " + error.message;
			} catch (error:HxParseError) {
				actual = "rejected: " + error.toString();
			}
			if (actual != expected[index])
				failures.push(sources[index] + "\nexpected: " + expected[index] + "\nactual: " + actual);
		}
		if (failures.length > 0)
			throw failures.join("\n");
		Sys.println("SOURCE_COMPREHENSION_SYNTAX:PASS");
	}
}
