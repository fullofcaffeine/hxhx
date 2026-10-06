import backend.cpp.CppManagedCallContext.fromFunction;
import backend.cpp.CppManagedClassStorage;
import backend.cpp.CppTypedProgramProjection;
import backend.cpp.CppManagedMethods.CppManagedMethodUse;

/** Keep lexical call ownership separate from the concrete application that executes it. */
class M14CppGenericMethodContextTest {
	static function rejects(action:Void->Void, fragment:String):Void {
		try
			action()
		catch (failure:haxe.Exception) {
			if (failure.message.indexOf(fragment) >= 0)
				return;
			throw failure;
		}
		throw "nested call accepted foreign context";
	}

	static function ownership():Void {
		final path = "test/fixtures/cpp_generic_method_context_seed/Main.hx";
		final module = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
		final program = new CppTypedProgramProjection(new MacroExpandedProgram([TyperStage.typeResolvedModule(module, TyperIndex.build([module]))], false));
		final classes = new CppManagedClassStorage(program);
		final main = program.requireClass(program.requireClassIdentity("Main"))
			.getFunctions()
			.filter(fn -> fn.requireSemanticDeclaration().getSignature().getName() == "main")[0];
		for (allocation in main.getConstructorCatalog().getEntries())
			classes.constructorApplication(allocation);
		final outer = new Array<TypedBackendInstanceCallOccurrence>();
		TypedBackendSourceWalk.functionDeclaration(main.getDeclaration(), expression -> {
			final call = classes.methods.functionInstanceCall(main, expression);
			if (call != null && call.getDeclaration().getSignature().getName() == "forward")
				outer.push(call);
		}, _ -> {});
		final ints = classes.methods.instanceApplication(outer[0]);
		final bools = classes.methods.instanceApplication(outer[1]);
		final strings = classes.methods.instanceApplication(outer[2]);
		final nested = new Array<TypedBackendInstanceCallOccurrence>();
		TypedBackendSourceWalk.functionDeclaration(ints.projection.getDeclaration(), expression -> {
			final call = classes.methods.functionInstanceCall(ints.projection, expression);
			if (call != null)
				nested.push(call);
		}, _ -> {});
		final read = nested.filter(call -> call.getDeclaration().getSignature().getName() == "read")[0];
		final original = read.getReceiverType().getSemanticKey();
		final intRead = classes.methods.instanceApplication(read, fromFunction(ints));
		final boolRead = classes.methods.instanceApplication(read, fromFunction(bools));
		final stringRead = classes.methods.instanceApplication(read, fromFunction(strings));
		if (intRead.resultType().getSemanticKey() != "primitive:Int"
			|| boolRead.resultType().getSemanticKey() != "primitive:Bool"
			|| stringRead.resultType().getSemanticKey() != "primitive:String"
			|| intRead.identity == boolRead.identity
			|| intRead.identity == stringRead.identity)
			throw "same lexical call conflated concrete enclosing applications";
		if (read.getReceiverType().getSemanticKey() != original
			|| TyTypeSubstitution.parameterIdentities(read.getReceiverType()).length == 0)
			throw "application mutated shared generic call facts";
		rejects(() -> classes.methods.instanceApplication(read), "exact applied class");
		rejects(() -> classes.methods.instanceApplication(read, fromFunction(intRead)), "another executable owner");
		final uses:Array<CppManagedMethodUse> = [
			{call: read, context: fromFunction(ints)},
			{call: read, context: fromFunction(strings)}
		];
		classes.methods.sealInstanceDispatch(uses);
		final intTargets = classes.methods.instanceDispatch(read, fromFunction(ints));
		final stringTargets = classes.methods.instanceDispatch(read, fromFunction(strings));
		if (intTargets.length != 2
			|| stringTargets.length != 2
			|| intTargets.filter(entry -> entry.application.resultType().getSemanticKey() != "primitive:Int").length != 0
			|| stringTargets.filter(entry -> entry.application.resultType().getSemanticKey() != "primitive:String").length != 0)
			throw "sealed dispatch mixed applications of the same call";
		intTargets.pop();
		if (classes.methods.instanceDispatch(read, fromFunction(ints)).length != 2)
			throw "consumer changed sealed contextual dispatch";
		rejects(() -> classes.methods.instanceDispatch(read, fromFunction(bools)), "absent from sealed dispatch");
		final body = HxFunctionDecl.getBody(ints.projection.requireSemanticDeclaration().getSourceDeclaration());
		body.push(SExpr(EInt(99), HxPos.unknown()));
		rejects(() -> intRead.assertCurrent(), "typed body revision mismatch");
		body.pop();
		intRead.assertCurrent();
		Sys.println("CPP_GENERIC_METHOD_CONTEXT:OWNERSHIP:PASS");
	}

	static function main():Void {
		ownership();
		M14CppManagedStartupExecutionTest.runFixture({
			sourceRoot: "test/fixtures/cpp_generic_method_context_seed",
			output: ".tmp/cpp-generic-method-context",
			observer: "test/cpp_managed_heap/GenericFieldObserver.cpp"
		});
		Sys.println("CPP_GENERIC_METHOD_CONTEXT:PASS");
	}
}
