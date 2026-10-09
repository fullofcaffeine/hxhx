import backend.cpp.CppManagedCallContext.fromFunction;
import backend.cpp.CppManagedCallContext.fromInitializer;
import backend.cpp.CppManagedClassStorage;
import backend.cpp.CppTypedProgramProjection;

/** Constructor substitution belongs to the exact calling function or field, including its closures. */
class M14CppGenericConstructorContextTest {
	static function program():CppTypedProgramProjection {
		final path = "test/fixtures/cpp_generic_constructor_context_seed/Main.hx";
		final module = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
		return new CppTypedProgramProjection(new MacroExpandedProgram([TyperStage.typeResolvedModule(module, TyperIndex.build([module]))], false));
	}

	static function rejects(action:Void->Void, fragment:String):Void {
		try
			action()
		catch (failure:haxe.Exception) {
			if (failure.message.indexOf(fragment) >= 0)
				return;
			throw failure;
		}
		throw "constructor accepted an invalid enclosing application";
	}

	static function field(source:CppTypedProgramProjection, name:String):TypedBackendFieldInitializerProjection
		return source.requireClass(source.requireClassIdentity("Main.Factory")).getFieldInitializers().filter(value -> value.getField().getName() == name)[0];

	static function ownership():Void {
		final source = program();
		final classes = new CppManagedClassStorage(source);
		final main = source.requireClass(source.requireClassIdentity("Main"))
			.getFunctions()
			.filter(fn -> fn.requireSemanticDeclaration().getSignature().getName() == "main")[0];
		final calls = new Array<TypedBackendInstanceCallOccurrence>();
		TypedBackendSourceWalk.functionDeclaration(main.getDeclaration(), expression -> {
			final call = classes.methods.functionInstanceCall(main, expression);
			if (call != null && call.getDeclaration().getSignature().getName() == "make")
				calls.push(call);
		}, _ -> {});
		final ints = classes.methods.instanceApplication(calls[0]);
		final strings = classes.methods.instanceApplication(calls[1]);
		final occurrence = ints.projection.getConstructorCatalog().getEntries()[0];
		final original = occurrence.getConstructedType().getSemanticKey();
		final intNew = classes.constructorApplication(occurrence, fromFunction(ints));
		final stringNew = classes.constructorApplication(occurrence, fromFunction(strings));
		if (intNew.receiverType.getTypeArguments()[0].getSemanticKey() != "primitive:Int"
			|| stringNew.receiverType.getTypeArguments()[0].getSemanticKey() != "primitive:String"
			|| intNew.identity == stringNew.identity
			|| occurrence.getConstructedType().getSemanticKey() != original
			|| TyTypeSubstitution.parameterIdentities(occurrence.getConstructedType()).length == 0)
			throw "constructor conflated applications or mutated shared declaration facts";
		rejects(() -> classes.constructorApplication(occurrence), "concrete owner arguments");
		rejects(() -> classes.constructorApplication(occurrence, fromFunction(intNew)), "another executable owner");
		final projection = field(source, "build");
		final owner = projection.getField().getOwner();
		final intField = classes.initializerApplication(projection, TyType.nominal(owner, [TyType.fromHintText("Int")]));
		final stringField = classes.initializerApplication(projection, TyType.nominal(owner, [TyType.fromHintText("String")]));
		final fieldOccurrence = projection.getConstructorCatalog().getEntries()[0];
		final fieldIntNew = classes.constructorApplication(fieldOccurrence, fromInitializer(intField));
		final fieldStringNew = classes.constructorApplication(fieldOccurrence, fromInitializer(stringField));
		if (fieldIntNew.identity != intNew.identity || fieldStringNew.identity != stringNew.identity)
			throw "equal constructor applications did not select the same authored body";
		rejects(() -> classes.constructorApplication(fieldOccurrence), "concrete owner arguments");
		rejects(() -> classes.constructorApplication(fieldOccurrence, fromFunction(ints)), "another executable owner");
		rejects(() -> classes.constructorApplication(occurrence, fromInitializer(intField)), "another executable owner");
		final other = classes.initializerApplication(field(source, "alsoBuild"), intField.ownerType);
		rejects(() -> classes.constructorApplication(fieldOccurrence, fromInitializer(other)), "another executable owner");
		final foreignSource = program();
		final foreign = new CppManagedClassStorage(foreignSource).initializerApplication(field(foreignSource, "build"), intField.ownerType);
		rejects(() -> classes.constructorApplication(fieldOccurrence, fromInitializer(foreign)), "another executable owner");
		// The retained target must fail when its lexical source changes, even when its type stays valid.
		switch fieldOccurrence.getExpression() {
			case ENew(_, arguments):
				final saved = arguments[0];
				arguments[0] = EInt(99);
				rejects(() -> fieldIntNew.assertCurrent(), "arguments were replaced");
				arguments[0] = saved;
			case _:
				throw "constructor fixture lost its allocation";
		}
		fieldIntNew.assertCurrent();
		final body = HxFunctionDecl.getBody(ints.projection.requireSemanticDeclaration().getSourceDeclaration());
		body.push(SExpr(EInt(99), HxPos.unknown()));
		rejects(() -> intNew.assertCurrent(), "typed body revision mismatch");
		body.pop();
		intNew.assertCurrent();
		Sys.println("CPP_GENERIC_CONSTRUCTOR_CONTEXT:OWNERSHIP:PASS");
	}

	static function main():Void {
		ownership();
		M14CppManagedStartupExecutionTest.runFixture({
			sourceRoot: "test/fixtures/cpp_generic_constructor_context_seed",
			output: ".tmp/cpp-generic-constructor-context",
			observer: "test/cpp_managed_heap/GenericFieldObserver.cpp"
		});
		Sys.println("CPP_GENERIC_CONSTRUCTOR_CONTEXT:PASS");
	}
}
