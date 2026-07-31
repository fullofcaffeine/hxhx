import backend.BackendContext;
import backend.js.JsBackend;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Proves that the JS backend consumes exact typed-local projections instead of
	recovering lexical identity from a repeated source name.
**/
class M14JsTypedLocalProjectionIntegrationTest {
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

	static function makeProgram(source:String):MacroExpandedProgram {
		final parsed = ParserStage.parse(source, "Main.hx");
		return MacroStage.expandProgram([TyperStage.typeModule(parsed)], []);
	}

	static function functionProjection(program:MacroExpandedProgram, name:String):TypedBackendFunctionProjection {
		final modules = program.getTypedModules();
		assertTrue(modules.length == 1, "fixture should produce one typed module");
		final classes = modules[0].getBackendProjection().getClasses();
		assertTrue(classes.length == 1, "fixture should produce one projected class");
		for (fn in classes[0].getFunctions())
			if (HxFunctionDecl.getName(fn.getDeclaration()) == name)
				return fn;
		throw "fixture projection is missing Main." + name;
	}

	static function catalogSignature(projection:TypedBackendFunctionProjection):String {
		return [
			for (entry in projection.getLocalCatalog().getEntries())
				entry.getProjectedName() + "=" + entry.getBinding().getCanonicalIdentity()
		].join("\n");
	}

