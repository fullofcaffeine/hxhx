import sys.io.File;

/** Prove callback context solves the original argument without replaying either operand. */
class M14CallbackArgumentContextTest {
	static function main():Void {
		omittedMethodCallback();
		collectionContexts();
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
		genericMethodContexts();
		rollback();
		parameterRollback();
		omittedInputConversion();
		sourceSignatureRetention();
		conflictingArgument();
		Sys.println("CALLBACK_ARGUMENT_CONTEXT:PASS");
	}

	/** All callers constrain one declaration before its immutable parameter facts are published. */
	static function omittedMethodCallback():Void {
		final integer = "function(value:Int):Int return value + 1";
		final text = "function(value:String):String return value";
		final failures = new Array<String>();
		for (entry in [
			{
				name: "single",
				parameter: "listener",
				calls: [integer],
				accepted: true,
				reverse: false
			},
			{
				name: "receiver_after_caller",
				parameter: "listener",
				calls: [integer],
				accepted: true,
				reverse: true
			},
			{
				name: "repeated",
				parameter: "listener",
				calls: [integer, integer],
				accepted: true,
				reverse: false
			},
			{
				name: "callback_conflict",
				parameter: "listener",
				calls: [integer, text],
				accepted: false,
				reverse: false
			},
			{
				name: "scalar_conflict",
				parameter: "listener",
				calls: ["1", "\"text\""],
				accepted: false,
				reverse: false
			},
			{
				name: "written_string",
				parameter: "listener:String",
				calls: [integer],
				accepted: false,
				reverse: false
			},
			{
				name: "written_callback",
				parameter: "listener:Int->Int",
				calls: [text],
				accepted: false,
				reverse: false
			},
			{
				name: "unused_callback_input",
				parameter: "listener",
				calls: ["function(value):Void {}"],
				accepted: true,
				reverse: false
			},
			{
				name: "later_callback_input",
				parameter: "listener",
				calls: ["function(value):Int return 1", integer],
				accepted: true,
				reverse: false
			},
			{
				name: "later_local_input",
				parameter: "listener",
				calls: ["callback"],
				accepted: true,
				reverse: false
			},
			{
				name: "written_dynamic",
				parameter: "listener:Dynamic",
				calls: [integer, text],
				accepted: true,
				reverse: false
			}
		]) {
			final receiver = "class Receiver { public function new() {} public function add(" + entry.parameter + ") {} } ";
			final main = "class Main { static function main():Void { var receiver = new Receiver(); "
				+ (entry.name == "later_local_input" ? "var callback = function(value):Int return 1; " : "")
				+ entry.calls.map(callback -> "receiver.add(" + callback + ");").join(" ")
				+ (entry.name == "later_local_input" ? "callback(2); " : "")
				+ " Sys.println(\"accepted\"); } }";
			final source = entry.reverse ? main + receiver : receiver + main;
			final root = JsRuntimeFixture.reserveOutput();
			final path = root + "/Main.hx";
			File.saveContent(path, source);
			final upstream = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "--run", "Main"]);
			final output = upstream.stdout.readAll().toString();
			final errors = upstream.stderr.readAll().toString();
			final code = upstream.exitCode();
			upstream.close();
			if (entry.accepted ? code != 0 || output != "accepted\n" : code == 0 || errors.length == 0)
				throw "upstream omitted method callback contract differs: " + entry.name + output + errors;
			Sys.println("OMITTED_CALLBACK_UPSTREAM:PASS " + entry.name);
			final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
			var typed:Null<TypedModule> = null;
			var diagnostic = "";
			try {
				typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
			} catch (error:TyperError) {
				diagnostic = Std.string(error);
			} catch (error:haxe.Exception) {
				// An internal publication failure is not a valid source diagnostic.
				failures.push(entry.name + ": internal failure: " + error.message);
			}
			if (entry.accepted) {
				if (typed == null) {
					failures.push(entry.name + ": " + diagnostic);
				} else {
					// Checking the declaration itself catches a per-call substitution
					// that leaves an earlier published method with an Unknown input.
					var found = false;
					for (cls in typed.getTypedClasses())
						for (fn in cls.getFunctions())
							if (HxFunctionDecl.getName(fn.getSourceDeclaration()) == "add") {
								found = true;
								final actual = fn.getEnvironment().getParams()[0].getType();
								final expected = entry.name == "unused_callback_input" ? TyType.fromHintText("Int->Void")
									.withFunctionTypes([TyType.unknown()],
										TyType.fromHintText("Void")) : TyType.fromHintText(entry.parameter == "listener:Dynamic" ? "Dynamic" : "Int->Int");
								if (actual.getSemanticKey() != expected.getSemanticKey())
									failures.push(entry.name + ": published input is " + actual.getDisplay());
							}
					if (!found)
						throw "omitted callback observer lost the add declaration";
					JsRuntimeFixture.assertRuntime(typed, "Main", "accepted\n");
				}
			} else if (typed != null) {
				failures.push(entry.name + ": incompatible callers were accepted");
			}
			@:privateAccess JsRuntimeFixture.removeOutput(root);
		}
		if (failures.length > 0)
			throw "omitted method callback failures:\n" + failures.join("\n");
	}

	/** Only complete collection contexts agreed by every candidate can guide first-pass typing. */
	static function collectionContexts():Void {
		final integer = TyType.fromHintText("Int");
		final string = TyType.fromHintText("String");
		final array = new TyNominalTypeId("Array");
		final ints = TyType.nominal(array, [integer]);
		final strings = TyType.nominal(array, [string]);
		final map = TyType.nominal(new TyNominalTypeId("haxe.ds.Map"), [string, integer]);
		final method = new TyTypeParameterId("collection-method", 0, "T");
		function signature(type:TyType, rest:Bool = false):TyFunSig {
			return new TyFunSig("take", true, ["values"], [type], [false], [rest], TyType.fromHintText("Void"), HxPos.unknown());
		}
		for (type in [ints, map]) {
			final context = TyCallArgumentContext.shared([signature(type), signature(type)], 1)[0];
			if (context == null || context.getSemanticKey() != type.getSemanticKey())
				throw "agreed collection context was lost";
		}
		for (signatures in [
			[signature(ints), signature(strings)],
			[signature(ints), signature(map)],
			[signature(TyType.nominal(array, [TyType.unknown()]))],
			[signature(TyType.fromHintText("Array<Int>"))],
			[signature(ints, true)]
		])
			if (TyCallArgumentContext.shared(signatures, 1)[0] != null)
				throw "ambiguous, open, unresolved, or rest collection context escaped selection";
		if (TyCallArgumentContext.shared([signature(TyType.nominal(array, [TyType.typeParameter(method)]))], 1, [[method]])[0] != null)
			throw "method inference variable became a rigid collection annotation";
		if (TyCallArgumentContext.shared([signature(ints)], 0).length != 0)
			throw "omitted collection invented a source context";
	}

	/** A receiver fixes callback inputs even while the method result remains inferable. */
	static function genericMethodContexts():Void {
		for (explicit in [false, true]) {
			final source = 'class Box<T> { public var item:T; public function new(item:T) {this.item=item;} '
				+ 'public function transform<S>(f:T->S):S {return f(item);} } '
				+ 'class Main { static function run(box:Box<{label:String}>):String {return box.transform('
				+ (explicit ? '(c:{label:String})' : 'c')
				+ ' -> c.label);} '
				+ 'static function main() {Sys.println(run(new Box({label:"ok"})));}}';
			final root = JsRuntimeFixture.reserveOutput();
			final path = root + '/Main.hx';
			File.saveContent(path, source);
			final upstream = new sys.io.Process('node_modules/.bin/haxe', ['-cp', root, '--run', 'Main']);
			final output = upstream.stdout.readAll().toString();
			final errors = upstream.stderr.readAll().toString();
			final code = upstream.exitCode();
			upstream.close();
			if (code != 0 || output != 'ok\n')
				throw 'upstream generic callback differs: ' + output + errors;
			final module = new ResolvedModule('Main', path, ParserStage.parse(source, path));
			JsRuntimeFixture.assertRuntime(TyperStage.typeResolvedModule(module, TyperIndex.build([module])), 'Main', 'ok\n');
			if (!explicit)
				for (callback in ['c -> c.absent', 'c -> 7', '(c:Int) -> "wrong"']) {
					final invalid = StringTools.replace(source, 'c -> c.label', callback);
					File.saveContent(path, invalid);
					final oracle = new sys.io.Process('node_modules/.bin/haxe', ['-cp', root, '--run', 'Main']);
					oracle.stdout.readAll();
					final diagnostic = oracle.stderr.readAll().toString();
					final status = oracle.exitCode();
					oracle.close();
					if (status == 0 || diagnostic.length == 0)
						throw 'upstream accepted invalid callback: ' + callback;
					final rejected = new ResolvedModule('Main', path, ParserStage.parse(invalid, path));
					var failed = false;
					try {
						TyperStage.typeResolvedModule(rejected, TyperIndex.build([rejected]));
					} catch (_:TyperError) {
						failed = true;
					} catch (error:haxe.Exception) {
						if (error.message.indexOf('selected call conversion does not satisfy its retained parameter:') < 0)
							throw error;
						failed = true;
					}
					if (!failed)
						throw 'context accepted invalid callback: ' + callback;
				}
		}
		final caller = new TyTypeParameterId('context-caller', 0, 'T');
		final method = new TyTypeParameterId('context-method', 0, 'T');
		final callerType = TyType.typeParameter(caller);
		final methodType = TyType.typeParameter(method);
		function signature(input:TyType, result:TyType):TyFunSig {
			return new TyFunSig('transform', true, ['callback'], [TyType.functionType([input], result)], [false], [false], result, HxPos.unknown());
		}
		final generic = signature(callerType, methodType);
		final context = TyCallArgumentContext.shared([generic], 1, [[method]])[0];
		if (context == null
			|| context.getFunctionArguments()[0].getSemanticKey() != callerType.getSemanticKey()
			|| !context.getFunctionReturn().isUnknown())
			throw 'generic context confused equally named caller and method binders';
		if (generic.getArgs()[0].getFunctionReturn().getSemanticKey() != methodType.getSemanticKey())
			throw 'callback context mutated the declaration';
		if (TyCallArgumentContext.shared([signature(methodType, methodType)], 1, [[method]])[0] != null)
			throw 'an open method input became a rigid callback annotation';
		if (TyCallArgumentContext.shared([generic, signature(TyType.fromHintText('Int'), methodType)], 1, [[method], [method]])[0] != null)
			throw 'overload disagreement supplied a callback context';
		if (TyCallArgumentContext.shared([generic], 0, [[method]]).length != 0)
			throw 'omitted argument invented a source context';
	}

	/** Optional omission preserves input facts; only the selected Dynamic slot receives a value conversion after sealing. */
	static function omittedInputConversion():Void {
		final dynamicType = TyType.fromHintText("Dynamic");
		final signature = TyCallableSignature.fromFunctionValue(TyType.functionSignature([
			{
				name: "value",
				type: dynamicType,
				isOptional: false,
				isRest: false,
				metadata: []
			},
			{
				name: "label",
				type: TyType.fromHintText("String"),
				isOptional: true,
				isRest: false,
				metadata: []
			}
		], dynamicType));
		final index = TyperIndex.build([]);
		for (later in [false, true]) {
			final env = new TyFunctionEnv("omitted-callback-input", [], [], TyType.unknown(), TyType.unknown());
			final parameter = env.declareLocal("value", TyType.unknown(), LambdaParameter);
			env.getInference().registerOmittedParameter(parameter);
			final source:HxExpr = EIdent("value");
			final callee:HxExpr = EIdent("callback");
			final result = TyCallbackArgumentContext.resolve(signature, [source], [TyType.unknown()], [Value], env, index, callee);
			switch result {
				case Aligned(slots):
					if (!slots[0].match(Supplied(0)) || !slots[1].match(Omitted))
						throw "omitted input changed optional callback selection";
				case Rejected(failure):
					throw "omitted callback input was rejected: " + Std.string(failure);
			}
			if (!env.getInference().localType(parameter).isUnknown() || env.getInference().callbackBinding(callee) != null)
				throw "callback selection finalized an omitted input early";
			final integer = TyType.fromHintText("Int");
			if (later && !env.getInference().constrain([source], [integer], env, index))
				throw "Dynamic callback destination prevented a later Int constraint";
			env.getInference().seal([parameter]);
			final binding = env.getInference().callbackBinding(callee);
			if (binding.getOperandTypes()[0].getSemanticKey() != (later ? integer : dynamicType).getSemanticKey())
				throw "callback binding lost its final value conversion";
			if (!later && !parameter.getType().isUnknown())
				throw "callback conversion replaced the omitted declaration type";
			if (!TyCallbackArgumentContext.resolve(signature, [source], [parameter.getType()], [Value], env, index, callee).match(Aligned(_)))
				throw "callback replay lost the retained conversion and slots";
		}
		final missing = new TyFunctionEnv("missing-callback-fact", [], [], TyType.unknown(), TyType.unknown());
		missing.declareLocal("value", TyType.unknown(), Variable);
		if (!TyCallbackArgumentContext.resolve(signature, [EIdent("value")], [TyType.unknown()], [Value], missing, index).match(Rejected(_)))
			throw "missing local type facts forged an omitted-input conversion";
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
		inference.recordSourceFunction(source, type, []);
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
		if (env.getInference().callbackBinding(callee) != null)
			throw "callback published a binding before inference completed";
		env.getInference().seal([]);
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
