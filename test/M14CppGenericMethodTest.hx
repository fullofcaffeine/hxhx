/** Execute applied generic methods through the normal C++ program runner and collecting heap. */
class M14CppGenericMethodTest {
	static function program():backend.cpp.CppTypedProgramProjection {
		final path = "test/fixtures/cpp_generic_method_seed/Main.hx";
		final module = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
		return new backend.cpp.CppTypedProgramProjection(new MacroExpandedProgram([TyperStage.typeResolvedModule(module, TyperIndex.build([module]))], false));
	}

	static function rejects(action:Void->Void, fragment:String):Void {
		try
			action()
		catch (failure:haxe.Exception) {
			if (failure.message.indexOf(fragment) >= 0)
				return;
			throw failure;
		}
		throw "generic method accepted foreign or stale evidence";
	}

	/** Applied calls must select their own declaration, type arguments, and current source revision. */
	static function ownership():Void {
		final source = program();
		final storage = new backend.cpp.CppManagedClassStorage(source);
		final main = source.requireClass(source.requireClassIdentity("Main"))
			.getFunctions()
			.filter(fn -> fn.requireSemanticDeclaration().getSignature().getName() == "main")[0];
		for (constructor in main.getConstructorCatalog().getEntries())
			storage.constructorApplication(constructor);
		final calls = new Array<TypedBackendInstanceCallOccurrence>();
		for (statement in main.getBody())
			TypedBackendSourceWalk.statement(statement, expression -> {
				final call = storage.methods.functionInstanceCall(main, expression);
				if (call != null && call.getDeclaration().getSignature().getName() == "read")
					calls.push(call);
			}, _ -> {});
		final call = calls[0];
		final application = storage.methods.instanceApplication(call);
		if (application.resultType().getSemanticKey() != "primitive:Int"
			|| application.storedResultType().getSemanticKey() != "nullable:primitive:Int")
			throw "generic method conflated semantic result and storage transport";
		final cases = storage.methods.instanceDispatch(call);
		if (cases == null
			|| cases.length != 2
			|| cases.filter(entry -> entry.application.identity == application.identity).length != 1
			|| cases.filter(entry -> entry.application.resultType().getSemanticKey() != "primitive:Int").length != 0)
			throw "erased class descriptor mixed distinct generic applications";
		final inherited = calls.filter(selected -> selected.getReceiverType().getNominalIdentity().getCanonicalName() == "Main.Leaf")[0];
		final inheritedApplication = storage.methods.instanceApplication(inherited);
		if (inheritedApplication.receiverType.getNominalIdentity().getCanonicalName() != "Main.Box"
			|| inheritedApplication.receiverType.getTypeArguments()[0].getSemanticKey() != "primitive:String")
			throw "generic method lost arguments across its ancestor edges";
		final casts = new backend.cpp.CppManagedCastPlan(source);
		final leafType = inherited.getReceiverType();
		if (!casts.permitsClassUpcast(inheritedApplication.receiverType, leafType)
			|| casts.permitsClassUpcast(application.receiverType, leafType)
			|| casts.permitsClassUpcast(leafType, inheritedApplication.receiverType)
			|| casts.permitsClassUpcast(application.receiverType, inheritedApplication.receiverType))
			throw "generic upcast ignored an ancestor edge, direction, or exact type arguments";
		rejects(() -> new backend.cpp.CppManagedClassStorage(program()).methods.instanceApplication(call), "another program or occurrence");
		storage.methods.sealInstanceDispatch([for (call in calls) {call: call, context: null}]);
		storage.methods.instanceDispatch(call).pop();
		if (storage.methods.instanceDispatch(call).length != 2)
			throw "consumer changed sealed generic dispatch";
		final body = HxFunctionDecl.getBody(application.projection.requireSemanticDeclaration().getSourceDeclaration());
		body.push(SExpr(EInt(99), HxPos.unknown()));
		rejects(() -> application.assertCurrent(), "typed body revision mismatch");
		body.pop();
		application.assertCurrent();
		switch call.getExpression() {
			case ECall(_, arguments):
				arguments.push(EInt(99));
				rejects(() -> application.assertCurrent(), "marker was mutated");
				arguments.pop();
			case _:
				throw "generic method lost its exact projected call";
		}
		application.assertCurrent();
		Sys.println("CPP_GENERIC_METHOD:OWNERSHIP:PASS");
	}

	static function main():Void {
		ownership();
		M14CppManagedStartupExecutionTest.runFixture({
			sourceRoot: "test/fixtures/cpp_generic_method_seed",
			output: ".tmp/cpp-generic-method",
			observer: "test/cpp_managed_heap/GenericFieldObserver.cpp"
		});
		Sys.println("CPP_GENERIC_METHOD:PASS");
	}
}
