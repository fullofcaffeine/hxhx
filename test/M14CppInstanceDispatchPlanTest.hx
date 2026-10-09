import backend.cpp.CppManagedClassStorage;
import backend.cpp.CppTypedProgramProjection;

/** A sealed target list keeps exact ownership checks and cannot hide a late allocation. */
class M14CppInstanceDispatchPlanTest {
	static function method(program:CppTypedProgramProjection, owner:String, name:String):TypedBackendFunctionProjection {
		final matches = program.requireClass(program.requireClassIdentity(owner))
			.getFunctions()
			.filter(fn -> fn.requireSemanticDeclaration().getSignature().getName() == name);
		if (matches.length != 1)
			throw "dispatch fixture requires one method " + owner + "." + name;
		return matches[0];
	}

	/** Only the original expression in its original function can register a call. */
	static function calls(storage:CppManagedClassStorage, fn:TypedBackendFunctionProjection):Array<TypedBackendInstanceCallOccurrence> {
		final result = new Array<TypedBackendInstanceCallOccurrence>();
		for (statement in fn.getBody())
			TypedBackendSourceWalk.statement(statement, value -> {
				final call = storage.methods.functionInstanceCall(fn, value);
				if (call != null)
					result.push(call);
			}, _ -> {});
		return result;
	}

	static function rejected(action:Void->Void, message:String):Void {
		try
			action()
		catch (error:haxe.Exception) {
			if (error.message.indexOf(message) < 0)
				throw error;
			return;
		}
		throw "instance dispatch accepted invalid evidence: " + message;
	}

	/** Equal typed revisions do not make independent projection occurrences interchangeable. */
	static function independent(source:MacroExpandedProgram):CppTypedProgramProjection {
		final modules = [
			for (module in source.getTypedModules())
				new TypedModule(module.getParsed(), module.getEnv(), module.getTypedClasses(), module.getRevision(), module.getSourceOrigin(),
					module.getConditionalCompilation(), module.getGeneratedDeclarations())
		];
		final copy = new MacroExpandedProgram(modules, false);
		if (copy.getTypedProgramRevision().getCanonicalIdentity() != source.getTypedProgramRevision().getCanonicalIdentity())
			throw "independent dispatch control changed the typed revision";
		return new CppTypedProgramProjection(copy);
	}

	static function main():Void {
		final path = "test/oracle/cpp_instance_dispatch_seed/Main.hx";
		final module = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
		final source = new MacroExpandedProgram([TyperStage.typeResolvedModule(module, TyperIndex.build([module]))], false);
		final program = new CppTypedProgramProjection(source);
		final storage = new CppManagedClassStorage(program);
		final main = method(program, "Main", "main");
		final allocations = main.getConstructorCatalog().getEntries();
		if (allocations.length != 3)
			throw "dispatch fixture must allocate Base, Child, and Sibling directly";
		for (allocation in allocations)
			storage.constructorApplication(allocation);
		final inherited = method(program, "Main.Base", "inherited");
		final call = calls(storage, inherited)[0];
		final expectedOwners = ["Main.Base", "Main.Child", "Main.Sibling"];
		final planned = storage.methods.instanceDispatch(call);
		if (planned == null || planned.length != expectedOwners.length)
			throw "dispatch did not use exactly the reached allocations";
		for (index in 0...planned.length)
			if (planned[index].application.projection.requireSemanticDeclaration().getOwner().getCanonicalName() != expectedOwners[index])
				throw "dispatch chose the wrong override for its allocation";
		storage.methods.sealInstanceDispatch([{call: call, context: null}]);
		rejected(() -> storage.methods.sealInstanceDispatch([{call: call, context: null}]), "already sealed");
		final copied = storage.methods.instanceDispatch(call);
		copied.pop();
		if (storage.methods.instanceDispatch(call).length != 3)
			throw "consumer mutation changed sealed dispatch";
		storage.constructorApplication(allocations[0]);
		final late = method(program, "Main.Child", "spawn").getConstructorCatalog().getEntries()[0];
		rejected(() -> storage.constructorApplication(late), "allocation discovered after dispatch was sealed");
		final absent = calls(storage, main)[0];
		rejected(() -> storage.methods.instanceDispatch(absent), "absent from sealed dispatch");
		final foreign = independent(source);
		final foreignStorage = new CppManagedClassStorage(foreign);
		final foreignCall = calls(foreignStorage, method(foreign, "Main.Base", "inherited"))[0];
		if (call == foreignCall || call.getExpression() == foreignCall.getExpression())
			throw "independent dispatch control reused the original call";
		rejected(() -> storage.methods.instanceDispatch(foreignCall), "another program or occurrence");
		rejected(() -> calls(storage, method(foreign, "Main.Base", "inherited")), "foreign function owner");
		// Mutating a projected marker must invalidate the cached target lookup.
		switch call.getExpression() {
			case ECall(_, arguments):
				arguments.push(HxExpr.EInt(99));
				rejected(() -> storage.methods.instanceDispatch(call), "marker was mutated");
				arguments.pop();
			case _:
				throw "instance fixture lost its exact call marker";
		}
		// A different method's authored body is part of the same program revision.
		final authored = HxFunctionDecl.getBody(method(program, "Main.Sibling", "read").requireSemanticDeclaration().getSourceDeclaration());
		authored.push(HxStmt.SReturn(HxExpr.EInt(99), HxPos.unknown()));
		rejected(() -> storage.methods.instanceDispatch(call), "typed body revision mismatch");
		authored.pop();
		if (storage.methods.instanceDispatch(call).length != 3)
			throw "restored source lost its exact dispatch plan";
		final projected = planned[1].application.projection.getBody();
		projected.push(HxStmt.SReturn(HxExpr.EInt(99), HxPos.unknown()));
		rejected(() -> storage.methods.instanceDispatch(call), "projection was mutated");
		projected.pop();
		Sys.println("CPP_INSTANCE_DISPATCH_PLAN:PASS");
	}
}
