import backend.cpp.CppManagedClassStorage;
import backend.cpp.CppTypedProgramProjection;
import backend.cpp.CppManagedProgramPlan;

/** Applied constructor types must retain exact program, source, and generic binder ownership. */
class M14CppConstructorApplicationTest {
	/** The native observer uses the same authored fixture and exact typed declaration owners. */
	public static function program():CppTypedProgramProjection {
		final source = sys.io.File.getContent("test/oracle/cpp_constructor_application_seed/Main.hx");
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final index = TyperIndex.buildHeaders([resolved]);
		final loader = new ModuleLoader(["."], HxDefineMap.fromRawDefines([]), index, _ -> false);
		loader.markResolvedAlready([resolved]);
		return new CppTypedProgramProjection(new MacroExpandedProgram([TyperStage.typeResolvedModule(resolved, index, loader)], false));
	}

	static function rejects(action:Void->Void, fragment:String):Void {
		try {
			action();
		} catch (failure:haxe.Exception) {
			if (failure.message.indexOf(fragment) >= 0)
				return;
			throw failure;
		}
		throw "invalid constructor application was accepted";
	}

	public static function main():Void {
		final source = program();
		final classes = new CppManagedClassStorage(source);
		final foreign = new CppManagedClassStorage(program());
		final owner = source.requireClass(source.requireClassIdentity("Main"));
		final entries = owner.getFunctions()[0].getConstructorCatalog().getEntries();
		if (entries.length != 2)
			throw "application fixture lost a constructor";
		final plans = [for (entry in entries) classes.constructorApplication(entry)];
		for (index in 0...plans.length) {
			final selected = plans[index];
			final expected = index == 0 ? "primitive:Int" : "primitive:String";
			if (selected.backingType.getSemanticKey() != expected
				|| selected.parameterTypes()[0].getSemanticKey() != expected
				|| !selected.resultType().isVoid())
				throw "applied constructor lost its concrete parameter, backing, or Void completion";
			if (selected.projection.getParameters()[0].getBinding().getType().getTypeParameterIdentity() == null)
				throw "application mutated its authored generic parameter";
			if (selected.identity != classes.constructorApplication(entries[index]).identity)
				throw "application identity is unstable";
			rejects(() -> foreign.constructorApplication(entries[index]), "another program or occurrence");
			if (classes.requireConstructor(entries[index]) != selected.projection)
				throw "constructor admission changed the exact authored body";
		}
		if (plans[0].identity == plans[1].identity || plans[0].projection != plans[1].projection)
			throw "applications must separate storage identity while retaining one authored body";
		if (plans[0].storedBackingType.getSemanticKey() != "nullable:primitive:Int"
			|| plans[1].storedBackingType.getSemanticKey() != "primitive:String")
			throw "generic constructor backing lost its null-preserving storage";
		final integer = plans[0].receiverType;
		final nullableInteger = TyType.nullable(integer);
		final otherInteger = TyType.nominal(new TyNominalTypeId("Main.Other"), [TyType.fromHintText("Int")]);
		if (backend.cpp.CppManagedValueTransfer.accepts(integer, nullableInteger, classes.casts)
			|| !backend.cpp.CppManagedValueTransfer.needsScalarConversion(integer, nullableInteger, classes.casts)
			|| backend.cpp.CppManagedValueTransfer.supports(otherInteger, nullableInteger, classes.casts)
			|| backend.cpp.CppManagedValueTransfer.needsScalarConversion(otherInteger, nullableInteger, classes.casts))
			throw "abstract transfer lost its exact nominal conversion boundary";
		if (classes.casts.appliedAbstractStorage(integer, integer).getSemanticKey() != integer.getSemanticKey())
			throw "concrete abstract storage acquired generic null";
		// Both applications and their direct methods must link in one program.
		new CppManagedProgramPlan(source, "Main").render();
		final other = source.requireClass(source.requireClassIdentity("Main.Other")).getFunctions()[0];
		rejects(() -> plans[0].resolveType(other.getParameters()[0].getBinding().getType()), "unapplied type parameter");
		rejects(() -> new backend.cpp.CppManagedStoragePlan(other, classes, plans[0]), "another function");
		switch entries[0].getExpression() {
			case ENew(_, arguments):
				arguments[0] = EInt(8);
			case _:
				throw "application fixture lost its construction";
		}
		rejects(() -> plans[0].assertCurrent(), "arguments were replaced");
		Sys.println("CPP_CONSTRUCTOR_APPLICATION:PASS");
	}
}
