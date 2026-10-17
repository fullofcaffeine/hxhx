import backend.cpp.CppManagedStoragePlan;
import backend.cpp.CppManagedClosureAbi;
import backend.cpp.CppManagedEnvironmentEmitter;
import backend.cpp.CppManagedCallEmitter;
import backend.cpp.CppManagedCallEmitter.CppManagedCallOperands;
import backend.cpp.CppManagedEnvironmentEmitter.CppManagedEnvironmentConstruction;
import backend.cpp.CppManagedCellEmitter;
import backend.cpp.CppManagedParameterEmitter;
import backend.cpp.CppManagedFunctionBody;
import backend.cpp.CppManagedLocalAccess;
import backend.cpp.CppManagedRootedExpression;

/** Cell selection must retain declaration identity, creation timing, and exact closure ownership. */
class M14CppManagedStoragePlanTest {
	static function projection(source:String):TypedBackendFunctionProjection {
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved])).getTypedClasses()[0].getFunctions()[0];
		return TypedBodySource.functionProjection(typed);
	}

	static function check(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function rejected(action:Void->Void, diagnostic:String):Void {
		var observed = "";
		try {
			action();
		} catch (error:haxe.Exception) {
			observed = error.message;
		}
		check(observed.indexOf(diagnostic) >= 0, "expected " + diagnostic + ", received " + observed);
	}

	/** Equal text, replaced children, and another lexical owner cannot authorize aggregate storage. */
	static function aggregates():Void {
		final source = "class Main { static function test():Void { final record = {name: 'same'}; } }";
		final projected = projection(source);
		final value = switch projected.getBody()[0] {
			case SVar(_, _, value, _): value;
			case _: throw "aggregate fixture lost its declaration";
		};
		final occurrence = projected.requireAggregate(value);
		check(occurrence.getType().isAnonymous() && occurrence.getChildTypes()[0].getSemanticKey() == "primitive:String",
			"aggregate lost its exact child type");
		rejected(() -> projected.requireAggregate(EAnon(["name"], [EString("same")])), "not an exact occurrence");
		rejected(() -> projection(source).requireAggregate(value), "not an exact occurrence");
		switch value {
			case EAnon(_, values):
				values[0] = EString("same");
			case _:
				throw "aggregate fixture lost its record";
		}
		rejected(() -> projected.requireAggregate(value), "children were replaced");
		final unresolved = projection("class Main { static function test():Void { final values = [1]; } }");
		rejected(() -> new backend.cpp.CppManagedFunctionEmitter({
			projection: unresolved,
			rootSymbol: "unresolved",
			symbolPrefix: "hxhx_function_unresolved"
		}).render(), "managed value transfer requires complete types");
		final nested = projection("class Main { static function test():Void { final child = function() { return {name: 'nested'}; }; } }");
		final closure = nested.requireCaptureCatalog().getExpressions()[0];
		var childAggregate:Null<HxExpr> = null;
		function visit(expression:HxExpr):Void {
			switch expression {
				case EAnon(_, _):
					childAggregate = expression;
				case _:
			}
			TypedBackendSourceWalk.expressionChildren(expression, visit);
		}
		visit(closure);
		if (childAggregate == null)
			throw "nested fixture lost its aggregate";
		final access = new CppManagedLocalAccess({
			projection: nested,
			plan: new CppManagedStoragePlan(nested),
			owner: Root(nested),
			parameters: [],
			temporaryPrefix: "hxhx_parameters_aggregate_"
		});
		rejected(() -> access.aggregate(childAggregate), "not an exact expression");
	}

	/** Unassigned declarations need checked slots; scalar patterns cannot invent bindings. */
	static function controlResults():Void {
		final uninitialized = projection("class Main { static function test():Void { var result:Int; } }");
		final rendered = new backend.cpp.CppManagedFunctionEmitter({
			projection: uninitialized,
			rootSymbol: "method",
			symbolPrefix: "hxhx_function_uninitialized"
		}).render();
		check(rendered.indexOf("hxhx::managed::LocalSlot ") >= 0, "unassigned source local lost its checked storage state");
		function render(patterns:Array<HxSwitchPattern>, type:TyType):Void {
			backend.cpp.CppManagedSwitch.render({
				value: EInt(1),
				type: type,
				patterns: patterns,
				heap: "heap",
				prefix: "hxhx_switch_test_",
				renderValue: (_, _, _) -> [],
				renderBody: (_, _) -> []
			}, "");
		}
		rejected(() -> render([PBind("value")], TyType.fromHintText("Int")), "exact matching or binding support");
		rejected(() -> render([PInt(1)], TyType.fromHintText("Bool")), "exact matching or binding support");
		rejected(() -> render([PInt(1)], TyType.fromHintText("Null<Bool>")), "exact matching or binding support");
		rejected(() -> render([PBool(false)], TyType.fromHintText("Null<Int>")), "exact matching or binding support");
		rejected(() -> render([PWildcard, PWildcard], TyType.fromHintText("Int")), "repeats its default arm");
		rejected(() -> render([PWildcard], TyType.fromHintText("Dynamic")), "exact supported scalar type");
	}

	public static function run():Void {
		recordReads();
		controlResults();
		aggregates();
		staticCalls();
		functionEmission();
		rootFunction();
		final stringType = TyType.fromHintText("String");
		final stringAbi = new CppManagedClosureAbi(TyType.functionType([stringType], stringType));
		check(stringAbi.result == RootedResult && stringAbi.getParameters()[0].storage == RootedParameter,
			"String transport must retain null separately from empty text");
		declaredLocals();
		for (name in ["Bool", "Int", "Float"]) {
			final type = TyType.fromHintText(name);
			final abi = new CppManagedClosureAbi(TyType.functionType([type], type), false);
			check(abi.result == DirectResult
				&& abi.getParameters()[0].storage == DirectParameter, "a known owned leaf acquired managed transport");
		}
		final unresolved = TyType.functionType([], TyType.unresolved("Missing", []));
		rejected(() -> new CppManagedClosureAbi(unresolved), "complete semantic types");
		rejected(() -> new CppManagedClosureAbi(TyType.functionType([TyType.nullable(TyType.unknown())], TyType.fromHintText("Void"))),
			"complete semantic types");
		final dynamicAbi = new CppManagedClosureAbi(TyType.functionType([TyType.fromHintText("Dynamic")], TyType.fromHintText("Dynamic")));
		check(dynamicAbi.result == RootedResult && dynamicAbi.getParameters()[0].storage == RootedParameter,
			"erased values cannot be classified as pointer-free");
		final source = "class Main { static function make():Int->Int { var unused = 7; var calls = 0; function count(n:Int):Int { calls++; return n == 0 ? calls : count(n-1); } return count; } }";
		final projected = projection(source);
		final plan = new CppManagedStoragePlan(projected);
		final cells = plan.getCells();
		check([for (cell in cells) cell.source.binding.getSourceName()].join(",") == "calls,count",
			"cell selection included uncaptured locals or lost recursion");
		check(cells[0].mode == SharedBinding && cells[1].mode == InitializeOnce,
			"named functions and ordinary bindings require distinct initialization policies");
		check(cells[0].source.creation == Declaration
			&& cells[1].source.creation == Declaration, "declaration cells moved to function entry");
		final cellEmitter = new CppManagedCellEmitter(plan, cells[0].source.binding);
		rejected(() -> cellEmitter.renderAllocation("heap", "cell", cells[1].source), "exact source event");
		check(plan.requireCell(cells[0].source.binding) == cells[0], "cell lookup copied the promoted declaration");
		final expression = projected.requireCaptureCatalog().getExpressions()[0];
		final closure = plan.requireClosure(expression);
		final bodyEmitter = new CppManagedFunctionBody(plan, Closure(expression));
		final localAccess = new CppManagedLocalAccess({
			projection: projected,
			plan: plan,
			owner: Closure(expression),
			parameters: ["argument"],
			temporaryPrefix: "hxhx_parameters_access_",
			environmentName: "hxhx_env_counter",
			environmentSymbol: "environment"
		});
		final parameterName = projected.getLocalCatalog().projectedName(closure.getParameters()[0].binding);
		check(localAccess.render(EIdent(parameterName), "hxhx::managed::Value").indexOf("hxhx_parameters_access_value0") >= 0
			&& localAccess.parameters.render("heap").indexOf("argument") >= 0,
			"local access lost its rooted scalar parameter");
		rejected(() -> localAccess.render(EIdent(parameterName), "bool"), "typed Boolean local");
		rejected(() -> localAccess.render(EInt(1), "std::int32_t"), "projected local read");
		rejected(() -> new CppManagedLocalAccess({
			projection: projection(source),
			plan: plan,
			owner: Closure(expression),
			parameters: ["argument"],
			temporaryPrefix: "hxhx_parameters_foreign_",
			environmentName: "hxhx_env_counter",
			environmentSymbol: "environment"
		}), "not an exact occurrence");
		rejected(() -> bodyEmitter.render(null, null, null), "rooted return requires a stable destination");
		final parameters = new CppManagedParameterEmitter(plan, Closure(expression), ["argument"], "hxhx_parameters_test_");
		check(closure.getParameters().length == 1 && closure.getParameters()[0].binding.getSourceName() == "n",
			"managed closure lost its exact parameter identity");
		rejected(() -> parameters.cellReference(closure.getParameters()[0].binding), "not captured by a descendant");
		rejected(() -> parameters.value(cells[0].source.binding), "not a parameter");
		switch parameters.place(closure.getParameters()[0].binding) {
			case LocalRoot(name):
				check(name == "hxhx_parameters_test_value0", "parameter write lost its rooted scalar storage");
			case _:
				throw "function-value parameter did not retain common rooted transport";
		}
		rejected(() -> localAccess.place(cells[1].source.binding), "cannot be reassigned");
		rejected(() -> new CppManagedParameterEmitter(plan, Closure(expression), [], "hxhx_parameters_test_"), "disagree with source arity");
		final environment = new CppManagedEnvironmentEmitter(plan, expression, "hxhx_env_counter");
		final call = new CppManagedCallEmitter(plan, expression);
		final operands:CppManagedCallOperands = {
			heap: "heap",
			calleeSetup: [],
			callee: "select()",
			arguments: [{setup: [], value: "argument()"}],
			destination: "result",
			temporaryPrefix: "hxhx_call_test_"
		};
		check(call.render(operands) == call.render(operands), "repeated call emission changed");
		rejected(() -> call.render({
			heap: "heap",
			calleeSetup: [],
			callee: "select()",
			arguments: [],
			destination: "result",
			temporaryPrefix: "hxhx_call_test_"
		}), "every adapted source argument");
		rejected(() -> call.render({
			heap: "heap",
			calleeSetup: [],
			callee: "select()",
			arguments: [{setup: [], value: "argument()"}],
			temporaryPrefix: "hxhx_call_test_"
		}), "destination disagrees");
		check(environment.cellField(cells[0].source.binding) == "captured.cell0"
			&& environment.cellField(cells[1].source.binding) == "captured.cell1",
			"environment lost deterministic binding slots");
		rejected(() -> environment.receiverField(), "does not capture a receiver");
		check(environment.render() == new CppManagedEnvironmentEmitter(plan, expression, "hxhx_env_counter").render(),
			"environment output changes across repeated planning");
		final construction:CppManagedEnvironmentConstruction = {
			heap: "heap",
			destination: "result",
			entry: "entry",
			temporaryPrefix: "hxhx_construct_test_",
			captures: [
				{binding: cells[1].source.binding, reference: "selfCell"},
				{binding: cells[0].source.binding, reference: "callsCell"}
			]
		};
		final constructed = environment.renderConstruction(construction);
		check(constructed.indexOf("(callsCell)") < constructed.indexOf("(selfCell)"),
			"construction selected capture slots from input array order instead of exact identities");
		rejected(() -> environment.renderConstruction({
			heap: "heap",
			destination: "result",
			entry: "entry",
			temporaryPrefix: "hxhx_construct_test_",
			captures: [
				{binding: cells[0].source.binding, reference: "one"},
				{binding: cells[0].source.binding, reference: "two"}
			]
		}), "repeats a captured binding");
		rejected(() -> environment.renderConstruction({
			heap: "heap",
			destination: "result",
			entry: "entry",
			temporaryPrefix: "hxhx_construct_test_",
			captures: []
		}), "exactly its captured cells");
		check(closure.abi.result == RootedResult
			&& closure.abi.getParameters().length == 1
			&& closure.abi.getParameters()[0].storage == RootedParameter,
			"scalar function value lost null-preserving transport");
		check(closure.abi.getHiddenParameters().length == 3, "function value requires heap, environment, and result root");
		check(closure.abi.nativeSignature() == "void(hxhx::managed::Root<hxhx::managed::Value>&, hxhx::managed::Value)",
			"common scalar signature changed source arity or root order");
		check(closure.getCells()[0] == cells[0] && closure.getCells()[1] == cells[1], "recursive environment copied cell plans");
		cells.pop();
		closure.getCells().pop();
		check(plan.getCells().length == 2 && closure.getCells().length == 2, "plan exposes mutable storage inventories");
		final repeated = new CppManagedStoragePlan(projected);
		check([for (cell in repeated.getCells()) cell.source.getCanonicalIdentity()].join(";") == [for (cell in plan.getCells()) cell.source.getCanonicalIdentity()].join(";"),
			"repeated planning changes allocation origins");
		rejected(() -> plan.requireClosure(projection(source).requireCaptureCatalog().getExpressions()[0]), "not an exact occurrence");

		final relay = projection("class Main { static function make(seed:Int):Void->(Void->Int) { return function():Void->Int { final unused = 1; return function():Int { return seed; }; }; } }");
		final relayPlan = new CppManagedStoragePlan(relay);
		final closures = relay.requireCaptureCatalog().getExpressions();
		final relayAccess = new CppManagedLocalAccess({
			projection: relay,
			plan: relayPlan,
			owner: Closure(closures[0]),
			parameters: [],
			temporaryPrefix: "hxhx_parameters_relay_",
			environmentName: "hxhx_env_relay",
			environmentSymbol: "environment"
		});
		final rooted = new CppManagedRootedExpression({
			owner: CallableBody(relayAccess),
			heap: "heap",
			temporaryPrefix: "hxhx_value_relay_",
			resolve: value -> {expression: value, environmentName: "hxhx_env_child", entrySymbol: "childEntry"}
		});
		check(rooted.render(closures[1], "result", "").join("\n") == rooted.render(closures[1], "result", "").join("\n"),
			"closure literal emission changed across repeated rendering");
		rejected(() -> rooted.render(closures[0], "result", ""), "another lexical parent");
		rejected(() -> rooted.render(EArrayDecl([]), "result", ""), "not an exact expression");
		rejected(() -> rooted.renderControlValue(EInt(1), "bool"), "not an exact expression");
		// Reach the Boolean type check with an actual owned Int occurrence. A
		// fabricated literal must fail ownership before it can test source types.
		var ownedInt:Null<HxExpr> = null;
		TypedBackendSourceWalk.expression(closures[0], value -> {
			switch value {
				case EInt(1): ownedInt = value;
				case _:
			}
		});
		check(ownedInt != null, "relay fixture lost its owned integer expression");
		rejected(() -> rooted.renderControlValue(ownedInt, "bool"), "requires Bool or nullable Bool");
		rejected(() -> rooted.render(EBinop("+", EBool(true), EInt(1)), "result", ""), "exact Int or nullable Int operands");
		final wrongLink = new CppManagedRootedExpression({
			owner: CallableBody(relayAccess),
			heap: "heap",
			temporaryPrefix: "hxhx_value_wrong_",
			resolve: _ -> {expression: closures[0], environmentName: "hxhx_env_child", entrySymbol: "childEntry"}
		});
		rejected(() -> wrongLink.render(closures[1], "result", ""), "exact emitted entry link");
		check(relayPlan.requireClosure(closures[0]).abi.result == RootedResult
			&& relayPlan.requireClosure(closures[0]).abi.getHiddenParameters().length == 3,
			"returned closure requires a caller-owned result root");
		check(relay.requireCaptureCatalog()
			.requireCallableType(closures[0])
			.getSemanticKey() == relayPlan.requireClosure(closures[0])
			.abi.signature.getSemanticKey(),
			"ABI lost the exact typed callable signature");
		check(relayPlan.getCells().length == 1
			&& relayPlan.getCells()[0].source.creation == FunctionEntry, "parameter cell must belong to each invocation");
		check(relayPlan.requireClosure(closures[0]).getCells()[0] == relayPlan.requireClosure(closures[1]).getCells()[0],
			"transitive forwarding lost the shared location");

		final loop = new CppManagedStoragePlan(projection("class Main { static function make():Void { var values = []; for (i in 0...3) { var local = i; values.push(function():Int { return local + i; }); } } }"));
		check(loop.getCells()[0].source.creation == LoopIteration && loop.getCells()[1].source.creation == Declaration,
			"iteration and body declaration allocation events were merged");
		final shadow = new CppManagedStoragePlan(projection("class Main { static function make(x:Int):Int->(Void->Int) { return function(x:Int):Void->Int { return function():Int { return x; }; }; } }"));
		check(shadow.getCells().length == 1 && shadow.getCells()[0].source.binding.getKind() == LambdaParameter,
			"same-spelled root parameter received the inner cell");
		final receiver = projection("class Main { var value:Int; function make():Void->Int { return function():Int { return this.value; }; } }");
		final receiverPlan = new CppManagedStoragePlan(receiver);
		check(new CppManagedEnvironmentEmitter(receiverPlan, receiver.requireCaptureCatalog().getExpressions()[0],
			"hxhx_env_receiver").receiverField() == "captured.receiver",
			"receiver was modeled as a fake local capture");
		final unused = projected.getLocalCatalog().findByProjectedName("unused");
		check(unused != null, "test lost its uncaptured local declaration");
		rejected(() -> localAccess.render(EIdent(unused.getProjectedName()), "std::int32_t"), "not a parameter");
		rejected(() -> new CppManagedCellEmitter(plan, unused.getBinding()), "does not promote this binding");
		rejected(() -> environment.cellField(unused.getBinding()), "not captured by this managed environment");
		check(receiverPlan.getCells().length == 0
			&& receiverPlan.requireClosure(receiver.requireCaptureCatalog().getExpressions()[0]).facts.capturesReceiver,
			"receiver requirements must survive without a fake source local");

		final nullable = projection("class Main { static function make():Null<Int>->Null<Int> { return function(value:Null<Int>):Null<Int> { return value; }; } }");
		final nullablePlan = new CppManagedStoragePlan(nullable);
		final nullableAbi = nullablePlan.requireClosure(nullable.requireCaptureCatalog().getExpressions()[0]).abi;
		rejected(() -> new CppManagedFunctionBody(nullablePlan, Closure(nullable.requireCaptureCatalog().getExpressions()[0])).render(null, null, null),
			"rooted return requires a stable destination");
		check(nullableAbi.result == RootedResult && nullableAbi.getParameters()[0].storage == RootedParameter,
			"nullable transport lost presence or bypassed the conservative root convention");
		nullableAbi.getParameters().pop();
		nullableAbi.getHiddenParameters().pop();
		check(nullableAbi.getParameters().length == 1
			&& nullableAbi.getHiddenParameters().length == 3, "ABI exposed mutable parameter inventories");
		check(nullableAbi.nativeSignature() == "void(hxhx::managed::Root<hxhx::managed::Value>&, hxhx::managed::Value)",
			"native managed signature lacks its leading result root");
		final noResult = projection("class Main { static function make():Void->Void { return function():Void {}; } }");
		final noResultPlan = new CppManagedStoragePlan(noResult);
		rejected(() -> new CppManagedFunctionBody(noResultPlan,
			Closure(noResult.requireCaptureCatalog().getExpressions()[0])).render("unexpectedRoot", null, null),
			"Void managed function cannot have a result root");
		check(noResultPlan.requireClosure(noResult.requireCaptureCatalog().getExpressions()[0]).abi.result == NoResult,
			"Void closure acquired a fake result value");

		switch expression {
			case ELambda(_, ELoweredControl(FunctionBody, _, values, _)):
				values.push(EInt(99));
			case _:
				throw "expected a lowered closure";
		}
		rejected(() -> plan.getCells(), "projection was mutated");
		rejected(() -> localAccess.render(EIdent(parameterName), "std::int32_t"), "projection was mutated");
		rejected(() -> bodyEmitter.render(null, null, null), "projection was mutated");
		rejected(() -> parameters.render("heap"), "projection was mutated");
		rejected(() -> cellEmitter.renderRead("cell", "result"), "projection was mutated");
		rejected(() -> plan.requireClosure(expression), "projection was mutated");
		rejected(() -> environment.render(), "projection was mutated");
		rejected(() -> environment.renderConstruction(construction), "projection was mutated");
		rejected(() -> call.render(operands), "projection was mutated");
		rejected(() -> projected.requireCaptureCatalog().requireCallableType(expression), "projection was mutated");
		Sys.println("CPP_MANAGED_STORAGE_PLAN:PASS");
	}

	/** Declaration events cannot be borrowed from parameters or used to hide source conversions. */
	static function declaredLocals():Void {
		final projected = projection("class Main { static function make():Void { var creator = function(value:Int):Void->Int { var copy = value; var kept = copy; var wider:Float = value; return function():Int { return kept; }; }; } }");
		final plan = new CppManagedStoragePlan(projected);
		final closures = projected.requireCaptureCatalog().getExpressions();
		final access = new CppManagedLocalAccess({
			projection: projected,
			plan: plan,
			owner: Closure(closures[0]),
			parameters: ["value"],
			temporaryPrefix: "hxhx_parameters_declarations_",
			environmentName: "hxhx_env_declarations",
			environmentSymbol: "environment"
		});
		final declarations = plan.getDeclarations(Closure(closures[0]));
		check([for (entry in declarations) entry.binding.getSourceName()].join(",") == "copy,kept,wider",
			"declaration storage included another function or creation event");
		final copy = declarations[0].binding;
		final kept = declarations[1].binding;
		final wider = declarations[2].binding;
		declarations.pop();
		check(plan.getDeclarations(Closure(closures[0])).length == 3, "local event inventory is mutable");
		check(access.locals.owns(copy) && access.locals.owns(kept), "local storage lost the declared bindings");
		rejected(() -> access.locals.cellReference(copy), "not captured by a descendant");
		check(access.locals.cellReference(kept) == access.cellReference(kept), "child capture selected a different local cell");
		final parameter = plan.requireClosure(closures[0]).getParameters()[0].binding;
		rejected(() -> access.locals.value(parameter), "not a declaration");
		final rooted = new CppManagedRootedExpression({
			owner: CallableBody(access),
			heap: "heap",
			temporaryPrefix: "hxhx_value_declarations_",
			resolve: value -> {expression: value, environmentName: "hxhx_env_child", entrySymbol: "childEntry"}
		});
		rejected(() -> access.locals.renderDeclaration(copy, null, "heap", "", rooted.render), "explicit source initialization");
		final parameterName = projected.getLocalCatalog().projectedName(parameter);
		final widerName = projected.getLocalCatalog().projectedName(wider);
		// Integer widening is an implemented storage conversion. Both declaration
		// and assignment must emit it; incompatible strings must still reject.
		final initialized = rooted.renderStatement(SVar(widerName, "Float", EIdent(parameterName), HxPos.unknown()), "").join("\n");
		final assigned = rooted.render(EBinop("=", EIdent(widerName), EIdent(parameterName)), "result", "").join("\n");
		for (emitted in [initialized, assigned])
			check(emitted.indexOf("Value::floating(static_cast<double>(") >= 0, "Float storage omitted its integer widening conversion");
		rejected(() -> rooted.renderStatement(SVar(widerName, "Float", EString("wrong"), HxPos.unknown()), ""), "explicit typed conversion");
		rejected(() -> rooted.render(EBinop("=", EIdent(widerName), EString("wrong")), "result", ""), "explicit typed conversion");
	}

	/** Roots retain exact method ownership and cannot be substituted by equal source text. */
	static function rootFunction():Void {
		final source = "class Main { static function make(seed:Int, spare:Dynamic):Void->Int { var kept = seed; return function():Int { var inner = 1; return kept; }; } }";
		final projected = projection(source);
		final plan = new CppManagedStoragePlan(projected);
		final root = plan.requireFunction(Root(projected));
		check(root.facts.parentIdentity == null && root.getCells().length == 0, "root acquired a closure environment");
		check([for (parameter in root.getParameters()) parameter.binding.getSourceName()].join(",") == "seed,spare", "root lost ordered source parameters");
		check(root.abi.result == RootedResult, "root callable return lost rooted transport");
		check(root.abi.getHiddenParameters().indexOf(EnvironmentPointer) < 0, "root ABI acquired a closure environment operand");
		check([
			for (entry in plan.getDeclarations(Root(projected)))
				entry.binding.getSourceName()
		].join(",") == "kept", "root declarations included nested locals");
		final parameters = new CppManagedParameterEmitter(plan, Root(projected), ["seed", "spare"], "hxhx_parameters_root_");
		final storage = new backend.cpp.CppManagedLocalStorage(plan, Root(projected), "hxhx_locals_root_");
		check(storage.owns(plan.getDeclarations(Root(projected))[0].binding), "root storage lost its declaration");
		rejected(() -> plan.requireFunction(Root(projection(source))), "exact projection object");
		rejected(() -> new CppManagedFunctionBody(plan, Root(projection(source))), "exact projection object");
		rejected(() -> new CppManagedLocalAccess({
			projection: projected,
			plan: plan,
			owner: Root(projected),
			parameters: ["seed", "spare"],
			temporaryPrefix: "hxhx_parameters_bad_root_",
			environmentName: "hxhx_env_root",
			environmentSymbol: "environment"
		}), "without a closure environment");
		final nested = projected.requireCaptureCatalog().getExpressions()[0];
		rejected(() -> parameters.value(plan.getDeclarations(Closure(nested))[0].binding), "not a parameter");
		root.getParameters().pop();
		check(plan.requireFunction(Root(projected)).getParameters().length == 2, "root parameters expose mutable inventory");
		projected.getBody().push(SExpr(EInt(1), HxPos.unknown()));
		rejected(() -> plan.requireFunction(Root(projected)), "projection was mutated");
		rejected(() -> parameters.render("heap"), "projection was mutated");
		rejected(() -> projected.requireRootControlIdentity(), "projection was mutated");
	}

	/** Emission must reject unowned layouts instead of publishing a plausible native unit. */
	static function functionEmission():Void {
		final source = "class Main { static function make(value:Int):Void->Int { return function():Int { return value; }; } }";
		final projected = projection(source);
		final emitter = new backend.cpp.CppManagedFunctionEmitter({projection: projected, rootSymbol: "method", symbolPrefix: "hxhx_function_unit"});
		check(emitter.render() == emitter.render(), "function unit changed across repeated emission");
		rejected(() -> new backend.cpp.CppManagedFunctionEmitter({
			projection: projected,
			rootSymbol: "hxhx_function_unit_closure0",
			symbolPrefix: "hxhx_function_unit"
		}), "symbols collide");
		final optional = projection("class Main { static function value(value:Int = 3):Int { return value; } }");
		// Defaults now have an explicit entry plan. Native omission/null/supplied
		// behavior is covered by M14CppConstructorDefaultsTest; keep ownership here.
		final defaultEmitter = new backend.cpp.CppManagedFunctionEmitter({
			projection: optional,
			rootSymbol: "method",
			symbolPrefix: "hxhx_function_default"
		});
		final defaults = optional.getDefaults();
		check(defaults.length == 1 && defaults[0].slot == 0 && defaults[0].expression.match(EInt(3)), "default entry lost its source operand");
		check(defaultEmitter.render().length > 0, "default entry did not emit");
		optional.getBody().push(SExpr(EInt(1), HxPos.unknown()));
		rejected(() -> defaultEmitter.render(), "projection was mutated");
		projected.getBody().push(SExpr(EInt(1), HxPos.unknown()));
		rejected(() -> emitter.render(), "projection was mutated");
	}

	/** Selected declarations and actual call occurrences must both belong to this program. */
	static function staticCalls():Void {
		final source = "class Main { static function entry():Int { return target(); } static function target():Int { return 1; } static function other():Int { return 2; } }";
		final parsed = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final functions = TyperStage.typeResolvedModule(parsed, TyperIndex.build([parsed])).getTypedClasses()[0].getFunctions();
		final projections = [for (fn in functions) TypedBodySource.functionProjection(fn)];
		final inputs:Array<backend.cpp.CppManagedProgramEmitter.CppManagedProgramFunction> = [
			for (index in 0...projections.length)
				{projection: projections[index], rootSymbol: "method" + index, symbolPrefix: "hxhx_function_method" + index}
		];
		rejected(() -> new backend.cpp.CppManagedProgramEmitter({functions: [inputs[0]], output: []}).render(), "lacks the selected static declaration");
		rejected(() -> new backend.cpp.CppManagedProgramEmitter({functions: [inputs[0], inputs[0]], output: []}), "repeats a declaration identity");
		rejected(() -> new backend.cpp.CppManagedFunctionEmitter({
			projection: projections[0],
			rootSymbol: "entry",
			symbolPrefix: "hxhx_function_wrong_static",
			resolveStatic: _ -> Source(projections[2], "other")
		}).render(), "another declaration");
		final plan = new CppManagedStoragePlan(projections[0]);
		final access = new CppManagedLocalAccess({
			projection: projections[0],
			plan: plan,
			owner: Root(projections[0]),
			parameters: [],
			temporaryPrefix: "hxhx_parameters_static_test_"
		});
		var original:Null<HxExpr> = null;
		for (statement in projections[0].getBody())
			TypedBackendSourceWalk.statement(statement, value -> {
				if (TypedExactStaticCallSource.decode(value) != null)
					original = value;
			}, _ -> {});
		check(original != null, "static call lost its exact declaration marker");
		access.requireExpression(original);
		final copied:HxExpr = switch original {
			case ECall(callee, args): ECall(callee, args.copy());
			case _: throw "missing call";
		};
		rejected(() -> access.requireExpression(copied), "not an exact expression");
		final program = new backend.cpp.CppManagedProgramEmitter({functions: inputs, output: []});
		check(program.render() == program.render(), "static program output is not deterministic");
		projections[1].getBody().push(SExpr(EInt(9), HxPos.unknown()));
		rejected(() -> program.render(), "projection was mutated");
	}

	static function main():Void
		run();

	/** Structural field types and exact expression ownership both precede native reads. */
	static function recordReads():Void {
		final type = TyType.anonymous(["name"], [TyType.fromHintText("String")]);
		check(backend.cpp.CppManagedRecordRead.fieldType(type, "name").getSemanticKey() == "primitive:String", "record field lost its semantic type");
		rejected(() -> backend.cpp.CppManagedRecordRead.fieldType(type, "missing"), "exact structural field");
		rejected(() -> backend.cpp.CppManagedRecordRead.fieldType(TyType.fromHintText("String"), "name"), "exact anonymous receiver");
		check(!backend.cpp.CppManagedStringEquality.supports("==", TyType.fromHintText("Float"), TyType.fromHintText("String")),
			"String equality admitted mixed types");
		final projected = projection("class Main { static function read():String { final value = {name: 'a'}; return value.name; } }");
		final plan = new CppManagedStoragePlan(projected);
		final access = new CppManagedLocalAccess({
			projection: projected,
			plan: plan,
			owner: Root(projected),
			parameters: [],
			temporaryPrefix: "hxhx_parameters_record_read_"
		});
		var selected:Null<HxExpr> = null;
		for (statement in projected.getBody())
			TypedBackendSourceWalk.statement(statement, value -> {
				switch value {
					case EField(_, _): selected = value;
					case _:
				}
			}, _ -> {});
		final copy:HxExpr = switch selected {
			case EField(receiver, name): EField(receiver, name);
			case _: throw "record fixture lost its field";
		};
		final rooted = new CppManagedRootedExpression({
			owner: CallableBody(access),
			heap: "heap",
			temporaryPrefix: "hxhx_value_record_read_",
			resolve: _ -> throw "record read cannot select a closure"
		});
		rooted.render(selected, "result", "");
		rejected(() -> rooted.render(copy, "result", ""), "not an exact expression");
	}
}
