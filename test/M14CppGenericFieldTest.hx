/** Native generic fields preserve applied selection, aliases, conversion boundaries, and traced references. */
class M14CppGenericFieldTest {
	static function rejects(action:Void->Void, fragment:String):Void {
		try {
			action();
		} catch (failure:haxe.Exception) {
			if (failure.message.indexOf(fragment) >= 0)
				return;
			throw failure;
		}
		throw "invalid applied field selection was accepted";
	}

	static function program():backend.cpp.CppTypedProgramProjection {
		final path = "test/fixtures/cpp_generic_field_seed/Main.hx";
		final source = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
		return new backend.cpp.CppTypedProgramProjection(new MacroExpandedProgram([TyperStage.typeResolvedModule(source, TyperIndex.build([source]))], false));
	}

	/** Wrong applications and equal source from another program cannot select this field's physical slot. */
	static function ownership():Void {
		final source = program();
		final classes = new backend.cpp.CppManagedClassStorage(source);
		final main = source.requireClass(source.requireClassIdentity("Main")).getFunctions()[0];
		final calls = main.getConstructorCatalog().getEntries();
		final ints = calls[0].getConstructedType();
		final strings = calls[1].getConstructedType();
		var selected:Null<TypedBackendFieldOccurrence> = null;
		for (statement in main.getBody())
			TypedBackendSourceWalk.statement(statement, expression -> {
				final field = main.findField(expression);
				if (selected == null
					&& field != null
					&& field.getField().getName() == "value"
					&& field.getType().getSemanticKey() == "primitive:Int")
					selected = field;
			}, _ -> {});
		if (selected == null)
			throw "generic field control lost its exact Int occurrence";
		final field = selected;
		final member = classes.member(field, ints, field.getType());
		if (!member.declaredType.isTypeParameter()
			|| backend.cpp.CppManagedInstanceField.transportType(member).getSemanticKey() != "nullable:primitive:Int")
			throw "generic field conflated declared type and physical transport";
		rejects(() -> classes.member(field, strings, field.getType()), "exact applied type");
		rejects(() -> classes.member(field, ints, TyType.fromHintText("String")), "concrete occurrence type");
		rejects(() -> classes.member(field, strings, TyType.fromHintText("String")), "concrete occurrence type");
		rejects(() -> new backend.cpp.CppManagedClassStorage(program()).member(field, ints, field.getType()), "exact declaration");
		final body = HxFunctionDecl.getBody(main.requireSemanticDeclaration().getSourceDeclaration());
		body.push(SExpr(EInt(99), HxPos.unknown()));
		rejects(() -> classes.member(field, ints, field.getType()), "typed body revision mismatch");
		body.pop();
		classes.member(field, ints, field.getType());
		for (wrong in ["Dynamic", "Int", "String", "Null<Int>"])
			if (backend.cpp.CppManagedValueTransfer.needsScalarConversion(TyType.fromHintText("Bool"), TyType.fromHintText(wrong)))
				throw "Boolean conversion accepted an unrelated source type";
		Sys.println("CPP_GENERIC_FIELD:OWNERSHIP:PASS");
	}

	static function main():Void {
		ownership();
		M14CppManagedStartupExecutionTest.runFixture({
			sourceRoot: "test/fixtures/cpp_generic_field_seed",
			output: ".tmp/cpp-generic-field",
			observer: "test/cpp_managed_heap/GenericFieldObserver.cpp"
		});
		Sys.println("CPP_GENERIC_FIELD:PASS");
	}
}
