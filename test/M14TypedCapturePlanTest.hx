/** Capture facts follow lexical declarations and descendant construction, without changing source trees. */
class M14TypedCapturePlanTest {
	static function typed(source:String):Array<TypedFunction> {
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		return TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved])).getTypedClasses()[0].getFunctions();
	}

	static function names(bindings:Array<TyLocalBinding>):String
		return [for (binding in bindings) binding.getSourceName()].join(",");

	static function check(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	public static function run():Void {
		M14TypedCaptureStaticMethodTest.run();
		final counter = typed("class Main { static function make():Int->Int { var calls = 0; function count(n:Int):Int { calls++; return n == 0 ? calls : count(n-1); } return count; } }")[0];
		final before = CompilerTypedTreeRevision.functionBody(counter);
		final plan = TypedCapturePlan.analyze(counter);
		final functions = plan.getFunctions();
		check(functions.length == 2, "counter must contain one root and one closure");
		check(names(functions[1].getCaptures()) == "calls,count", "counter must capture the scalar and exact recursive declaration");
		check(functions[1].namedBinding.getKind() == NamedFunction, "recursive binding must retain its read-only declaration role");
		check(functions[1].controlTargetIdentity == counter.getBody().getStatements()[1].getExpressions()[0].getControlTarget().getCanonicalIdentity(),
			"capture occurrence must retain the exact authored function target");
		for (fact in plan.getBindings()) {
			final parameter = fact.binding.getSourceName() == "n";
			check(fact.functionIdentity == functions[parameter ? 1 : 0].identity, "nested parameters and enclosing declarations have different owners");
			check(parameter ? fact.creation == FunctionEntry : fact.creation == Declaration, "binding allocation event differs from declaration role");
		}
		check(before == CompilerTypedTreeRevision.functionBody(counter), "capture analysis mutated the typed body");
		check(plan.getCanonicalIdentity() == TypedCapturePlan.analyze(counter).getCanonicalIdentity(), "repeated capture analysis changed identity");
		functions[1].getCaptures().pop();
		check(functions[1].getCaptures().length == 2, "capture getter exposed a mutable array");
		plan.assertCurrent(counter);

		final relay = typed("class Main { static function relay(seed:Int):Void->(Void->Int) { return function():Void->Int { return function():Int { return seed; }; }; } }")[0];
		final relayed = TypedCapturePlan.analyze(relay).getFunctions();
		check(relayed.length == 3, "relay must contain all three executable scopes");
		check(relayed[1].getDirectCaptures().length == 0
			&& names(relayed[1].getCaptures()) == "seed", "middle function must forward a capture it never reads");
		check(names(relayed[2].getDirectCaptures()) == "seed" && relayed[2].parentIdentity == relayed[1].identity,
			"inner capture must retain its lexical parent");

		final shadowed = typed("class Main { static function make(x:Int):Int->(Void->Int) { return function(x:Int):Void->Int { return function():Int { return x; }; }; } }")[0];
		final shadowPlan = TypedCapturePlan.analyze(shadowed);
		final shadowFunctions = shadowPlan.getFunctions();
		check(shadowFunctions[1].getCaptures().length == 0, "inner parameter must not capture a same-spelled root parameter");
		final selected = shadowFunctions[2].getCaptures()[0];
		check(selected.getKind() == LambdaParameter, "inner function must select the nearest parameter identity");
		check(shadowPlan.getBindings()[1].binding.getIdentity().equals(selected.getIdentity()), "shadowed capture was selected by spelling");
		var stale = false;
		try {
			plan.assertCurrent(relay);
		} catch (error:String) {
			stale = error.indexOf("another typed function revision") >= 0;
		}
		check(stale, "a plan accepted another function");
		stale = false;
		final changed = counter.withBody(new TypedFunctionBody([], counter.getBody().getSourceFingerprint()));
		try {
			plan.assertCurrent(changed);
		} catch (error:String) {
			stale = error.indexOf("another typed function revision") >= 0;
		}
		check(stale, "a plan accepted a replaced body under the same function identity");

		final loops = typed("class Main { static function make():Void { var values = []; for (i in 0...3) { var local = i; values.push(function():Int { return local + i; }); } } }")[0];
		final loopPlan = TypedCapturePlan.analyze(loops);
		check(names(loopPlan.getFunctions()[1].getCaptures()) == "i,local", "loop closure lost the iteration and body-local bindings");
		for (fact in loopPlan.getBindings()) {
			if (fact.binding.getSourceName() == "i")
				check(fact.creation == LoopIteration, "for binding must receive an instance per iteration");
			if (fact.binding.getSourceName() == "local")
				check(fact.creation == Declaration, "body-local allocation must remain at declaration execution");
		}
		final quoted = typed("class Main { static function make():Void { var syntax = macro function(quoted:Int):Int { return quoted; }; } }")[0];
		final quotePlan = TypedCapturePlan.analyze(quoted);
		check(quotePlan.getFunctions().length == 1
			&& quotePlan.getBindings().length == 1, "quoted functions must not introduce runtime scopes or captures");
		final receiverFunctions = typed("class Main { var value:Int; function read():Int { return value; } function make():Void->(Void->Int) { return function():Void->Int { return function():Int { return this.value + value + read(); }; }; } }");
		final receiverPlan = TypedCapturePlan.analyze(receiverFunctions[1]);
		final receiverScopes = receiverPlan.getFunctions();
		check(receiverPlan.receiverOwner != null && receiverPlan.receiverOwner.getCanonicalName() == "Main",
			"receiver ownership must retain its resolved class");
		check(!receiverScopes[1].directReceiver && receiverScopes[1].capturesReceiver, "middle closure must forward the receiver without a direct use");
		check(receiverScopes[2].directReceiver && receiverScopes[2].capturesReceiver, "inner explicit and implicit receiver reads require capture");
		check(!receiverScopes[0].capturesReceiver, "root method owns its receiver rather than capturing it");
		final writer = typed("class Main { static function make():Void->Void { var state = 0; return function():Void { state = 1; }; } }")[0];
		check(names(TypedCapturePlan.analyze(writer).getFunctions()[1].getDirectCaptures()) == "state", "assignment-only capture was omitted");
		Sys.println("TYPED_CAPTURE_PLAN:PASS");
	}

	static function main():Void
		run();
}