	static function runNode(scriptPath:String):String {
		final process = new sys.io.Process("node", [scriptPath]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		assertTrue(code == 0, "generated JS failed with exit " + code + ": " + stderr);
		return StringTools.trim(stdout);
	}

	static function assertFailClosedCatalog():Void {
		final identity = TyLocalId.forSourceDeclaration("Main.main#projection-fixture", 0, Variable, "value");
		final first = new TyLocalBinding(identity, "value", TyType.fromHintText("Int"), Variable);
		final conflicting = new TyLocalBinding(identity, "value", TyType.fromHintText("String"), Variable);
		var conflictFailed = false;
		try {
			new TypedBackendLocalCatalog([first, conflicting]);
		} catch (_:String) {
			conflictFailed = true;
		}
		assertTrue(conflictFailed, "projection catalog accepted one local identity with conflicting semantic types");

		final catalog = new TypedBackendLocalCatalog([first]);
		final missing = new TyLocalBinding(TyLocalId.forSourceDeclaration("Main.main#projection-fixture", 1, Variable, "other"), "other",
			TyType.fromHintText("Int"), Variable);
		var missingFailed = false;
		try {
			catalog.projectedName(missing);
		} catch (_:String) {
			missingFailed = true;
		}
		assertTrue(missingFailed, "projection catalog accepted a local binding that was not sealed into the function catalog");
	}

	static function assertCompilerTemporaryProjection():Void {
		final position = HxPos.unknown();
		final allocator = new TyCompilerTemporaryAllocator("Main.temporary#0", "projection-fixture-v1", "__fixture_");
		final binding = allocator.allocate("value", TyType.fromHintText("Int"));
		final temporary = TypedExpr.temporary(binding.getSourceName(), "Int", TypedExpr.intLiteral(7, TyType.fromHintText("Int"), position),
			TyType.fromHintText("Int"), position, binding);
		final read = TypedExpr.localRead(binding.getSourceName(), binding.getType(), position, binding);
		final block = TypedExpr.block([temporary, read], binding.getType(), position);
		final sourceFunction = new HxFunctionDecl("temporary", Public, true, [], "Int", [], "", [], position);
		final typedFunction = new TypedFunction("Main", 0, sourceFunction, null, null,
			new TypedFunctionBody([TypedStmt.expressionStmt(block, position)], TypedBodyFingerprint.forStatements([])));
		final projection = TypedBodySource.functionProjection(typedFunction);
		final entries = projection.getLocalCatalog().getEntries();
		assertTrue(entries.length == 1 && entries[0].getBinding().getKind() == CompilerTemporary,
			"compiler temporary was not retained in the backend projection catalog");
		final projectedName = entries[0].getProjectedName();
		switch (HxFunctionDecl.getBody(projection.getDeclaration())[0]) {
			case SExpr(ECall(ECast(ELambda([binder], EIdent(localRead)), _), [EInt(7)]), _):
				assertTrue(binder == projectedName && localRead == projectedName,
					"compiler temporary declaration and read did not share the exact projected transport name");
			case _:
				throw "compiler temporary projection lost its structural declaration/read sequence";
		}
	}

	static function main():Void {
		assertFailClosedCatalog();
		assertCompilerTemporaryProjection();
		final source = [
			"class Main {",
			"  static function echo(parameter:Int):Int {",
			"    return parameter;",
			"  }",
			"  static function main() {",
			"    var value:Int = 1;",
			"    {",
			"      var value:String = \"inner\";",
			"      Sys.println(value);",
			"    }",
			"    Sys.println(value);",
			"  }",
			"}"
		].join("\n");
		final firstProgram = makeProgram(source);
		final firstProjection = functionProjection(firstProgram, "main");
		final repeatedProjection = functionProjection(makeProgram(source), "main");
		assertTrue(catalogSignature(firstProjection) == catalogSignature(repeatedProjection),
			"equivalent typed functions produced different local projection catalogs");
		final parameterProjection = functionProjection(firstProgram, "echo");
		final parameterEntries = parameterProjection.getLocalCatalog().getEntries();
		assertTrue(parameterEntries.length == 1 && parameterEntries[0].getBinding().getKind() == Parameter,
			"function parameter was not retained in the backend projection catalog");
		final projectedParameterName = HxFunctionArg.getName(HxFunctionDecl.getArgs(parameterProjection.getDeclaration())[0]);
		switch (HxFunctionDecl.getBody(parameterProjection.getDeclaration())[0]) {
			case SReturn(EIdent(projectedRead), _):
				assertTrue(projectedRead == projectedParameterName, "function parameter declaration and read did not share the exact projected transport name");
			case _:
				throw "function parameter projection lost its structural return fixture";
		}

		final valueEntries = [
			for (entry in firstProjection.getLocalCatalog().getEntries())
				if (entry.getBinding().getSourceName() == "value") entry
		];
		assertTrue(valueEntries.length == 2, "projection catalog did not retain both shadowed value declarations");
		assertTrue(valueEntries[0].getProjectedName() != valueEntries[1].getProjectedName(),
			"shadowed local declarations received the same backend transport name");
		final valueTypes = [for (entry in valueEntries) entry.getBinding().getType().getSemanticKey()];
		assertTrue(valueTypes.indexOf("primitive:Int") >= 0 && valueTypes.indexOf("primitive:String") >= 0,
			"projection catalog lost the distinct semantic types of shadowed locals");

		final tmpRoot = Path.normalize(".tmp/m14_js_typed_local_projection_" + Std.string(Date.now().getTime()));
		final outDir = Path.join([tmpRoot, "out"]);
		final scriptPath = Path.join([outDir, "main.js"]);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(outDir);
		var failure:Null<String> = null;
		try {
			new JsBackend().emit(firstProgram, new BackendContext(outDir, scriptPath, "Main", true, false, HxDefineMap.fromRawDefines(["js=1", "js-es=5"])));
			final generated = File.getContent(scriptPath);
			assertContains(generated, "var value = 1;", "outer typed binding should keep a readable JS local name");
			assertContains(generated, 'var value_1 = "inner";', "shadowed typed binding should receive a distinct readable JS local name");
			assertTrue(generated.indexOf("__hxhx_local_") < 0, "JS should consume the typed projection catalog instead of leaking transport names into output");
			assertTrue(runNode(scriptPath) == "inner\n1", "generated JS did not preserve inner then outer shadowing behavior");
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
