/** The signed lower bound must not inherit the lexer's unrepresentable positive-magnitude fallback. */
class M14MinimumIntLiteralTest {
	static function main():Void {
		for (source in ["-2147483648", "- 2147483648"]) {
			switch HxParser.parseCompleteExprText(source) {
				case EInt(value) if (value == -2147483647 - 1):
				case _:
					throw "minimum Int literal lost its exact signed value";
			}
		}
		switch HxParser.parseCompleteExprText("macro -2147483648") {
			case EMacroExpr(EInt(value), _) if (value == -2147483647 - 1):
			case _:
				throw "minimum Int macro quote differs from upstream CInt";
		}
		Sys.println("MINIMUM_INT_LITERAL:PASS");
	}
}
