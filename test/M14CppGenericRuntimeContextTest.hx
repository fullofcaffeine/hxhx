import backend.cpp.CppManagedCallContext.fromFunction;
import backend.cpp.CppManagedCallContext.fromInitializer;
import backend.cpp.CppManagedClassStorage;
import backend.cpp.CppManagedMapTypeTest.matchesFamily;
import backend.cpp.CppTypedProgramProjection;

/** Applied runtime tests keep exact source ownership and preserve unsupported-value rejection. */
class M14CppGenericRuntimeContextTest {
	static function rejects(action:Void->Void, fragment:String):Void {
		try
			action()
		catch (failure:haxe.Exception) {
			if (failure.message.indexOf(fragment) >= 0)
				return;
			throw failure;
		}
		throw "runtime test accepted invalid ownership or an unsupported value";
	}

	static function field(source:CppTypedProgramProjection, name:String):TypedBackendFieldInitializerProjection
		return source.requireClass(source.requireClassIdentity("Main.Inspector"))
			.getFieldInitializers()
			.filter(value -> value.getField().getName() == name)[0];

	static function ownership():Void {
		final fixture = CppResolvedFixture.load({
			sourceRoot: "test/fixtures/cpp_generic_runtime_context_seed",
			mainModule: "Main",
			requiredModules: ["haxe.ds.Map", "haxe.ds.IntMap"]
		});
		final expanded = new MacroExpandedProgram(TypedAbstractOperatorLowering.lowerModules(fixture.modules, fixture.index), false);
		final source = new CppTypedProgramProjection(expanded);
		final classes = new CppManagedClassStorage(source);
		final main = source.requireClass(source.requireClassIdentity("Main"))
			.getFunctions()
			.filter(fn -> fn.requireSemanticDeclaration().getSignature().getName() == "main")[0];
		final allocations = main.getConstructorCatalog()
			.getEntries()
			.filter(entry -> entry.getConstructedType().getNominalIdentity().getCanonicalName() == "Main.Inspector");
		final projection = field(source, "check");
		final ints = classes.initializerApplication(projection, allocations[0].getConstructedType());
		final maps = classes.initializerApplication(projection, allocations[3].getConstructedType());
		final occurrence = projection.getRuntimeTypeCatalog().getEntries()[0];
		final original = occurrence.getValueType().getSemanticKey();
		if (matchesFamily(occurrence, classes, null, fromInitializer(ints))
			|| !matchesFamily(occurrence, classes, null, fromInitializer(maps))
			|| occurrence.getValueType().getSemanticKey() != original
			|| !occurrence.getValueType().isTypeParameter())
			throw "runtime test conflated caller applications or changed shared facts";
		rejects(() -> matchesFamily(occurrence, classes), "erased or unplanned");
		rejects(() -> matchesFamily(occurrence, null, null, fromInitializer(maps)), "program-owned class storage");
		final other = classes.initializerApplication(field(source, "alsoCheck"), maps.ownerType);
		rejects(() -> matchesFamily(occurrence, classes, null, fromInitializer(other)), "another executable owner");
		final erased = classes.initializerApplication(projection, TyType.nominal(projection.getField().getOwner(), [TyType.fromHintText("Dynamic")]));
		rejects(() -> matchesFamily(occurrence, classes, null, fromInitializer(erased)), "erased or unplanned");
		final calls = new Array<TypedBackendInstanceCallOccurrence>();
		TypedBackendSourceWalk.functionDeclaration(main.getDeclaration(), expression -> {
			final call = classes.methods.functionInstanceCall(main, expression);
			if (call != null && call.getDeclaration().getSignature().getName() == "test")
				calls.push(call);
		}, _ -> {});
		final method = classes.methods.instanceApplication(calls[0]);
		final methodOccurrence = method.projection.getRuntimeTypeCatalog().getEntries()[0];
		if (!matchesFamily(methodOccurrence, classes, null, fromFunction(method)))
			throw "method runtime test lost its concrete Map operand";
		rejects(() -> matchesFamily(occurrence, classes, null, fromFunction(method)), "another executable owner");
		rejects(() -> matchesFamily(methodOccurrence, classes, null, fromInitializer(maps)), "another executable owner");
		// New projection caches must not borrow occurrence ownership, even for identical typed modules.
		final independent = new MacroExpandedProgram([
			for (module in expanded.getTypedModules())
				new TypedModule(module.getParsed(), module.getEnv(), module.getTypedClasses(), module.getRevision(), module.getSourceOrigin(),
					module.getConditionalCompilation(), module.getGeneratedDeclarations())
		], expanded.macroMode, expanded.getGeneratedOcamlModules());
		final foreign = new CppTypedProgramProjection(independent);
		final foreignClasses = new CppManagedClassStorage(foreign);
		final foreignField = foreignClasses.initializerApplication(field(foreign, "check"), maps.ownerType);
		rejects(() -> matchesFamily(occurrence, classes, null, fromInitializer(foreignField)), "another executable owner");
		rejects(() -> matchesFamily(occurrence, foreignClasses, null, fromInitializer(foreignField)), "another program or occurrence");
		switch occurrence.getExpression() {
			case ECall(_, arguments):
				final saved = arguments[0];
				arguments[0] = EInt(1);
				rejects(() -> matchesFamily(occurrence, classes, null, fromInitializer(maps)), "mutat");
				arguments[0] = saved;
			case _:
				throw "runtime test lost its projected marker";
		}
		if (!matchesFamily(occurrence, classes, null, fromInitializer(maps)))
			throw "restored runtime marker lost its exact application";
		// Local field reuse must not replace the whole-program publication guard.
		final mainBody = HxFunctionDecl.getBody(main.requireSemanticDeclaration().getSourceDeclaration());
		mainBody.push(SExpr(EInt(99), HxPos.unknown()));
		rejects(() -> new backend.cpp.CppManagedProgramPlan(source, "Main"), "typed body revision mismatch");
		mainBody.pop();
		source.assertCurrent();
		Sys.println("CPP_GENERIC_RUNTIME_CONTEXT:OWNERSHIP:PASS");
	}

	static function main():Void {
		ownership();
		M14CppManagedStartupExecutionTest.runFixture({
			sourceRoot: "test/fixtures/cpp_generic_runtime_context_seed",
			output: ".tmp/cpp-generic-runtime-context",
			observer: "test/cpp_managed_heap/GenericRuntimeTypeObserver.cpp",
			requiredModules: ["haxe.ds.Map", "haxe.ds.IntMap"]
		});
		Sys.println("CPP_GENERIC_RUNTIME_CONTEXT:PASS");
	}
}
