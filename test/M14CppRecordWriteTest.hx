import TyAnonymousField.TyAnonymousFieldKind;

/** Execute complete authored field-write functions against independently observed native contracts. */
class M14CppRecordWriteTest {
	static function rejected(action:Void->Void, diagnostic:String):Void {
		try {
			action();
		} catch (error:haxe.Exception) {
			if (error.message.indexOf(diagnostic) >= 0)
				return;
			throw error;
		}
		throw "record assignment accepted invalid facts: " + diagnostic;
	}

	/** Mutability and exact occurrence ownership are admission requirements, not emitted-name conventions. */
	static function controls(program:backend.cpp.CppTypedProgramProjection, fn:TypedBackendFunctionProjection):Void {
		final boolean = TyType.fromHintText("Bool");
		final ordinary = TyType.anonymous(["item"], [boolean]);
		rejected(() -> backend.cpp.CppManagedRecordWrite.field(ordinary, "absent"), "exact structural field");
		rejected(() -> backend.cpp.CppManagedRecordWrite.field(boolean, "item"), "exact anonymous receiver");
		for (kind in [
			TyAnonymousField.TyAnonymousFieldKind.Variable(true, "", ""),
			Variable(false, "get", "never"),
			Method([])
		]) {
			final restricted = TyType.declaredAnonymous([
				{
					name: "item",
					type: kind.match(Method(_)) ? TyType.functionType([], boolean) : boolean,
					kind: kind,
					isOptional: false,
					visibility: Public,
					metadata: [],
					position: HxPos.unknown()
				}
			]);
			rejected(() -> backend.cpp.CppManagedRecordWrite.field(restricted, "item"), "ordinary mutable field");
		}
		final plan = new backend.cpp.CppManagedStoragePlan(fn);
		final access = new backend.cpp.CppManagedLocalAccess({
			projection: fn,
			plan: plan,
			owner: Root(fn),
			parameters: [
				for (index in 0...plan.requireFunction(Root(fn)).getParameters().length)
					"argument" + index
			],
			temporaryPrefix: "hxhx_parameters_record_control_"
		});
		rejected(() -> access.requireExpression(EField(ECall(EIdent("receiver"), []), "item")), "not an exact expression");
		final body = fn.getBody();
		body.push(SExpr(EInt(1), HxPos.unknown()));
		rejected(() -> plan.assertCurrent(), "projection was mutated");
		body.pop();
		program.assertCurrent();
	}

	static function main():Void {
		final fixture = CppResolvedFixture.load({sourceRoot: "test/oracle/cpp_record_write_seed", mainModule: "RecordWrite", requiredModules: []});
		final program = new backend.cpp.CppTypedProgramProjection(new MacroExpandedProgram(fixture.modules, false));
		final classes = new backend.cpp.CppManagedClassStorage(program);
		final owner = program.requireClass(program.requireClassIdentity("RecordWrite"));
		controls(program, owner.getFunctions()[0]);
		final functions:Array<backend.cpp.CppManagedProgramEmitter.CppManagedProgramFunction> = [
			for (projection in owner.getFunctions()) {
				final name = projection.requireSemanticDeclaration().getSignature().getName();
				{projection: projection, rootSymbol: "generated_" + name, symbolPrefix: "hxhx_function_" + name};
			}
		];
		final body = new backend.cpp.CppManagedProgramEmitter({
			functions: functions,
			output: [],
			classes: classes,
			casts: classes.casts
		}).render();
		final output = ".tmp/cpp-record-write";
		sys.FileSystem.createDirectory(output);
		new backend.cpp.CppManagedRuntime().publish(output);
		sys.io.File.saveContent(output + "/Generated.hpp", '#include "ManagedCallable.hpp"\n' + classes.render() + "\n" + body);
		program.assertCurrent();
		CppManagedAssertionFixture.sanitizers(output, "CPP_RECORD_WRITE", "test/cpp_managed_heap/RecordWriteObserver.cpp", "Generated.hpp");
		Sys.println("CPP_RECORD_WRITE:PASS");
	}
}
