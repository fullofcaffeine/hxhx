import backend.cpp.CppManagedClassStorage;
import backend.cpp.CppTypedProgramProjection;

/** Stored methods must retain their exact executable owner through dispatch sealing. */
class M14CppBoundMethodOwnershipTest {
	static function program():CppTypedProgramProjection {
		final source = 'class Main { static function main():Void { final box = new Box(7); final read = box.read; read(); box.read(); } }'
			+ ' class Box { var value:Int; public function new(value:Int) { this.value = value; } public function read():Int { return value; } }';
		final parsed = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		return new CppTypedProgramProjection(new MacroExpandedProgram([TyperStage.typeResolvedModule(parsed, TyperIndex.build([parsed]))], false));
	}

	static function mainFunction(program:CppTypedProgramProjection):TypedBackendFunctionProjection {
		return program.requireClass(program.requireClassIdentity("Main")).getFunctions()[0];
	}

	static function values(storage:CppManagedClassStorage, fn:TypedBackendFunctionProjection):Array<TypedBackendMethodOccurrence> {
		final result = new Array<TypedBackendMethodOccurrence>();
		for (statement in fn.getBody())
			TypedBackendSourceWalk.statement(statement, expression -> {
				final found = storage.methods.bound.functionValue(fn, expression);
				if (found != null)
					result.push(found);
			}, _ -> {});
		return result;
	}

	static function rejects(action:Void->Void, diagnostic:String):Void {
		try
			action()
		catch (error:haxe.Exception) {
			if (error.message.indexOf(diagnostic) < 0)
				throw error;
			return;
		}
		throw "bound method accepted invalid ownership: " + diagnostic;
	}

	static function main():Void {
		final source = program();
		final storage = new CppManagedClassStorage(source);
		final fn = mainFunction(source);
		for (allocation in fn.getConstructorCatalog().getEntries())
			storage.constructorApplication(allocation);
		final selected = values(storage, fn);
		if (selected.length != 1)
			throw "stored method discovery included a direct call or lost the value read";
		final occurrence = selected[0];
		final bound = storage.methods.bound;
		final application = bound.application(occurrence, null);
		if (application.projection.requireSemanticDeclaration() != occurrence.getDeclaration()
			|| application.resultType().getSemanticKey() != "primitive:Int")
			throw "stored method changed its selected declaration or result";
		switch occurrence.getExpression() {
			case EField(receiver, name):
				if (bound.functionValue(fn, HxExpr.EField(receiver, name)) != null)
					throw "same-shaped copied expression borrowed stored-method evidence";
			case _:
				throw "stored method lost its projected field expression";
		}
		final foreign = program();
		final other = new CppManagedClassStorage(foreign);
		final foreignOccurrence = values(other, mainFunction(foreign))[0];
		rejects(() -> bound.application(foreignOccurrence, null), "another program or occurrence");
		rejects(() -> other.methods.bound.application(occurrence, null), "another program or occurrence");
		rejects(() -> bound.functionValue(mainFunction(foreign), foreignOccurrence.getExpression()), "foreign function owner");
		bound.seal([{occurrence: occurrence, context: null}]);
		rejects(() -> bound.seal([{occurrence: occurrence, context: null}]), "already sealed");
		bound.dispatch(occurrence, null).pop();
		if (bound.dispatch(occurrence, null).length != 1)
			throw "consumer mutation changed sealed bound-method dispatch";
		final authored = HxFunctionDecl.getBody(application.projection.requireSemanticDeclaration().getSourceDeclaration());
		authored.push(HxStmt.SReturn(HxExpr.EInt(99), HxPos.unknown()));
		rejects(() -> bound.dispatch(occurrence, null), "typed body revision mismatch");
		authored.pop();
		final projected = fn.getBody();
		projected.push(HxStmt.SReturn(HxExpr.EInt(99), HxPos.unknown()));
		rejects(() -> bound.dispatch(occurrence, null), "projection was mutated");
		projected.pop();
		if (bound.dispatch(occurrence, null).length != 1)
			throw "rejected mutation contaminated the restored method plan";
		Sys.println("CPP_BOUND_METHOD_OWNERSHIP:PASS");
	}
}
