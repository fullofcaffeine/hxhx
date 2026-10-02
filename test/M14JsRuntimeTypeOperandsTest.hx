import sys.io.File;

/** Preserve inherited and unrelated runtime class tests through real JavaScript execution. */
class M14JsRuntimeTypeOperandsTest {
	static function main():Void {
		final root = "test/fixtures/js_runtime_type_operands";
		final expected = File.getContent(root + "/expected.stdout");
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["60", "node_modules/.bin/haxe", "-cp", root, "--run", "Main"]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final status = process.exitCode();
		process.close();
		if (status != 0 || stdout != expected)
			throw "upstream class-test contract differs: " + stdout + stderr;
		final path = root + "/Main.hx";
		assertUpstreamJs(File.getContent(path), expected);
		final module = new ResolvedModule("Main", path, ParserStage.parse(File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		JsRuntimeFixture.assertRuntime(typed, "Main", expected);
		assertOwnership(typed, module);
		assertUnsupportedPublication();
		Sys.println("JS_RUNTIME_TYPE_OPERANDS:PASS");
	}

	/** Use Node's console only as the upstream JS observer; keep every tested expression intact. */
	static function assertUpstreamJs(source:String, expected:String):Void {
		final directory = ".tmp/js_runtime_type_upstream_" + Date.now().getTime();
		sys.FileSystem.createDirectory(directory);
		File.saveContent(directory + "/Main.hx", StringTools.replace(source, "Sys.println(", "js.Browser.console.log("));
		run("node_modules/.bin/haxe", ["-cp", directory, "-main", "Main", "-js", directory + "/main.js"]);
		if (run("node", [directory + "/main.js"]) != expected)
			throw "upstream JavaScript runtime type behavior differs; retained " + directory;
		for (file in sys.FileSystem.readDirectory(directory))
			sys.FileSystem.deleteFile(directory + "/" + file);
		sys.FileSystem.deleteDirectory(directory);
	}

	static function run(command:String, arguments:Array<String>):String {
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["60", command].concat(arguments));
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final status = process.exitCode();
		process.close();
		if (status != 0)
			throw "runtime type observer failed: " + stdout + stderr;
		return stdout;
	}

	/** Identical text cannot lend another function or program its occurrence authority. */
	static function assertOwnership(typed:TypedModule, module:ResolvedModule):Void {
		final program = MacroStage.expandProgram([typed], []);
		final plan = new backend.js.JsRuntimeTypePlan(program, new backend.js.JsClassInheritancePlan(program));
		final secondProgram = MacroStage.expandProgram([typed], []);
		reject(() -> new backend.js.JsRuntimeTypePlan(program, new backend.js.JsClassInheritancePlan(secondProgram)), "another typed program");
		final owner = typed.getBackendProjection().getClasses()[0];
		var selected:Null<TypedBackendFunctionProjection> = null;
		var other:Null<TypedBackendFunctionProjection> = null;
		for (fn in owner.getFunctions()) {
			if (HxFunctionDecl.getName(fn.getDeclaration()) == "main")
				selected = fn;
			if (HxFunctionDecl.getName(fn.getDeclaration()) == "effect")
				other = fn;
		}
		if (selected == null || other == null)
			throw "runtime type fixture lost its executable owners";
		final entry = selected.getRuntimeTypeCatalog().getEntries()[0];
		final scope = plan.forFunction(selected);
		if (scope.requireOccurrence(entry.getExpression()) != entry)
			throw "runtime type plan lost its exact occurrence";
		reject(() -> plan.forFunction(other).requireOccurrence(entry.getExpression()), "absent from the current function projection");
		final copy:HxExpr = switch (entry.getExpression()) {
			case ECall(callee, arguments): ECall(callee, arguments.copy());
			case _: throw "runtime type test lost its marker";
		};
		reject(() -> scope.requireOccurrence(copy), "absent from the current function projection");
		final foreign = TyperStage.typeResolvedModule(module, TyperIndex.build([module])).getBackendProjection().getClasses()[0].getFunctions()[0];
		reject(() -> plan.forFunction(foreign), "foreign function projection");
		switch (entry.getExpression()) {
			case ECall(_, arguments):
				final original = arguments[0];
				arguments[0] = ENull;
				reject(() -> scope.requireOccurrence(entry.getExpression()), "marker was mutated");
				arguments[0] = original;
			case _:
				throw "runtime type test lost its marker";
		}
		Sys.println("JS_RUNTIME_TYPE_OWNERSHIP:PASS");
	}

	static function reject(action:Void->Void, message:String):Void {
		try {
			action();
		} catch (error:haxe.Exception) {
			if (error.message.indexOf(message) < 0)
				throw error;
			return;
		}
		throw "runtime type boundary accepted invalid input: " + message;
	}

	/** Unsupported core objects must leave an existing JavaScript artifact untouched. */
	static function assertUnsupportedPublication():Void {
		final directory = ".tmp/js_runtime_type_admission_" + Date.now().getTime();
		sys.FileSystem.createDirectory(directory);
		final output = directory + "/existing.js";
		File.saveContent(output, "previous-output\n");
		for (primitive in ["Int", "Float", "Bool"]) {
			final source = "class Main { static function main():Void { var selected = " + primitive + "; } }";
			final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
			final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
			final program = MacroStage.expandProgram([typed], []);
			final context = new backend.BackendContext(directory, output, "Main", false, false, new haxe.ds.StringMap<String>());
			reject(() -> new backend.js.JsTargetCore().emit(program, context), "JavaScript core runtime type operand is unsupported");
			if (File.getContent(output) != "previous-output\n" || sys.FileSystem.readDirectory(directory).length != 1)
				throw "JavaScript changed existing output before rejecting " + primitive;
		}
		sys.FileSystem.deleteFile(output);
		sys.FileSystem.deleteDirectory(directory);
		Sys.println("JS_RUNTIME_TYPE_PUBLICATION:PASS");
	}
}
