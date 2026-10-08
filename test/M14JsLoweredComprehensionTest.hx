import backend.js.JsFunctionScope;

/** Compare authored comprehensions through upstream and candidate JavaScript, including exact operation ownership. */
class M14JsLoweredComprehensionTest {
	static function main():Void {
		final fixture = "test/fixtures/js_lowered_comprehension";
		final output = ".tmp/js_lowered_comprehension";
		sys.FileSystem.createDirectory(output);
		final expected = sys.io.File.getContent(fixture + "/expected.stdout");
		run("node_modules/.bin/haxe", ["-cp", fixture, "-main", "Main", "-js", output + "/upstream.js"]);
		if (run("node", [output + "/upstream.js"]) != expected)
			throw "upstream comprehension behavior differs";
		Sys.println("JS_LOWERED_COMPREHENSION_UPSTREAM:PASS");
		final path = fixture + "/Main.hx";
		final module = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
		final args = hxhx.Stage1Compiler.Stage1Args.parse(["-main", "Main"], true);
		final root = hxhx.Stage1Compiler.Stage1Args.getStandardLibraryRoot(args);
		final index = TyperIndex.buildHeaders([module]);
		final loader = new ModuleLoader([root + "/js/_std", root], hxhx.Stage3SetupSupport.buildDefinesMap([], "js", "js-native"), index, null, true);
		loader.markResolvedAlready([module]);
		for (name in ["Class", "Array"])
			if (loader.ensureTypeAvailable(name, "", []) == null)
				throw "missing real provider: " + name;
		final typed = TyperStage.typeResolvedModule(module, index, loader, true);
		final revision = CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity();
		new backend.js.JsBackend().emit(new MacroExpandedProgram([typed], false),
			new backend.BackendContext(output, output + "/candidate.js", "Main", true, false, HxDefineMap.fromRawDefines(["js=1"])));
		if (run("node", [output + "/candidate.js"]) != expected)
			throw "candidate comprehension behavior differs";
		if (CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity() != revision)
			throw "comprehension emission changed typed source";
		checkOwnership(typed);
		Sys.println("JS_LOWERED_COMPREHENSION:PASS");
	}

	/** Copied, foreign, ownerless, and mutated operations cannot borrow an executable's authority. */
	static function checkOwnership(module:TypedModule):Void {
		final functions = [
			for (owner in module.getTypedClasses())
				for (fn in owner.getFunctions())
					if (fn.getDeclaration().getSignature().getName() == "range")
						fn
		];
		if (functions.length != 1)
			throw "missing range owner";
		final projection = TypedBodySource.functionProjection(functions[0]);
		final foreign = TypedBodySource.functionProjection(functions[0]);
		final scope = new JsFunctionScope(new haxe.ds.StringMap());
		scope.setControlProjection(projection);
		final operations = new Array<HxExpr>();
		for (statement in projection.getBody())
			TypedBackendSourceWalk.statement(statement, expression -> {
				if (expression.match(ELoweredControl(ArrayAppend, _, _, _)))
					operations.push(expression);
			}, _ -> {});
		if (operations.length != 1)
			throw "missing original append";
		final operation = operations[0];
		projection.requireExpression(operation);
		reject(() -> foreign.requireExpression(operation));
		reject(() -> backend.js.JsArrayAppendSupport.emit(operation, new JsFunctionScope(new haxe.ds.StringMap()).exprScope()));
		reject(() -> TypedControlStatements.methodStatement(operation, projection.requireRootControlIdentity()));
		switch operation {
			case ELoweredControl(kind, destination, operands, position):
				final copy = HxExpr.ELoweredControl(kind, destination, operands.copy(), position);
				reject(() -> backend.js.JsArrayAppendSupport.emit(copy, scope.exprScope()));
				operands[1] = EInt(99);
				reject(() -> backend.js.JsArrayAppendSupport.emit(operation, scope.exprScope()));
			case _:
				throw "append changed kind";
		}
	}

	static function reject(action:Void->Void):Void {
		try {
			action();
		} catch (_:haxe.Exception) {
			return;
		}
		throw "invalid comprehension operation was accepted";
	}

	/** Bound child processes and preserve their diagnostics for a faithful failure. */
	static function run(command:String, args:Array<String>):String {
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["60", command].concat(args));
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0)
			throw "comprehension observer failed: " + stdout + stderr;
		return stdout;
	}
}
