/** Run complete source handlers and real ValueException construction through the production target. */
class M14CppBoolCatchTest {
	public static function run(mainModule:String):Void {
		final fixture = CppResolvedFixture.load({
			sourceRoot: "test/oracle/cpp_bool_catch_seed",
			mainModule: mainModule,
			requiredModules: ["haxe.Exception", "haxe.ValueException", "BoolCatch"]
		});
		final program = new MacroExpandedProgram(TypedAbstractOperatorLowering.lowerModules(fixture.modules, fixture.index), false);
		ownership(new backend.cpp.CppTypedProgramProjection(program));
		final output = ".tmp/cpp-bool-catch/" + mainModule;
		final result = backend.cpp.CppTargetCore.emit(program, new backend.BackendContext(output, null, mainModule, true, true, fixture.defines));
		if (!result.builtExecutable || Sys.command(result.entryPath, []) != 0)
			throw "Boolean catch source assertions failed";
		CppManagedAssertionFixture.sanitizers(output, "CPP_BOOL_CATCH:" + mainModule, "test/cpp_managed_heap/BoolCatchObserver.cpp",
			"src/" + mainModule + ".cpp");
		Sys.println("CPP_BOOL_CATCH:" + mainModule + ":PASS");
	}

	static function main():Void
		run("Main");

	/** Equal facts from an unregistered use and a modified source body cannot authorize a payload read. */
	static function ownership(program:backend.cpp.CppTypedProgramProjection):Void {
		final classes = new backend.cpp.CppManagedClassStorage(program);
		final owner = program.requireClass(program.requireClassIdentity("BoolCatch"));
		final fn = owner.getFunctions().filter(fn -> fn.requireSemanticDeclaration().getSignature().getName() == "select")[0];
		final catalog = fn.getLocalCatalog();
		final local = catalog.getEntries()
			.filter(local -> local.getBinding().getKind() == CatchVariable
				&& local.getBinding().getType().getSemanticKey() == "primitive:Bool")[0];
		final use = catalog.findCatchUse(local.getBinding().getIdentity().getCanonicalKey());
		final member = classes.catchPayload(use);
		if (member.declaredType.getSemanticKey() != "nominal:Any" || !classes.needsRuntimePredicate())
			throw "catch payload lost its declared opaque storage or nominal predicate";
		final copied = @:privateAccess new TypedCatchUse(use.binding, use.view, use.target, use.conversion, use.payload);
		reject(() -> classes.catchPayload(copied), "another program or implicit use");
		final body = fn.getBody();
		body.push(SExpr(EInt(99), HxPos.unknown()));
		reject(() -> classes.catchPayload(use), "projection was mutated");
		body.pop();
		classes.catchPayload(use);
		final bool = TyType.fromHintText("Bool");
		if (!backend.cpp.CppManagedValueTransfer.accepts(member.declaredType, bool, classes.casts)
			|| backend.cpp.CppManagedValueTransfer.accepts(bool, member.declaredType, classes.casts)
			|| backend.cpp.CppManagedValueTransfer.accepts(TyType.fromHintText("Int"), TyType.fromHintText("String"), classes.casts))
			throw "opaque argument transport admitted an unchecked narrowing conversion";
	}

	static function reject(action:Void->Void, message:String):Void {
		try {
			action();
		} catch (failure:haxe.Exception) {
			if (failure.message.indexOf(message) >= 0)
				return;
			throw failure;
		}
		throw "catch payload accepted foreign or stale ownership";
	}
}
