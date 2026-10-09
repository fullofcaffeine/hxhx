/** Check exact generic selection and expose the authored call through stable observer symbols. */
function header(program:backend.cpp.CppTypedProgramProjection, plan:backend.cpp.CppManagedProgramPlan):String {
	final owner = program.requireClass(program.requireClassIdentity("Main"));
	final boundary = owner.getFunctions().filter(fn -> HxFunctionDecl.getName(fn.getDeclaration()) == "boundary")[0];
	final standard = program.requireClass(program.requireClassIdentity("Std"));
	final declaration = standard.getFunctions().filter(fn -> HxFunctionDecl.getName(fn.getDeclaration()) == "downcast")[0].requireSemanticDeclaration();
	backend.cpp.CppManagedDowncast.requireDeclaration(declaration);
	final args = declaration.getSignature().getArgs();
	final original = args[1];
	args[1] = TyType.fromHintText("Dynamic");
	reject(() -> backend.cpp.CppManagedDowncast.requireDeclaration(declaration), "exact generic signature");
	args[1] = original;
	reject(() -> backend.cpp.CppManagedStaticTarget.abi(Downcast(declaration)), "exact call application");
	final expression = switch boundary.getBody()[0] {
		case SReturn(value, _): value;
		case _: throw "downcast boundary lost its return";
	};
	final classes = @:privateAccess plan.classes;
	final access = new backend.cpp.CppManagedLocalAccess({
		projection: boundary,
		plan: new backend.cpp.CppManagedStoragePlan(boundary),
		owner: Root(boundary),
		parameters: ["value", "target"],
		temporaryPrefix: "hxhx_parameters_downcast_"
	});
	final rooted = new backend.cpp.CppManagedRootedExpression({
		owner: CallableBody(access),
		classes: classes,
		heap: "heap",
		temporaryPrefix: "hxhx_value_downcast_",
		resolve: _ -> throw "downcast boundary has no nested closures",
		resolveStatic: identity -> @:privateAccess plan.emitter.resolve(identity)
	});
	final copy = switch expression {
		case ECall(target, values): HxExpr.ECall(target, values.copy());
		case _: throw "downcast boundary lost its call";
	};
	reject(() -> rooted.valueType(copy), "not an exact expression");
	reject(() -> rooted.render(copy, "result", ""), "not an exact expression");
	final foreignFixture = CppResolvedFixture.load({sourceRoot: "test/oracle/cpp_downcast_seed", mainModule: "Main", requiredModules: ["Std"]});
	final foreignProgram = new backend.cpp.CppTypedProgramProjection(new MacroExpandedProgram(TypedAbstractOperatorLowering.lowerModules(foreignFixture.modules,
		foreignFixture.index), false));
	final foreign = new backend.cpp.CppManagedRootedExpression({
		owner: CallableBody(access),
		classes: new backend.cpp.CppManagedClassStorage(foreignProgram),
		heap: "heap",
		temporaryPrefix: "hxhx_value_foreign_downcast_",
		resolve: _ -> throw "downcast boundary has no nested closures",
		resolveStatic: identity -> @:privateAccess plan.emitter.resolve(identity)
	});
	reject(() -> foreign.valueType(expression), "foreign function owner");
	reject(() -> foreign.render(expression, "result", ""), "foreign function owner");
	if (rooted.valueType(expression).getSemanticKey() != "nominal:Main.Child")
		throw "downcast erased its selected result type";
	final bindings = [];
	for (name in ["value", "target"]) {
		final selected = owner.getFunctions().filter(fn -> HxFunctionDecl.getName(fn.getDeclaration()) == name)[0];
		final target = @:privateAccess plan.emitter.resolve(selected.getStableIdentity());
		bindings.push("#define HXHX_DOWNCAST_" + name.toUpperCase() + " " + backend.cpp.CppManagedStaticTarget.sourceSymbol(target));
	}
	program.assertCurrent();
	return bindings.join("\n") + "\n" + new backend.cpp.CppManagedProgramEmitter({
		functions: [
			{projection: boundary, rootSymbol: "observeDowncast", symbolPrefix: "hxhx_function_downcast_boundary_"}
		],
		output: [],
		downcasts: [declaration],
		classes: classes
	}).render();
}

/** Reject the intended ownership or signature fault rather than accepting any exception. */
private function reject(action:Void->Void, expected:String):Void {
	try
		action()
	catch (error:haxe.Exception) {
		if (error.message.indexOf(expected) < 0)
			throw error;
		return;
	}
	throw "downcast accepted invalid facts: " + expected;
}
