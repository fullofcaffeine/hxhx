/** Lowering must preserve closure origins while accounting for its actual executable locals. */
class M14TypedCaptureLoweringTest {
	static function typed(source:String):TypedFunction {
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		return TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved])).getTypedClasses()[0].getFunctions()[0];
	}

	static function check(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function names(bindings:Array<TyLocalBinding>):String
		return [for (binding in bindings) binding.getSourceName()].join(",");

	static function rejected(action:Void->Void, diagnostic:String):Void {
		var observed = "";
		try {
			action();
		} catch (error:String) {
			observed = error;
		}
		check(observed.indexOf(diagnostic) >= 0, "expected " + diagnostic + ", received " + observed);
	}

	/** Corrupt an immutable derived tree without changing the original source or hiding its revision. */
	static function replace(fn:TypedFunction, target:TypedExpr, replacement:TypedExpr):TypedFunction {
		function expression(node:TypedExpr):TypedExpr
			return node == target ? replacement : node.withExpressions([for (child in node.getExpressions()) expression(child)]);
		function statement(node:TypedStmt):TypedStmt
			return node.withChildren([for (child in node.getExpressions()) expression(child)], [for (child in node.getStatements()) statement(child)]);
		return fn.withBody(new TypedFunctionBody([for (node in fn.getBody().getStatements()) statement(node)], fn.getBody().getSourceFingerprint()));
	}

	public static function run():Void {
		final source = typed("class Main { static function make(seed:Int):Int->Int { var calls = seed; function count(n:Int):Int { calls++; return n == 0 ? calls : count(n-1); } return count; } }");
		final before = CompilerTypedTreeRevision.functionBody(source);
		final original = TypedCapturePlan.analyze(source);
		final lowered = TypedControlLowering.functionBody(source);
		final plan = TypedCapturePlan.afterLowering(source, lowered);
		check(names(plan.getFunctions()[1].getCaptures()) == "calls,count", "lowered recursion lost its exact captures");
		check(plan.getFunctions()[1].identity == original.getFunctions()[1].identity, "lowering replaced the authored closure identity");
		check(before == CompilerTypedTreeRevision.functionBody(source), "capture transfer changed the authored body");
		check(plan.bodyRevision == CompilerTypedTreeRevision.functionBody(lowered), "capture plan must bind the actual lowered revision");
		check(plan.sourceBodyRevision == before, "capture plan lost its authored input revision");
		final closure = plan.getFunctionExpressions()[0];
		check(plan.requireFunction(closure).identity == original.getFunctions()[1].identity, "exact occurrence lookup lost its origin");
		plan.getFunctionExpressions().pop();
		check(plan.getFunctionExpressions().length == 1, "occurrence getter exposed a mutable array");
		final rebuilt = TypedControlLowering.functionBody(source);
		final rebuiltPlan = TypedCapturePlan.afterLowering(source, rebuilt);
		rejected(() -> plan.requireFunction(rebuiltPlan.getFunctionExpressions()[0]), "not an exact occurrence");
		rejected(() -> plan.assertCurrent(source), "another typed function revision");
		check(plan.getCanonicalIdentity() == TypedCapturePlan.afterLowering(source, TypedControlLowering.functionBody(lowered)).getCanonicalIdentity(),
			"repeated lowering changed the capture plan");

		final relay = typed("class Main { static function make(seed:Int):Void->(Void->Int) { return function():Void->Int { return function():Int { return seed; }; }; } }");
		final relayLowered = TypedControlLowering.functionBody(relay);
		final relayPlan = TypedCapturePlan.afterLowering(relay, relayLowered);
		check(relayPlan.getFunctions()[1].getDirectCaptures().length == 0 && names(relayPlan.getFunctions()[1].getCaptures()) == "seed",
			"lowering lost a forwarded capture");
		final inner = relayPlan.getFunctionExpressions()[1];
		final moved = relayLowered.withBody(new TypedFunctionBody([TypedStmt.expressionStmt(inner, null)], relayLowered.getBody().getSourceFingerprint()));
		rejected(() -> TypedCapturePlan.afterLowering(relay, moved), "changed its lexical function parent");
		final outer = relayPlan.getFunctionExpressions()[0];
		final duplicated = relayLowered.withBody(new TypedFunctionBody([TypedStmt.expressionStmt(outer, null), TypedStmt.expressionStmt(outer, null)],
			relayLowered.getBody().getSourceFingerprint()));
		rejected(() -> TypedCapturePlan.afterLowering(relay, duplicated), "repeated function origin");
		final body = outer.getExpressions()[0];
		final lostOrigin = outer.withExpressions([
			TypedExpr.controlRegion(body.getExpressions(), body.getType(), body.getPosition())
		]);
		rejected(() -> TypedCapturePlan.afterLowering(relay, replace(relayLowered, outer, lostOrigin)), "exact function body origin");

		final loops = typed("class Main { static function make():Void { for (i in 0...3) { var local = i; var read = function():Int { return local + i; }; } } }");
		final loopPlan = TypedCapturePlan.afterLowering(loops, TypedControlLowering.functionBody(loops));
		var temporaries = 0;
		for (fact in loopPlan.getBindings()) {
			if (fact.binding.getKind() == CompilerTemporary) {
				temporaries++;
				check(fact.functionIdentity == loopPlan.getFunctions()[0].identity && fact.creation == Declaration,
					"range-bound temporary requires its actual enclosing function and declaration event");
			}
			if (fact.binding.getSourceName() == "i")
				check(fact.creation == LoopIteration, "lowered loop binding lost per-iteration creation");
		}
		check(temporaries == 2
			&& names(loopPlan.getFunctions()[1].getCaptures()) == "i,local", "range lowering changed captured local ownership");

		final dead = typed("class Main { static function make(seed:Int, unused:Int):Void->Int { return function():Int { return seed; var unreachable = function():Int { return unused; }; }; } }");
		check(TypedCapturePlan.analyze(dead).getFunctions().length == 3, "unreachable source closure is required for this test");
		final deadPlan = TypedCapturePlan.afterLowering(dead, TypedControlLowering.functionBody(dead));
		check(deadPlan.getFunctions().length == 2 && names(deadPlan.getFunctions()[1].getCaptures()) == "seed",
			"unreachable closure or its forwarding-only dependency survived executable analysis");
		final noCapture = typed("class Main { static function make(unused:Int):Void->Int { return function():Int { return 1; }; } }");
		final noCaptureLowered = TypedControlLowering.functionBody(noCapture);
		final noCapturePlan = TypedCapturePlan.afterLowering(noCapture, noCaptureLowered);
		final independent = noCapturePlan.getFunctionExpressions()[0];
		final independentBody = independent.getExpressions()[0];
		final unusedParameter = noCapturePlan.getBindings()[0].binding;
		final inserted = independentBody.withExpressions(independentBody.getExpressions().concat([
			TypedExpr.localRead(unusedParameter.getSourceName(), unusedParameter.getType(), null, unusedParameter)
		]));
		rejected(() -> TypedCapturePlan.afterLowering(noCapture, replace(noCaptureLowered, independentBody, inserted)), "new capture dependency");
		final temporary = new TyLocalBinding(TyLocalId.forCompilerTemporary(noCapture.getStableIdentity(), "capture-test", 0, "storage"), "storage",
			TyType.fromHintText("Int"), CompilerTemporary);
		final temporaryUse = independentBody.withExpressions(independentBody.getExpressions()
			.concat([TypedExpr.localRead("storage", temporary.getType(), null, temporary)]));
		final capturedTemporaryBody = replace(noCaptureLowered, independentBody, temporaryUse);
		final capturedTemporary = capturedTemporaryBody.withBody(new TypedFunctionBody([
			TypedStmt.variable("storage", "Int", TypedExpr.intLiteral(0, temporary.getType(), null), null, [], temporary)
		].concat(capturedTemporaryBody.getBody().getStatements()), capturedTemporaryBody.getBody().getSourceFingerprint()));
		rejected(() -> TypedCapturePlan.afterLowering(noCapture, capturedTemporary), "captured temporary");
		rejected(() -> noCapturePlan.assertCurrent(capturedTemporary), "another typed function revision");
		final withReceiver = typed("class Main { var value:Int; function make():Void->Int { return function():Int { return this.value + value; }; } }");
		final receiverPlan = TypedCapturePlan.afterLowering(withReceiver, TypedControlLowering.functionBody(withReceiver));
		check(receiverPlan.receiverOwner.getCanonicalName() == "Main" && receiverPlan.getFunctions()[1].capturesReceiver,
			"lowering lost explicit or implicit receiver dependencies");
		final quoted = typed("class Main { static function make():Void { var syntax = macro function(quoted:Int):Int { return quoted; }; } }");
		check(TypedCapturePlan.afterLowering(quoted, TypedControlLowering.functionBody(quoted)).getFunctions().length == 1,
			"quoted function entered the executable capture catalog");
		Sys.println("TYPED_CAPTURE_LOWERING:PASS");
	}

	static function main():Void
		run();
}
