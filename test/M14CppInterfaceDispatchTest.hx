/** Run interface contracts through authored Haxe, the managed target, and forced collection. */
class M14CppInterfaceDispatchTest {
	static function reject(action:Void->Void, message:String):Void {
		try
			action()
		catch (error:haxe.Exception) {
			if (error.message.indexOf(message) < 0)
				throw error;
			return;
		}
		throw "interface plan accepted invalid evidence: " + message;
	}

	/** Validate the selected bodies before checking their generated execution. */
	static function checkPlan(source:MacroExpandedProgram):backend.cpp.CppManagedProgramPlan {
		final program = new backend.cpp.CppTypedProgramProjection(source);
		final plan = new backend.cpp.CppManagedProgramPlan(program, "Main");
		final classes = @:privateAccess plan.classes;
		final owner = program.requireClass(program.requireClassIdentity("Main"));
		final read = owner.getFunctions().filter(fn -> fn.requireSemanticDeclaration().getSignature().getName() == "read")[0];
		var selected:Null<TypedBackendInstanceCallOccurrence> = null;
		for (statement in read.getBody())
			TypedBackendSourceWalk.statement(statement, expression -> {
				final call = classes.methods.functionInstanceCall(read, expression);
				if (call != null)
					selected = call;
			}, _ -> {});
		if (selected == null)
			throw "interface plan lost its checked call";
		final target = @:privateAccess plan.emitter.resolveInstance(selected, null);
		if (target.entry != null || target.projection.requireSemanticDeclaration().getHasBody() || target.dispatch == null)
			throw "interface signature acquired an executable body";
		final expected = ["Main.Constant", "Main.Counter", "Main.Counter", "Main.Doubled"];
		final actual = target.dispatch.map(entry -> entry.target.projection.requireSemanticDeclaration().getOwner().getCanonicalName());
		actual.sort((left, right) -> left < right ? -1 : left > right ? 1 : 0);
		if (actual.join(",") != expected.join(","))
			throw "interface dispatch admitted an unreachable body or lost an override: " + actual.join(",");
		final readable = TyType.nominal(new TyNominalTypeId("Main.Readable"), []);
		reject(() -> classes.requireType(readable), "interface or native adapter plan");
		reject(() -> new backend.cpp.CppManagedProgramEmitter({
			functions: [
				{
					projection: target.projection,
					application: target.application,
					rootSymbol: "forbidden_interface_body",
					symbolPrefix: "forbidden_"
				}
			],
			output: [],
			classes: classes
		}), "cannot emit a bodyless contract");
		final foreign = new backend.cpp.CppManagedClassStorage(program);
		reject(() -> foreign.methods.instanceApplication(selected), "another program or occurrence");
		final copy = classes.methods.instanceDispatch(selected);
		copy.pop();
		if (classes.methods.instanceDispatch(selected).length != 4)
			throw "caller mutated sealed interface dispatch";
		switch selected.getExpression() {
			case ECall(_, arguments):
				arguments.push(HxExpr.EInt(99));
				reject(() -> classes.methods.instanceDispatch(selected), "marker was mutated");
				arguments.pop();
			case _:
				throw "interface call lost its projected marker";
		}
		program.assertCurrent();
		Sys.println("CPP_INTERFACE_DISPATCH_PLAN:PASS");
		return plan;
	}

	static function main():Void {
		final fixture = CppResolvedFixture.load({sourceRoot: "test/oracle/cpp_interface_dispatch_seed", mainModule: "Main", requiredModules: []});
		final expanded = new MacroExpandedProgram(fixture.modules, false);
		final plan = checkPlan(expanded);
		final output = ".tmp/cpp-interface-dispatch";
		final result = backend.cpp.CppTargetCore.emit(expanded, new backend.BackendContext(output, null, "Main", true, true, fixture.defines));
		if (!result.builtExecutable || Sys.command(result.entryPath, []) != 0)
			throw "interface dispatch did not execute its native assertions";
		final owner = fixture.index.getByFullName("Main");
		final identity = owner.declarationForSignature(owner.staticMethod("callEdge")).getIdentity().getCanonicalKey();
		final target = @:privateAccess plan.emitter.resolve(identity);
		sys.io.File.saveContent(output
			+ "/Bindings.hpp", "#define HXHX_INTERFACE_EDGE "
			+ backend.cpp.CppManagedStaticTarget.sourceSymbol(target)
			+ "\n");
		CppManagedAssertionFixture.sanitizers(output, "CPP_INTERFACE_DISPATCH", "test/cpp_managed_heap/InterfaceDispatchObserver.cpp");
		Sys.println("CPP_INTERFACE_DISPATCH:PASS");
	}
}
