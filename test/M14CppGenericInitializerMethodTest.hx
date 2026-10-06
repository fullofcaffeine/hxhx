import backend.cpp.CppManagedCallContext.fromFunction;
import backend.cpp.CppManagedCallContext.fromInitializer;
import backend.cpp.CppManagedClassStorage;
import backend.cpp.CppTypedProgramProjection;

/** Field and function applications cannot borrow each other's exact call ownership. */
class M14CppGenericInitializerMethodTest {
	static function program():CppTypedProgramProjection {
		final path = "test/fixtures/cpp_generic_initializer_method_seed/Main.hx";
		final module = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
		return new CppTypedProgramProjection(new MacroExpandedProgram([TyperStage.typeResolvedModule(module, TyperIndex.build([module]))], false));
	}

	static function field(source:CppTypedProgramProjection, name:String):TypedBackendFieldInitializerProjection {
		return source.requireClass(source.requireClassIdentity("Main.Reader")).getFieldInitializers().filter(value -> value.getField().getName() == name)[0];
	}

	static function rejects(action:Void->Void, fragment:String):Void {
		try
			action()
		catch (failure:haxe.Exception) {
			if (failure.message.indexOf(fragment) >= 0)
				return;
			throw failure;
		}
		throw "initializer call accepted invalid ownership";
	}

	static function ownership():Void {
		final source = program();
		final classes = new CppManagedClassStorage(source);
		final main = source.requireClass(source.requireClassIdentity("Main"))
			.getFunctions()
			.filter(fn -> fn.requireSemanticDeclaration().getSignature().getName() == "main")[0];
		for (allocation in main.getConstructorCatalog().getEntries())
			classes.constructorApplication(allocation);
		final projection = field(source, "read");
		final owner = projection.getField().getOwner();
		final ints = classes.initializerApplication(projection, TyType.nominal(owner, [TyType.fromHintText("Int")]));
		final strings = classes.initializerApplication(projection, TyType.nominal(owner, [TyType.fromHintText("String")]));
		final bools = classes.initializerApplication(projection, TyType.nominal(owner, [TyType.fromHintText("Bool")]));
		final calls = new Array<TypedBackendInstanceCallOccurrence>();
		TypedBackendSourceWalk.expression(projection.getExpression(), expression -> {
			final call = classes.methods.initializerInstanceCall(projection, expression);
			if (call != null)
				calls.push(call);
		});
		if (calls.length != 1)
			throw "initializer fixture lost its exact method call";
		final call = calls[0];
		final original = call.getReceiverType().getSemanticKey();
		final intRead = classes.methods.instanceApplication(call, fromInitializer(ints));
		final stringRead = classes.methods.instanceApplication(call, fromInitializer(strings));
		if (intRead.resultType().getSemanticKey() != "primitive:Int"
			|| stringRead.resultType().getSemanticKey() != "primitive:String"
			|| intRead.identity == stringRead.identity
			|| call.getReceiverType().getSemanticKey() != original
			|| TyTypeSubstitution.parameterIdentities(call.getReceiverType()).length == 0)
			throw "initializer call mixed applications or changed shared facts";
		rejects(() -> classes.methods.instanceApplication(call), "exact applied class");
		rejects(() -> classes.methods.instanceApplication(call, fromFunction(intRead)), "another executable owner");
		final other = classes.initializerApplication(field(source, "alsoRead"), ints.ownerType);
		rejects(() -> classes.methods.instanceApplication(call, fromInitializer(other)), "another executable owner");
		final foreignSource = program();
		final foreign = new CppManagedClassStorage(foreignSource).initializerApplication(field(foreignSource, "read"), ints.ownerType);
		rejects(() -> classes.methods.instanceApplication(call, fromInitializer(foreign)), "another executable owner");
		classes.methods.sealInstanceDispatch([
			{call: call, context: fromInitializer(ints)},
			{call: call, context: fromInitializer(strings)}
		]);
		final intTargets = classes.methods.instanceDispatch(call, fromInitializer(ints));
		final stringTargets = classes.methods.instanceDispatch(call, fromInitializer(strings));
		if (intTargets.length != 2
			|| stringTargets.length != 1
			|| intTargets.filter(entry -> entry.application.resultType().getSemanticKey() != "primitive:Int").length != 0
			|| stringTargets[0].application.resultType().getSemanticKey() != "primitive:String")
			throw "initializer dispatch mixed exact receiver applications";
		intTargets.pop();
		if (classes.methods.instanceDispatch(call, fromInitializer(ints)).length != 2)
			throw "initializer dispatch leaked its mutable target array";
		rejects(() -> classes.methods.instanceDispatch(call, fromInitializer(bools)), "absent from sealed dispatch");
		switch call.getExpression() {
			case ECall(_, arguments) if (arguments.length > 0):
				final saved = arguments[0];
				arguments[0] = EInt(99);
				rejects(() -> intRead.assertCurrent(), "mutated");
				arguments[0] = saved;
			case _:
				throw "initializer call mutation fixture lost its marker";
		}
		intRead.assertCurrent();
		Sys.println("CPP_GENERIC_INITIALIZER_METHOD:OWNERSHIP:PASS");
	}

	static function main():Void {
		ownership();
		M14CppManagedStartupExecutionTest.runFixture({
			sourceRoot: "test/fixtures/cpp_generic_initializer_method_seed",
			output: ".tmp/cpp-generic-initializer-method",
			observer: "test/cpp_managed_heap/GenericFieldObserver.cpp"
		});
		Sys.println("CPP_GENERIC_INITIALIZER_METHOD:PASS");
	}
}
