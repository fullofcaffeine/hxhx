/** Field-owned capture plans preserve shared bindings, lexical parents, and exact revisions. */
class M14InitializerCapturePlanTest {
	static function initializers(source:String):Array<TypedFieldInitializer> {
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		return TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved])).getTypedClasses()[0].getFieldInitializers();
	}

	static function check(value:Bool, message:String):Void {
		if (!value)
			throw message;
	}

	static function expectFailure(fragment:String, action:Void->Void):Void {
		try {
			action();
		} catch (message:String) {
			if (message.indexOf(fragment) < 0)
				throw message;
			return;
		}
		throw "missing initializer capture rejection: " + fragment;
	}

	static function lowered(initializer:TypedFieldInitializer):Array<TypedExpr> {
		final result = TypedControlLowering.fieldInitializer(initializer);
		return result.value == null ? result.steps : result.steps.concat([result.value]);
	}

	/** An equal-looking closure from another projection cannot borrow capture ownership. */
	static function catalog():Void {
		final text = 'class Main { public var make:Int->(Void->Int) = function(value:Int):Void->Int {return function():Int {value=value+1;return value;};}; }';
		function project():TypedBackendFieldInitializerProjection {
			final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(text, "Main.hx"));
			final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved])).getTypedClasses()[0];
			return TypedBodySource.classProjection(typed).getFieldInitializers()[0];
		}
		final projected = project();
		final facts = projected.requireCaptureCatalog();
		check(facts == projected.requireCaptureCatalog(), "initializer rebuilt its capture catalog");
		check(facts.getExpressions().length == 2, "initializer lost a closure occurrence");
		check(facts.getPlan().sourceBodyRevision == projected.getBodyRevision(), "initializer catalog lost its source revision");
		final closure = facts.getExpressions()[1];
		final callable = facts.getCallableExpressions()[0];
		check(projected.findCallableExpression(callable.expression) == callable.source, "direct initializer lookup lost its exact callable source");
		check(project().findCallableExpression(callable.expression) == null, "direct initializer lookup borrowed another projection");
		check(projected.findCallableExpression(EIdent("make")) == null, "direct initializer lookup accepted reconstructed syntax");
		check(facts.require(closure).getCaptures().length == 1, "initializer catalog lost shared storage");
		expectFailure("not an exact occurrence", () -> facts.require(project().requireCaptureCatalog().getExpressions()[1]));
		expectFailure("another function or source revision", () -> facts.assertOwner(projected.getStableIdentity(), "changed"));
		switch closure {
			case ELambda(args, body, signature):
				final copy:HxExpr = ELambda(args.copy(), body, signature);
				expectFailure("not an exact occurrence", () -> facts.require(copy));
				switch body {
					case ELoweredControl(_, _, entries, _): entries.push(EInt(99));
					case _: throw "initializer closure was not lowered";
				}
			case _:
				throw "catalog returned a non-closure";
		}
		expectFailure("projection was mutated", () -> facts.getPlan());
		expectFailure("projection was mutated", () -> projected.findCallableExpression(callable.expression));
	}

	static function main():Void {
		catalog();
		final fields = initializers('class Main {
public var make:Int->({read:Void->Int, write:Void->Void}) = function(value:Int):{read:Void->Int, write:Void->Void} {
return {read:function():Int {return value;}, write:function():Void {value = value + 1;}};
};
public var other:Void->Int = function():Int {return 9;};
}');
		final source = fields[0];
		final original = CompilerTypedTreeRevision.expression(source.getField().getCanonicalKey(), source.getExpression());
		final plan = TypedCapturePlan.analyzeInitializer(source);
		check(plan.ownerIdentity == source.getField().getCanonicalKey(), "initializer borrowed a method owner");
		check(plan.bodyRevision == original, "initializer lost its exact authored revision");
		final functions = plan.getFunctions();
		check(functions.length == 4, "initializer root and three closures must remain distinct");
		check(functions[0].controlTargetIdentity == null, "initializer root gained a function return target");
		check(functions[2].parentIdentity == functions[1].identity && functions[3].parentIdentity == functions[1].identity,
			"sibling closures lost their creating function");
		final reader = functions[2].getCaptures();
		final writer = functions[3].getCaptures();
		check(reader.length == 1 && writer.length == 1, "initializer siblings lost their capture");
		check(reader[0].getCanonicalIdentity() == writer[0].getCanonicalIdentity(), "initializer siblings selected different cells");
		check(reader[0].getIdentity().getOwnerIdentity() == plan.ownerIdentity, "capture declaration has a foreign owner");
		check(plan.getBindings().length == 1
			&& plan.getBindings()[0].creation == FunctionEntry, "captured parameter lost its invocation allocation event");
		plan.assertInitializerCurrent(source);
		check(plan.getCanonicalIdentity() == TypedCapturePlan.analyzeInitializer(source).getCanonicalIdentity(), "initializer plan is unstable");
		final entries = lowered(source);
		final transferred = TypedCapturePlan.afterInitializerLowering(source, entries);
		transferred.assertInitializerCurrent(source, entries);
		check(transferred.sourceBodyRevision == original, "lowered initializer lost its source revision");
		check(transferred.getFunctions()[2].identity == functions[2].identity, "lowering changed the authored closure identity");
		check(transferred.getBindings()[0].binding.getCanonicalIdentity() == reader[0].getCanonicalIdentity(), "lowering replaced the captured binding");
		expectFailure("another typed initializer revision", () -> plan.assertInitializerCurrent(fields[1]));
		final changed = new TypedFieldInitializer(source.getField(), TypedExpr.intLiteral(1, TyType.fromHintText("Int"), HxPos.unknown()));
		expectFailure("another typed initializer revision", () -> plan.assertInitializerCurrent(changed));
		expectFailure("another typed initializer revision", () -> transferred.assertInitializerCurrent(source, []));
		expectFailure("authored function origin", () -> TypedCapturePlan.afterInitializerLowering(source, lowered(fields[1])));
		check(original == CompilerTypedTreeRevision.expression(source.getField().getCanonicalKey(), source.getExpression()),
			"analysis mutated the initializer");

		final block = initializers('class Main { public var next:Void->Int = {var value=10; function():Int {value=value+1;return value;};}; }')[0];
		final blockPlan = TypedCapturePlan.afterInitializerLowering(block, lowered(block));
		check(blockPlan.getBindings()[0].creation == Declaration && blockPlan.getFunctions()[1].getCaptures().length == 1,
			"initializer-local storage lost its declaration event");
		// Haxe rejects the future instance receiver even inside an initializer closure.
		// Legal initializer-local captures above must not authorize this access.
		var receiverDiagnostic = "";
		try {
			initializers('class Main { var value:Int; public var read:Void->Int = function():Int {return this.value;}; }');
		} catch (error:TyperError) {
			receiverDiagnostic = error.getMessage();
		}
		check(receiverDiagnostic == "Cannot access this or other member field in variable initialization",
			"initializer closure must reject access to its future receiver");
		Sys.println("INITIALIZER_CAPTURE_PLAN:PASS");
	}
}
