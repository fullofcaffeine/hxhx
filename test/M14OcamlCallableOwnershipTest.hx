import backend.ocaml.Stage3OcamlCallableProgram;
import backend.ocaml.Stage3OcamlLocalNames;

/** A selected callback body cannot borrow facts from a copied program or another expression. */
class M14OcamlCallableOwnershipTest {
	static function typed():TypedModule {
		final source = "class Main { static function factory():Int->Int return value -> value + 1; static function main():Void { var callback = factory(); callback(7); } }";
		final module = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		return TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
	}

	static function projection(module:TypedModule, name:String):TypedBackendFunctionProjection {
		final fn = module.getTypedClasses()[0].getFunctions().filter(fn -> HxFunctionDecl.getName(fn.getSourceDeclaration()) == name)[0];
		return TypedBodySource.functionProjection(fn);
	}

	static function rejects(expected:String, action:Void->Void):Void {
		try {
			action();
		} catch (error:haxe.Exception) {
			if (error.message.indexOf(expected) < 0)
				throw error;
			return;
		}
		throw "Expected ownership rejection: " + expected;
	}

	static function main():Void {
		final module = typed();
		final program = new Stage3OcamlCallableProgram([module]);
		final body = projection(module, "main");
		final names = new Stage3OcamlLocalNames(body.getLocalCatalog(), false, name -> name);
		final owner = program.bind(body, names);
		if (owner == null)
			throw "The original callback consumer must be selected";
		// Simulate an interrupted emit leaving both callback owners in request state.
		@:privateAccess EmitterStage.currentCallables = program;
		@:privateAccess EmitterStage.currentCallableFunction = owner;
		CompilerRequestStaticState.reset();
		final remainingProgram = @:privateAccess EmitterStage.currentCallables;
		final remainingFunction = @:privateAccess EmitterStage.currentCallableFunction;
		if (remainingProgram != null || remainingFunction != null)
			throw "Request cleanup retained an aborted callback owner";
		final foreign = projection(typed(), "main");
		rejects("another local catalog", () -> program.bind(body, new Stage3OcamlLocalNames(foreign.getLocalCatalog(), false, name -> name)));
		rejects("another typed owner", () -> program.bind(foreign, new Stage3OcamlLocalNames(foreign.getLocalCatalog(), false, name -> name)));
		if (owner.render(EIdent("callback"), _ -> throw "Foreign expression was emitted", _ -> throw "Foreign expression was emitted",
			_ -> throw "Foreign declaration was emitted") != null)
			throw "An equal-looking expression acquired callback authority";
		final factory = projection(module, "factory");
		final factoryOwner = program.bind(factory, new Stage3OcamlLocalNames(factory.getLocalCatalog(), false, name -> name));
		rejects("another statement owner", () -> factoryOwner.returned(SReturn(EIdent("callback"), null), "callback"));
		rejects("another expression owner", () -> factoryOwner.returnedExpression(EIdent("callback"), "callback"));
		var changed = false;
		for (entry in body.requireCaptureCatalog().getCallableExpressions()) {
			if (changed)
				break;
			switch entry.expression {
				case ECall(_, arguments):
					arguments.push(EInt(99));
					changed = true;
				case _:
			}
		}
		if (!changed)
			throw "Expected a mutable projected call for the stale-fact control";
		rejects("projection was mutated", () -> owner.type(TyType.functionType([TyType.fromHintText("Int")], TyType.fromHintText("Int"))));
		final next = typed();
		final nextBody = projection(next, "main");
		if (new Stage3OcamlCallableProgram([next]).bind(nextBody, new Stage3OcamlLocalNames(nextBody.getLocalCatalog(), false, name -> name)) == null)
			throw "A rejected stale request contaminated the next callback program";
		Sys.println("NATIVE_OCAML_CALLABLE_OWNERSHIP:PASS");
	}
}
