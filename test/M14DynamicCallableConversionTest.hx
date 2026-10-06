/** Compare native callback carrier conversion and factory evaluation with upstream Haxe. */
class M14DynamicCallableConversionTest {
	static function main():Void {
		argumentDestinations();
		final root = "test/fixtures/dynamic_callable_conversion";
		final expected = "15\n15\n15\nmake\napplyInt\n5\n6\nmake\nfalse\nmake\ntext\ntrue\nfalse\ntext\n5\n";
		if (run("node_modules/.bin/haxe", ["-cp", root, "--run", "Main"]) != expected)
			throw "upstream callable conversion contract differs";
		final path = root + "/Main.hx";
		final module = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		lambdaContracts(typed);
		JsRuntimeFixture.assertRuntime(typed, "Main", expected);
		final output = ".tmp/dynamic_callable_conversion_" + Date.now().getTime();
		final executable = EmitterStage.emitToDir(MacroStage.expandProgram([typed], []), output, true);
		if (run(executable, []) != expected)
			throw "native callable conversion differs; retained " + output;
		Sys.println("DYNAMIC_CALLABLE_CONVERSION:PASS artifacts=" + output);
	}

	/** Upstream keeps the body Dynamic while a call fixes the callable's concrete return contract. */
	static function lambdaContracts(typed:TypedModule):Void {
		final results = new Array<String>();
		for (cls in typed.getBackendProjection().getClasses())
			for (fn in cls.getFunctions())
				for (statement in fn.getBody())
					TypedBackendSourceWalk.statement(statement, expression -> {
						final facts = fn.findLambda(expression);
						if (facts == null || !facts.bodyType.isDynamic() || facts.callableType.getFunctionReturn().isDynamic())
							return;
						if (!facts.callableType.getFunctionArguments()[0].isDynamic())
							throw "context replaced an explicit Dynamic lambda parameter";
						results.push(facts.callableType.getFunctionReturn().getSemanticKey());
						switch expression {
							case ELambda(names, body, signature):
								if (fn.findLambda(ELambda(names.copy(), body, signature)) != null)
									throw "lambda return facts matched a foreign occurrence by shape";
								final original = names[0];
								names[0] = original + "_mutated";
								var rejected = false;
								try {
									fn.findLambda(expression);
								} catch (message:String) {
									if (message != "lambda occurrence changed after projection")
										throw message;
									rejected = true;
								}
								names[0] = original;
								if (!rejected) throw "lambda return facts survived projection mutation";
							case _: throw "lambda facts attached to another expression kind";
						}
					}, _ -> {});
		results.sort((left, right) -> left == right ? 0 : left < right ? -1 : 1);
		if (results.join(",") != "primitive:Bool,primitive:Int,primitive:String,primitive:Void")
			throw "contextual lambda contracts differ from upstream: " + results.join(",");
	}

	/** Omitted parameters and spread arrays must not borrow a neighboring scalar destination. */
	static function argumentDestinations():Void {
		final intType = TyType.fromHintText("Int");
		final signature = TyType.fromHintText("(?text:String,value:Int,...tail:Int)->Int");
		final callee = TypedExpr.nameRead("callback", signature, null);
		final first = TypedExpr.intLiteral(1, intType, null);
		final rest = TypedExpr.nameRead("values", TyType.nominal(new TyNominalTypeId("Array"), [intType]), null);
		final spread = TypedExpr.call(TypedExpr.nameRead("__hxhx_spread", TyType.unknown(), null), [rest], null, rest.getType(), null);
		for (retained in [false, true]) {
			final call = retained ? TypedExpr.functionValueCall(callee, [first, spread], intType,
				null) : TypedExpr.call(callee, [first, spread], null, intType, null);
			final destinations = TypedCallExpectedArguments.resolve(call);
			if (destinations.length != 2
				|| destinations[0] == null
				|| destinations[0].getSemanticKey() != intType.getSemanticKey()
				|| destinations[1] != null)
				throw "spread array received a scalar callback destination";
		}
		final invalid = TypedExpr.call(callee, [TypedExpr.nameRead("wrong", TyType.fromHintText("Bool"), null)], null, intType, null);
		if (TypedCallExpectedArguments.resolve(invalid)[0] != null)
			throw "rejected argument received a destination";
	}

	static function run(command:String, arguments:Array<String>):String {
		final process = new sys.io.Process(command, arguments);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0)
			throw "callback command failed: " + errors;
		return output;
	}
}
