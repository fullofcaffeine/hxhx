import backend.cpp.CppManagedClassStorage;
import backend.cpp.CppManagedInstanceField.transportType;
import backend.cpp.CppTypedProgramProjection;

/** Keep field-owned generic applications separate while executing ordinary construction. */
class M14CppGenericInitializerTest {
	static function program():CppTypedProgramProjection {
		final path = "test/fixtures/cpp_generic_initializer_seed/Main.hx";
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
		throw "generic initializer accepted an invalid application";
	}

	static function ownership():Void {
		final source = program();
		final classes = new CppManagedClassStorage(source);
		final box = source.requireClass(source.requireClassIdentity("Main.Box"));
		final projection = box.getFieldInitializers()[0];
		final declaration = box.requireSemanticFacts().requireField(projection.getField());
		final original = declaration.semanticType.getSemanticKey();
		final owner = projection.getField().getOwner();
		final ints = classes.initializerApplication(projection, TyType.nominal(owner, [TyType.fromHintText("Int")]));
		final strings = classes.initializerApplication(projection, TyType.nominal(owner, [TyType.fromHintText("String")]));
		if (ints.identity == strings.identity
			|| ints.resolveType(declaration.semanticType).getSemanticKey() != "primitive:Int"
			|| strings.resolveType(declaration.semanticType).getSemanticKey() != "primitive:String"
			|| transportType(classes.initializerMember(ints)).getSemanticKey() != TyType.nullable(TyType.fromHintText("Int")).getSemanticKey())
			throw "generic initializer mixed applied field storage";
		if (declaration.semanticType.getSemanticKey() != original || !declaration.semanticType.isTypeParameter())
			throw "initializer application changed shared declaration facts";
		rejects(() -> classes.initializerApplication(projection, TyType.nominal(owner, [])), "arity mismatch");
		final leaf = source.requireClass(source.requireClassIdentity("Main.Leaf")).getFieldInitializers()[0].getField().getOwner();
		rejects(() -> classes.initializerApplication(projection, TyType.nominal(leaf, [])), "exact declaring class");
		final foreignProgram = program();
		final foreign = foreignProgram.requireClass(foreignProgram.requireClassIdentity("Main.Box")).getFieldInitializers()[0];
		rejects(() -> classes.initializerApplication(foreign, ints.ownerType), "initializer");
		Sys.println("CPP_GENERIC_INITIALIZER:OWNERSHIP:PASS");
	}

	static function main():Void {
		ownership();
		M14CppManagedStartupExecutionTest.runFixture({
			sourceRoot: "test/fixtures/cpp_generic_initializer_seed",
			output: ".tmp/cpp-generic-initializer",
			observer: "test/cpp_managed_heap/GenericInitializerObserver.cpp"
		});
		Sys.println("CPP_GENERIC_INITIALIZER:PASS");
	}
}
