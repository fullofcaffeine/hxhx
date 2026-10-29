import HxSourceFunction.HxSourceFunctionKind;
import HxSourceFunction.HxSourceFunctionPlacement;

/** Source groups, function kind, and defaults must survive typed rebuilds and invalidate revisions. */
class M14SourceFunctionStructureTest {
	static function facts(kind:HxSourceFunctionKind):HxSourceFunction {
		return new HxSourceFunction({
			kind: kind,
			placement: Value,
			arguments: ["item", "fallback"],
			signature: new HxLambdaSignature([
				{
					typeHint: "String",
					isOptional: false,
					isRest: false,
					hasDefault: false
				},
				{
					typeHint: "String",
					isOptional: false,
					isRest: false,
					hasDefault: true
				}
			], "Dynamic")
		});
	}

	static function requireDifferent(left:String, right:String, label:String):Void {
		if (left == right)
			throw label + " did not change the revision";
	}

	/** Leaf conversion is test-local; authored group and function mapping uses the shared production owner. */
	static function macroExpr(source:HxExpr):haxe.macro.Expr {
		final structural = HxSourceMacroSyntax.definition(source, macroExpr, name -> TPath({pack: [], name: name}));
		final definition:haxe.macro.Expr.ExprDef = structural != null ? structural : switch source {
			case EReturn(value): EReturn(value == null ? null : macroExpr(value));
			case EIdent(name): EConst(CIdent(name));
			case EString(value): EConst(CString(value));
			case _: throw "unexpected macro construction leaf";
		};
		return {expr: definition, pos: null};
	}

	static function main():Void {
		for (hint in ["Void->Int", "()->Int", " Void -> Int "])
			if (TyType.fromHintText(hint).getSemanticKey() != "function:()->primitive:Int")
				throw "zero-argument function type invented a Void input: " + hint;
		for (hint in ["(Void)->Int", "(value:Void)->Int"])
			if (TyType.fromHintText(hint).getFunctionArguments().length != 1
				|| !TyType.fromHintText(hint).getFunctionArguments()[0].isVoid())
				throw "explicit Void argument was discarded: " + hint;
		if (TyType.fromHintText("Void->Int->Int").getFunctionArguments().length != 2)
			throw "Void in a multi-argument function was discarded";
		final nestedCallable = TyType.fromHintText("Void->(Void->Int)");
		if (nestedCallable.getFunctionArguments().length != 0 || nestedCallable.getFunctionReturn().getFunctionArguments().length != 0)
			throw "nested zero-argument function type retained a Void input";
		final position = new HxPos(12, 2, 4);
		final anonymous = facts(Anonymous);
		final body = HxExpr.ESourceGroup([ESourceGroup([EReturn(EIdent("item"))], position), EString("later")], position);
		final source = HxExpr.ESourceFunction(anonymous, body, [EString("fallback")], position);
		switch macroExpr(source).expr {
			case EFunction(FAnonymous, fn):
				if (fn.args.length != 2 || fn.args[1].opt || fn.args[0].value != null)
					throw "macro mapping lost default absence or changed the optional marker";
				switch fn.args[1].value.expr {
					case EConst(CString("fallback", _)):
					case _: throw "macro mapping lost the authored default child";
				}
				switch fn.expr.expr {
					case EBlock([
						{expr: EBlock([{expr: EReturn({expr: EConst(CIdent("item"))})}])},
						{expr: EConst(CString("later", _))}
					]):
					case _: throw "macro mapping moved the return or later source entry";
				}
			case _:
				throw "macro mapping changed anonymous function kind";
		}
		final fingerprint = TypedBodyFingerprint.forExpression(source);
		final observed = new Array<String>();
		TypedBackendSourceWalk.expression(source, expression -> switch expression {
			case EIdent(name) | EString(name): observed.push(name);
			case _:
		});
		if (observed.join(",") != "item,later,fallback")
			throw "source walker skipped a body, unreachable entry, or default child";
		requireDifferent(fingerprint, TypedBodyFingerprint.forExpression(ESourceFunction(facts(Arrow), body, [EString("fallback")], position)),
			"function kind");
		requireDifferent(fingerprint, TypedBodyFingerprint.forExpression(ESourceFunction(anonymous, body, [ENull], position)), "default child");
		requireDifferent(TypedBodyFingerprint.forExpression(ESourceGroup([EInt(1), EInt(2)], position)),
			TypedBodyFingerprint.forExpression(EDiscardThen(EInt(1), EInt(2))), "source group versus sequence");

		final stringType = TyType.fromHintText("String");
		final typedBody = TypedExpr.sourceGroup([
			TypedExpr.sourceGroup([
				TypedExpr.returnExpr(TypedExpr.nameRead("item", stringType, position), TyType.noNormalCompletion(), position)
			], TyType.noNormalCompletion(), position),
			TypedExpr.stringLiteral("later", stringType, position)
		], stringType, position);
		final typed = TypedExpr.sourceFunctionExpr(anonymous, typedBody, [TypedExpr.stringLiteral("fallback", stringType, position)],
			TyType.fromHintText("(String, String)->Dynamic"), position);
		final revision = CompilerTypedTreeRevision.expression("source-function-test", typed);
		final typedArrow = TypedExpr.sourceFunctionExpr(facts(Arrow), typedBody, [TypedExpr.stringLiteral("fallback", stringType, position)], typed.getType(),
			position);
		requireDifferent(revision, CompilerTypedTreeRevision.expression("source-function-test", typedArrow), "typed function kind");
		final rebuilt = typed.withExpressions(typed.getExpressions()).withType(typed.getType()).withCatchUses([]);
		if (rebuilt.getSourceFunction() != anonymous
			|| rebuilt.getLambdaSignature() != anonymous.getSignature()
			|| rebuilt.getExpressions()[0].getTag() != SourceGroup
			|| CompilerTypedTreeRevision.expression("source-function-test", rebuilt) != revision)
			throw "immutable rebuild lost source function facts or grouping";
		final changed = typed.getExpressions();
		changed[1] = TypedExpr.nullValue(TyType.fromHintText("Dynamic"), position);
		requireDifferent(revision, CompilerTypedTreeRevision.expression("source-function-test", typed.withExpressions(changed)), "typed default child");
		var rejected = false;
		try {
			typed.withExpressions([typedBody]);
		} catch (error:haxe.Exception) {
			rejected = error.message.indexOf("default children differ") >= 0;
		}
		if (!rejected)
			throw "typed rebuild accepted a missing default child";
		final indexes = anonymous.getDefaultParameterIndexes();
		indexes[0] = 0;
		if (anonymous.getDefaultParameterIndexes()[0] != 1 || anonymous.getSignature().getParameters()[1].isOptional)
			throw "default index mutation or default/optional conflation";
		Sys.println("SOURCE_FUNCTION_STRUCTURE:PASS");
	}
}
