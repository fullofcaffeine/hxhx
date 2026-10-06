import sys.io.File;

/** Prove callback context solves the original argument without replaying either operand. */
class M14CallbackArgumentContextTest {
	static function main():Void {
		final root = "test/fixtures/callback_argument_context";
		final expected = "receiver\noperand\ntrue\noperand\ntrue\n";
		final upstream = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "--run", "Main"]);
		final output = upstream.stdout.readAll().toString();
		final errors = upstream.stderr.readAll().toString();
		final code = upstream.exitCode();
		upstream.close();
		if (code != 0 || output != expected)
			throw "upstream callback contract differs: " + output + errors;
		final path = root + "/Main.hx";
		final module = new ResolvedModule("Main", path, ParserStage.parse(File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		JsRuntimeFixture.assertRuntime(typed, "Main", expected);
		rollback();
		parameterRollback();
		sourceSignatureRetention();
		conflictingArgument();
		Sys.println("CALLBACK_ARGUMENT_CONTEXT:PASS");
	}

	/** A first body constraint is speculative too; explicit Dynamic never becomes a fresh parameter hole. */
	static function parameterRollback():Void {
		final env = new TyFunctionEnv("parameter-rollback", [], [], TyType.unknown(), TyType.unknown());
		final parameter = env.declareLocal("value", TyType.unknown(), LambdaParameter);
		final expression:HxExpr = EIdent("value");
		final intType = TyType.fromHintText("Int");
		final stringType = TyType.fromHintText("String");
		final index = TyperIndex.build([]);
		if (env.getInference().constrain([expression, expression], [intType, stringType], env, index))
			throw "conflicting parameter contexts were accepted";
		if (!env.getInference().localType(parameter).isUnknown())
			throw "failed parameter transaction leaked its first context";
		if (!env.getInference().constrain([expression], [intType], env, index)
			|| env.getInference().localType(parameter).getSemanticKey() != intType.getSemanticKey())
			throw "valid body context did not infer the parameter after rollback";
		final explicit = env.declareLocal("explicit", TyType.fromHintText("Dynamic"), LambdaParameter);
		env.getInference().constrain([EIdent("explicit")], [intType], env, index);
		if (!env.getInference().localType(explicit).isDynamic())
			throw "parameter inference replaced explicit Dynamic";
	}

	/** A sealed source signature cannot be borrowed by an equal-looking node or survive source mutation. */
	static function sourceSignatureRetention():Void {
		final position = HxPos.unknown();
		final children:Array<HxExpr> = [EReturn(EInt(1))];
		final facts = new HxSourceFunction({
			kind: Anonymous,
			placement: Value,
			arguments: [],
			signature: new HxLambdaSignature([], "Int")
		});
		final source:HxExpr = ESourceFunction(facts, ESourceGroup(children, position), [], position);
		final inference = new TyFunctionInference("source-signature");
		final type = TyType.functionType([], TyType.fromHintText("Int"));
		inference.recordSourceFunction(source, type);
		if (inference.sourceFunctionType(source) != null)
			throw "mutable source inference reused a frozen signature";
		inference.seal([]);
		if (inference.sourceFunctionType(source).getSemanticKey() != type.getSemanticKey())
			throw "sealed source occurrence lost its signature";
		final foreign:HxExpr = ESourceFunction(facts, ESourceGroup(children, position), [], position);
		if (inference.sourceFunctionType(foreign) != null)
			throw "source signature matched by shape rather than occurrence";
		children.push(EReturn(EString("changed")));
		var rejected = false;
		try {
			inference.sourceFunctionType(source);
		} catch (message:String) {
			if (message != "source function changed after parameter inference")
				throw message;
			rejected = true;
		}
		if (!rejected)
			throw "source signature survived a changed function body";
	}

	/** Two individually valid parameter probes cannot commit conflicting uses of one variable. */
	static function rollback():Void {
		final env = new TyFunctionEnv("callback-rollback", [], [], TyType.unknown(), TyType.unknown());
		final expr:HxExpr = ENew("Container", []);
		final inferred = env.getInference().construct(expr, TyType.nominal(new TyNominalTypeId("Container"), []), 1);
		final callable = TyType.functionType([
			TyType.nominal(new TyNominalTypeId("Container"), [TyType.fromHintText("String")]),
			TyType.nominal(new TyNominalTypeId("Container"), [TyType.fromHintText("Int")])
		], TyType.fromHintText("Bool"));
		final signature = TyCallableSignature.fromFunctionValue(callable);
		final result = TyCallbackArgumentContext.resolve(signature, [expr, expr], [inferred, inferred], [Value, Value], env, TyperIndex.build([]));
		if (!result.match(Rejected(IncompatibleArgument(1, 1))))
			throw "callback accepted conflicting shared inference";
		if (!env.getInference().expressionType(expr, inferred, env).hasUnknownComponent())
			throw "failed callback alignment leaked an earlier parameter constraint";
		final callee:HxExpr = EIdent("callback");
		final single = TyCallableSignature.fromFunctionValue(TyType.functionType([callable.getFunctionArguments()[0]], TyType.fromHintText("Bool")));
		if (!TyCallbackArgumentContext.resolve(single, [expr], [inferred], [Value], env, TyperIndex.build([]), callee).match(Aligned(_)))
			throw "failed alignment poisoned a later compatible call";
		final binding = env.getInference().callbackBinding(callee);
		var rejected = false;
		try {
			binding.assertCurrent(single.getFunctionType(), [callable.getFunctionArguments()[1]], [Value]);
		} catch (message:String) {
			if (message != "call argument binding has a stale operand type or spread shape")
				throw message;
			rejected = true;
		}
		if (!rejected)
			throw "callback binding accepted a different concrete operand type";
	}

	/** Expected callback context must not overwrite an explicitly completed generic argument. */
	static function conflictingArgument():Void {
		final source = 'class Container<T>{public function new(){}}class Main{static function use(callback:Container<String>->Bool):Bool{return callback(new Container<Int>());}static function main(){}}';
		final root = ".tmp/callback_argument_context_invalid";
		sys.FileSystem.createDirectory(root);
		File.saveContent(root + "/Main.hx", source);
		final upstream = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "--run", "Main"]);
		upstream.stdout.readAll();
		final errors = upstream.stderr.readAll().toString();
		final code = upstream.exitCode();
		upstream.close();
		if (code == 0 || errors.indexOf("Int") < 0 || errors.indexOf("String") < 0)
			throw "upstream conflicting callback argument was not rejected";
		final module = new ResolvedModule("Main", root + "/Main.hx", ParserStage.parse(source, root + "/Main.hx"));
		var rejected = false;
		try {
			TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		} catch (error:TyperError) {
			rejected = true;
		}
		if (!rejected)
			throw "callback context overwrote an explicit Int argument";
	}
}
