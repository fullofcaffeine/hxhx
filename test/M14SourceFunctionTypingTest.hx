/** Proves parsed source-function return ownership and exact declaration replay. */
class M14SourceFunctionTypingTest {
	/** Reusing a solved function signature must also restore its lexical declaration. */
	static function namedBlockReplay():Void {
		final path = "test/fixtures/named_function_block_type/Main.hx";
		final parsed = ParserStage.parse(sys.io.File.getContent(path), path);
		final resolved = new ResolvedModule("Main", path, parsed);
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]), null, true);
		final fn = typed.getTypedClasses()[0].getFunctions()[0];
		final selected = fn.getBody().getStatements()[0].getExpressions()[0];
		if (selected.getTag() != SwitchExpr || selected.getExpressions()[1].getType().getSemanticKey() != "primitive:Bool")
			throw "named function replay lost the switch-arm block result type";
		for (functionBody in typed.getTypedClasses()[0].getFunctions())
			for (entry in TypedBodySource.functionProjection(functionBody).getLocalCatalog().getEntries())
				if (entry.getBinding().getType().hasUnknownComponent())
					throw "named function replay introduced incomplete local storage";
	}

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

	/** Whether no node below `node` is a return or carries a control destination. */
	static function controlFree(node:TypedExpr):Bool {
		if (node.getTag() == ReturnExpr || node.getControlTarget() != null)
			return false;
		for (child in node.getExpressions())
			if (!controlFree(child))
				return false;
		return true;
	}

	/** The lowered call `<owner>.<name>(...)`; this fixture loads no `haxe.macro.Expr`, so the callee spelling identifies it. */
	static function constructorCall(node:TypedExpr, name:String):TypedExpr {
		final callee = node.getTag() == Call ? node.getExpressions()[0] : null;
		if (callee == null || callee.getTag() != FieldRead || callee.getTexts()[0] != name)
			throw "quoted return: expected a lowered `" + name + "` construction";
		return node;
	}

	static function main():Void {
		namedBlockReplay();
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
		// The typer lowers a quotation to the construction of its `haxe.macro.Expr` value, so the
		// quoted `return` is the data `{expr: EReturn({expr: EConst(CInt("7"))}), pos}`, not a
		// return statement: nothing inside it may target the enclosing function.
		final quoted = typeBody(ESourceGroup([EMacroExpr(EReturn(EInt(7)), []), EReturn(null)], position), "Void");
		final group = quoted.getExpressions()[0];
		final quote = group.getExpressions()[0];
		if (quote.getTag() != Anonymous || quote.getTexts().join(",") != "expr,pos")
			throw "quoted return was not lowered to an Expr record";
		if (!controlFree(quote))
			throw "quoted return acquired an executing function target";
		final returned = constructorCall(quote.getExpressions()[0], "EReturn");
		final value = constructorCall(constructorCall(returned.getExpressions()[1].getExpressions()[0], "EConst").getExpressions()[1], "CInt");
		if (value.getExpressions()[1].getTag() != StringValue || value.getExpressions()[1].getTexts()[0] != "7")
			throw "quoted return lost its authored value";
		final real = group.getExpressions()[1];
		if (real.getTag() != ReturnExpr || real.getControlTarget() != quoted.getControlTarget())
			throw "the unquoted return no longer targets its function";
		reject(ESourceGroup([EMacroExpr(EReturn(EInt(7)), [])], position), "Int", "Missing return");
		Sys.putEnv("HXHX_TYPER_STRICT", oldStrict == null ? "" : oldStrict);
		Sys.println("SOURCE_FUNCTION_TYPING:PASS");
	}
}
