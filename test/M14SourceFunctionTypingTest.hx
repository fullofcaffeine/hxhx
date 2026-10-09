/** Proves parsed source-function return ownership and exact declaration replay. */
class M14SourceFunctionTypingTest {
	static function parsedTracer():TypedExpr {
		final source = 'class SourceControlFixture { static function main():Void { var callback = function(item:String):Dynamic {'
			+ 'var result = { { return item; } "wrong"; }; State.events += "after"; return result; }; } }'
			+ 'class State { public static var events:String = ""; }';
		final parsed = ParserStage.parse(source, "SourceControlFixture.hx");
		final resolved = new ResolvedModule("SourceControlFixture", "SourceControlFixture.hx", parsed);
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]), null, true);
		return typed.getTypedClasses()[0].getFunctions()[0].getBody().getStatements()[0].getExpressions()[0];
	}

	static function typeBody(body:HxExpr, returnHint:String):TypedExpr {
		final parsed = ParserStage.parse("class SourceControlFixture { static function main():Void { var callback = 0; } }", "SourceControlFixture.hx");
		final declaration = HxClassDecl.getFunctions(HxModuleDecl.getMainClass(parsed.getDecl()))[0];
		final position = new HxPos(1, 1, 2);
		final facts = new HxSourceFunction({
			kind: Anonymous,
			placement: Value,
			arguments: ["item"],
			signature: new HxLambdaSignature([
				{
					typeHint: "String",
					isOptional: false,
					isRest: false,
					hasDefault: false
				}
			], returnHint)
		});
		HxFunctionDecl.getBody(declaration)[0] = SVar("callback", "", ESourceFunction(facts, body, [], position), position);
		final resolved = new ResolvedModule("SourceControlFixture", "SourceControlFixture.hx", parsed);
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]), null, true);
		return typed.getTypedClasses()[0].getFunctions()[0].getBody().getStatements()[0].getExpressions()[0];
	}

	static function reject(body:HxExpr, hint:String, diagnostic:String):Void {
		try {
			typeBody(body, hint);
		} catch (error:TyperError) {
			if (error.toString().indexOf(diagnostic) >= 0)
				return;
			throw error;
		}
		throw "source function accepted invalid return contract";
	}

	static function main():Void {
		final oldStrict = Sys.getEnv("HXHX_TYPER_STRICT");
		Sys.putEnv("HXHX_TYPER_STRICT", "1");
		final position = new HxPos(1, 1, 2);
		final typed = parsedTracer();
		if (typed.getTag() != SourceFunction
			|| typed.getControlTarget() == null
			|| typed.getType().getFunctionReturn().getDisplay() != "Dynamic")
			throw "source function lost its kind, return target, or written result";
		final sourceBody = typed.getExpressions()[0];
		if (sourceBody.getTag() != SourceGroup || !sourceBody.getType().isNoNormalCompletion() || sourceBody.getExpressions().length != 3)
			throw "source group lost abrupt completion or later syntax";
		final returned = sourceBody.getExpressions()[0].getExpressions()[0].getExpressions()[0].getExpressions()[0].getExpressions()[0];
		if (returned.getTag() != ReturnExpr || returned.getControlTarget() != typed.getControlTarget())
			throw "nested value block return targets another function";
		if (returned.getExpressions()[0].getLocalBindings()[0].getCanonicalIdentity() != typed.getLocalBindings()[0].getCanonicalIdentity())
			throw "source function return lost its exact parameter binding";
		reject(ESourceGroup([EInt(7)], position), "Int", "Missing return");
		reject(ESourceGroup([EReturn(EInt(7))], position), "Void", "lambda result");
		final quoted = typeBody(ESourceGroup([EMacroExpr(EReturn(EInt(7)), []), EReturn(null)], position), "Void");
		final quote = quoted.getExpressions()[0].getExpressions()[0];
		if (quote.getTag() != MacroExpr || quote.getExpressions()[0].getControlTarget() != null)
			throw "quoted return acquired an executing function target";
		switch TypedSourceSyntax.expression(quote.getExpressions()[0]) {
			case EReturn(EInt(7)):
			case _:
				throw "quoted return lost its authored value";
		}
		reject(ESourceGroup([EMacroExpr(EReturn(EInt(7)), [])], position), "Int", "Missing return");
		Sys.putEnv("HXHX_TYPER_STRICT", oldStrict == null ? "" : oldStrict);
		Sys.println("SOURCE_FUNCTION_TYPING:PASS");
	}
}
