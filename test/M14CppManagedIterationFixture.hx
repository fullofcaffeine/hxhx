import backend.cpp.CppManagedFunctionEmitter;

/** Authored Array loops use the real provider and production closure/storage planning. */
function append(declarations:Array<String>):Void {
	final fixture = CppResolvedFixture.load({sourceRoot: "test/oracle/cpp_managed_iteration_seed/src", mainModule: "Main", requiredModules: ["Array"]});
	final selected = ["walk", "capture", "nested", "first", "negate"];
	var count = 0;
	for (typed in fixture.main.getTypedClasses()[0].getFunctions()) {
		final name = HxFunctionDecl.getName(typed.getSourceDeclaration());
		if (selected.indexOf(name) < 0)
			continue;
		final revision = CompilerTypedTreeRevision.functionBody(typed);
		if (name == "walk")
			ownership(TypedBodySource.functionProjection(typed));
		final emitter = new CppManagedFunctionEmitter({
			projection: TypedBodySource.functionProjection(typed),
			rootSymbol: "generatedIteration" + name,
			symbolPrefix: "hxhx_function_iteration" + name
		});
		final first = emitter.render();
		if (first != emitter.render() || revision != CompilerTypedTreeRevision.functionBody(typed))
			throw "iteration emission changed its typed source or deterministic output";
		declarations.push(first);
		count++;
	}
	if (count != selected.length)
		throw "iteration fixture lost an authored function";
}

/** Mixed loop operands or another function cannot authorize an iteration allocation event. */
private function ownership(projection:TypedBackendFunctionProjection):Void {
	final plan = new backend.cpp.CppManagedStoragePlan(projection);
	final closure = projection.requireCaptureCatalog().getExpressions()[0];
	final access = new backend.cpp.CppManagedLocalAccess({
		projection: projection,
		plan: plan,
		owner: Closure(closure),
		parameters: [],
		temporaryPrefix: "hxhx_parameters_iteration_rejection_",
		environmentName: "hxhx_env_IterationRejection",
		environmentSymbol: "environment"
	});
	var loop:Null<HxExpr> = null;
	TypedBackendSourceWalk.expression(closure, expression -> {
		switch expression {
			case ELoweredControl(For(_), _, _, _): loop = expression;
			case _:
		}
	});
	final operands = switch loop {
		case ELoweredControl(For(binding), _, children, _): {binding: binding, iterable: children[0]};
		case _: throw "iteration ownership fixture lost its loop";
	};
	access.requireLoop(operands.binding, operands.iterable);
	rejected(() -> access.requireLoop(Value("unrelated"), operands.iterable), "exact projected occurrence");
	rejected(() -> access.requireLoop(operands.binding, EInt(0)), "exact projected occurrence");
	final root = new backend.cpp.CppManagedLocalAccess({
		projection: projection,
		plan: plan,
		owner: Root(projection),
		parameters: ["source", "visit"],
		temporaryPrefix: "hxhx_parameters_iteration_root_"
	});
	rejected(() -> root.requireLoop(operands.binding, operands.iterable), "exact projected occurrence");
	final binding = access.binding(HxForBinding.names(operands.binding)[0]);
	rejected(() -> access.locals.renderDeclaration(binding, EInt(0), "heap", "", (_, _, _) -> []), "declaration event");
	for (declaration in plan.getDeclarations(Closure(closure)))
		if (declaration.creation == Declaration)
			rejected(() -> access.locals.renderIteration(declaration.binding, "selected", "heap", ""), "exact creation event");
}

private function rejected(run:Void->Void, diagnostic:String):Void {
	try {
		run();
	} catch (failure:haxe.Exception) {
		if (failure.message.indexOf(diagnostic) >= 0)
			return;
		throw failure;
	}
	throw "iteration fixture accepted invalid input: " + diagnostic;
}
