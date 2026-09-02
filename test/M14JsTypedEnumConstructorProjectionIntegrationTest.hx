import backend.BackendContext;
import backend.js.JsBackend;
import backend.js.JsExprEmitter;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import TypedExactEnumConstructorSource.TypedExactEnumConstructorCall;
import TypedExpr.TypedExprTag;

/**
	Proves that native JavaScript consumes the exact enum constructor selected by
	shared typing.

	The fixture starts from ordinary Haxe source. It checks the typed declaration
	and projected transport marker before it emits and runs JavaScript, so a
	backend cannot pass by rediscovering a constructor from its source spelling.
**/
class M14JsTypedEnumConstructorProjectionIntegrationTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function assertContains(haystack:String, needle:String, message:String):Void {
		if (haystack.indexOf(needle) < 0)
			throw message + " (missing `" + needle + "`)";
	}

	static function deleteRecursive(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				deleteRecursive(Path.join([path, entry]));
			FileSystem.deleteDirectory(path);
			return;
		}
		FileSystem.deleteFile(path);
	}

	static function exactSource():String {
		return [
			"package demo;",
			"",
			"enum Alpha {",
			"  AlphaValue(value:Int, label:String);",
			"}",
			"",
			"class Main {",
			"  static function main() {",
			"    var exact = Alpha.AlphaValue(7, \"a\");",
			"    js.Syntax.code(\"console.log({0})\", Std.string(exact));",
			"    js.Syntax.code(\"console.log({0})\", exact.match(Alpha.AlphaValue(7, \"a\")));",
			"    js.Syntax.code(\"console.log({0})\", exact.match(Alpha.AlphaValue(8, \"a\")));",
			"  }",
			"}"
		].join("\n");
	}

	static function ambiguousSource():String {
		return [
			"package demo;",
			"",
			"enum First {",
			"  Shared(value:Int);",
			"}",
			"",
			"enum Second {",
			"  Shared(value:Int);",
			"}",
			"",
			"class Main {",
			"  static function main() {",
			"    var ambiguous = Shared(1);",
			"  }",
			"}"
		].join("\n");
	}

	static function program(source:String):MacroExpandedProgram {
		final filePath = "demo/Main.hx";
		final parsed = ParserStage.parse(source, filePath);
		final resolved = new ResolvedModule("demo.Main", filePath, parsed);
		final index = TyperIndex.build([resolved]);
		return MacroStage.expandProgram([TyperStage.typeResolvedModule(resolved, index)], []);
	}

	static function variableInitializer(program:MacroExpandedProgram, name:String):TypedExpr {
		for (module in program.getTypedModules())
			for (typedClass in module.getTypedClasses())
				for (typedFunction in typedClass.getFunctions())
					for (statement in typedFunction.getBody().getStatements())
						if (statement.getNames().length > 0 && statement.getNames()[0] == name && statement.getExpressions().length == 1)
							return statement.getExpressions()[0];
		throw "fixture is missing variable initializer " + name;
	}

	static function mainProjection(program:MacroExpandedProgram):TypedBackendFunctionProjection {
		for (module in program.getTypedModules())
			for (typedClass in module.getBackendProjection().getClasses())
				if (HxClassDecl.getName(typedClass.getDeclaration()) == "Main")
					for (fn in typedClass.getFunctions())
						if (HxFunctionDecl.getName(fn.getDeclaration()) == "main")
							return fn;
		throw "fixture projection is missing demo.Main.main";
	}

	static function projectedExactConstructor(program:MacroExpandedProgram):TypedExactEnumConstructorCall {
		for (statement in HxFunctionDecl.getBody(mainProjection(program).getDeclaration())) {
			switch (statement) {
				case SVar("exact", _, initializer, _):
					final exact = TypedExactEnumConstructorSource.decode(initializer);
					if (exact != null)
						return exact;
				case _:
			}
		}
		throw "typed projection did not retain the exact enum-constructor marker";
	}

	static function runNode(scriptPath:String):String {
		final process = new sys.io.Process("node", [scriptPath]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final exitCode = process.exitCode();
		process.close();
		assertTrue(exitCode == 0, "generated JavaScript failed with exit " + exitCode + ": " + stderr);
		return StringTools.trim(stdout);
	}

	static function runProcess(command:String, arguments:Array<String>, label:String):String {
		final process = new sys.io.Process(command, arguments);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final exitCode = process.exitCode();
		process.close();
		assertTrue(exitCode == 0, label + " failed with exit " + exitCode + ": " + stderr);
		return StringTools.trim(stdout);
	}

	static function compileOracle(tmpRoot:String):String {
		final sourceDir = Path.join([tmpRoot, "oracle-source", "demo"]);
		final outputPath = Path.join([tmpRoot, "oracle.js"]);
		FileSystem.createDirectory(Path.join([tmpRoot, "oracle-source"]));
		FileSystem.createDirectory(sourceDir);
		File.saveContent(Path.join([sourceDir, "Main.hx"]), exactSource());
		final haxe = Path.normalize("node_modules/.bin/haxe");
		assertTrue(runProcess(haxe, ["--version"], "Haxe oracle version") == "4.3.7", "fixture requires the pinned Haxe 4.3.7 oracle");
		runProcess(haxe, [
			"-cp",
			Path.join([tmpRoot, "oracle-source"]),
			"-main",
			"demo.Main",
			"-js",
			outputPath
		], "Haxe 4.3.7 JS oracle");
		return runNode(outputPath);
	}

	static function assertMissingCarrierFailsClosed():Void {
		final marker = TypedExactEnumConstructorSource.encode("missing.Enum", "missing.Enum", "missing.Enum#static:Value(Int)->missing.Enum@0", "Value",
			EField(EIdent("Enum"), "Value"), [EInt(1)]);
		final scope:backend.js.JsEmitScope = {
			resolveLocal: function(_):Null<String> return null,
			resolveClassRef: function(_):Null<String> return null,
			resolveSuperClassRef: function():Null<String> return null,
		};
		var failure = "";
		try {
			JsExprEmitter.emit(marker, scope);
		} catch (message:String) {
			failure = message;
		}
		assertContains(failure, "[js-native:exact_enum_constructor] missing carrier for missing.Enum#static:Value(Int)->missing.Enum@0",
			"missing exact enum carriers must fail with a deterministic compiler diagnostic");
	}

	static function main():Void {
		final typedProgram = program(exactSource());
		final initializer = variableInitializer(typedProgram, "exact");
		assertTrue(initializer.getTag() == TypedExprTag.Call, "enum construction was not retained as a typed call");
		final declaration = initializer.getDeclaration();
		assertTrue(declaration != null && declaration.getIsEnumConstructor(), "shared typing did not select an enum constructor declaration");
		assertTrue(declaration.getOwner().getCanonicalName() == "demo.Main.Alpha", "typed enum constructor lost its canonical owner");
		assertTrue(declaration.getModulePath() == "demo.Main", "typed enum constructor lost its module identity");
		assertTrue(declaration.getSignature().getName() == "AlphaValue", "typed enum constructor lost its constructor name");
		assertTrue(initializer.getExpressions().length == 3, "typed enum constructor lost its two ordered arguments");

		final exact = projectedExactConstructor(typedProgram);
		assertTrue(exact.owner == "demo.Main.Alpha", "projected marker lost the exact enum owner");
		assertTrue(exact.modulePath == "demo.Main", "projected marker lost the exact module");
		assertTrue(exact.declaration == declaration.getIdentity().getCanonicalKey(), "projected marker lost the exact declaration identity");
		assertTrue(exact.constructor == "AlphaValue" && exact.arguments.length == 2, "projected marker lost its constructor or ordered argument list");

		final ambiguous = variableInitializer(program(ambiguousSource()), "ambiguous");
		assertTrue(ambiguous.getTag() == TypedExprTag.Call && ambiguous.getDeclaration() == null,
			"an ambiguous bare constructor must not select an owner by traversal order");
		assertMissingCarrierFailsClosed();

		final tmpRoot = Path.normalize(".tmp/m14_js_typed_enum_constructor_projection_" + Std.string(Date.now().getTime()));
		final outDir = Path.join([tmpRoot, "out"]);
		final scriptPath = Path.join([outDir, "main.js"]);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(outDir);
		var failure:Null<String> = null;
		try {
			final oracleOutput = compileOracle(tmpRoot);
			new JsBackend().emit(typedProgram,
				new BackendContext(outDir, scriptPath, "demo.Main", true, false, HxDefineMap.fromRawDefines(["js=1", "js-es=5"])));
			final generated = File.getContent(scriptPath);
			assertContains(generated, '__hx_cls_demo_Alpha.AlphaValue(7, "a")', "JavaScript did not call the exact typed enum constructor");
			assertTrue(generated.indexOf(TypedExactEnumConstructorSource.marker()) < 0, "compiler-owned enum marker leaked into generated JavaScript");
			final nativeOutput = runNode(scriptPath);
			assertTrue(oracleOutput == "AlphaValue(7,a)\ntrue\nfalse", "Haxe 4.3.7 oracle produced unexpected enum behavior");
			assertTrue(nativeOutput == oracleOutput, "native JavaScript did not match Haxe 4.3.7 enum construction, formatting, and matching");
		} catch (message:String) {
			failure = message;
		} catch (error:haxe.Exception) {
			failure = error.message;
		}
		if (failure != null) {
			Sys.println("debug_out=" + tmpRoot);
			throw failure;
		}
		deleteRecursive(tmpRoot);
	}
}
