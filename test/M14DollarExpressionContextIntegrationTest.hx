/** Distinguishes native dollar identifiers from macro splices through complete module parsing. */
class M14DollarExpressionContextIntegrationTest {
	static function returned(expression:String):HxExpr {
		final parsed = ParserStage.parse("class Main { static function sample() { return " + expression + "; } }", "Main.hx");
		for (declaration in HxModuleDecl.getClasses(parsed.getDecl()))
			for (method in HxClassDecl.getFunctions(declaration))
				if (HxFunctionDecl.getName(method) == "sample")
					for (statement in HxFunctionDecl.getBody(method))
						switch (statement) {
							case SReturn(value, _):
								return value;
							case _:
						}
		throw "module parser lost the returned expression";
	}

	static function main():Void {
		switch (returned("new Token()")) {
			case ENew("Token", []):
			case _:
				throw "ordinary constructor parsing changed";
		}
		switch (returned("untyped $new(null)")) {
			case EUntyped(ECall(EIdent("$new"), [ENull])):
			case _:
				throw "native allocation must retain the exact primitive call";
		}
		switch (returned("untyped $typeof(value)")) {
			case EUntyped(ECall(EIdent("$typeof"), [EIdent("value")])):
			case _:
				throw "ordinary native primitive names must not become macro splices";
		}
		switch (returned("macro $value")) {
			case EMacroExpr(ECall(EIdent("__hxhx_macro_expr_splice"), [EIdent("value")]), _):
			case _:
				throw "unbraced macro splice lost its expression identity";
		}
		switch (returned("macro untyped $new(null)")) {
			case EMacroExpr(ECall(ECall(EIdent("__hxhx_macro_expr_splice"), [EIdent("new")]), [ENull]), _):
			case _:
				throw "a quoted keyword name must remain a splice for later identifier validation";
		}
		switch (returned("[macro $value, untyped $new(null)]")) {
			case EArrayDecl([EMacroExpr(_, _), EUntyped(ECall(EIdent("$new"), [ENull]))]):
			case _:
				throw "macro quote context leaked into the following expression";
		}
		switch (returned("macro $e{untyped $new(null)}")) {
			case EMacroExpr(ECall(EIdent("__hxhx_macro_expr_splice"), [EUntyped(ECall(EIdent("$new"), [ENull]))]), _):
			case _:
				throw "splice payload must parse outside the quoted expression context";
		}
		var rejected = false;
		switch (returned("macro $e{macro $value}")) {
			case EMacroExpr(ECall(EIdent("__hxhx_macro_expr_splice"), [EMacroExpr(ECall(EIdent("__hxhx_macro_expr_splice"), [EIdent("value")]), _)]), _):
			case _:
				throw "a nested quote inside a splice payload must restore quote semantics";
		}
		switch (returned("macro [$e{value}, $other]")) {
			case EMacroExpr(EArrayDecl([
				ECall(EIdent("__hxhx_macro_expr_splice"), [EIdent("value")]),
				ECall(EIdent("__hxhx_macro_expr_splice"), [EIdent("other")])
			]), _):
			case _:
				throw "a splice payload must restore the surrounding quote context";
		}
		try {
			returned("$e{value}");
		} catch (_:HxParseError) {
			rejected = true;
		}
		if (!rejected)
			throw "braced reification outside a macro quote must fail";
		Sys.println("DOLLAR_EXPRESSION_CONTEXT:PASS");
	}
}
