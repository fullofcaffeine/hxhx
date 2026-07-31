import backend.BackendContext;
import backend.BackendRegistry;
import haxe.ds.StringMap;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Proves that Lua String lowering keeps exact static fields separate from
	same-spelled function locals.

	The field transport name remains `value`, while a nested Int local becomes
	`value_1`. String helper selection consumes each function's exact field-read
	catalog, so a failed output request cannot leave type state for the next one.
**/
class M14LuaTypedFieldProjectionIntegrationTest {
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

	static function commandAvailable(command:String):Bool
		return Sys.command("sh", ["-c", "command -v " + command + " >/dev/null 2>&1"]) == 0;

	static function program():MacroExpandedProgram {
		final source = [
			"class Main {",
			"  static var value:String = \"field\";",
			"  static function upperField():String {",
			"    return value.toUpperCase();",
			"  }",
			"  static function main() {",
			"    Sys.println(value.toUpperCase());",
			"    {",
			"      var value:Int = 7;",
			"      Sys.println(value);",
			"    }",
			"    Sys.println(value.toLowerCase());",
			"    Sys.println(upperField());",
			"  }",
			"}"
		].join("\n");
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final index = TyperIndex.build([resolved]);
		final loader = new ModuleLoader(["."], new StringMap<String>(), index, function(_):Bool return false);
		loader.markResolvedAlready([resolved]);
		return MacroStage.expandProgram([TyperStage.typeResolvedModule(resolved, index, loader, true)], []);
	}

	static function collectExpressionFacts(expression:TypedExpr, facts:Array<String>):Void {
		final field = expression.getFieldInfo();
		facts.push(Std.string(expression.getTag()) + ":" + expression.getTexts().join(",") + ":" + (field == null ? "-" : field.getCanonicalKey())
			+ ":qualified=" + Std.string(expression.getRequiresOwnerQualification()));
		for (child in expression.getExpressions())
			collectExpressionFacts(child, facts);
	}

	static function collectStatementFacts(statement:TypedStmt, facts:Array<String>):Void {
		for (expression in statement.getExpressions())
			collectExpressionFacts(expression, facts);
		for (child in statement.getStatements())
			collectStatementFacts(child, facts);
	}

	static function assertProjection(program:MacroExpandedProgram):Void {
		final typedModule = program.getTypedModules()[0];
		final facts = new Array<String>();
		for (typedClass in typedModule.getTypedClasses())
			for (typedFunction in typedClass.getFunctions())
				for (statement in typedFunction.getBody().getStatements())
					collectStatementFacts(statement, facts);
		final classes = typedModule.getBackendProjection().getClasses();
		assertTrue(classes.length == 1, "fixture should project one class");
		var mainProjection:Null<TypedBackendFunctionProjection> = null;
		var helperProjection:Null<TypedBackendFunctionProjection> = null;
		for (projection in classes[0].getFunctions())
			switch (HxFunctionDecl.getName(projection.getDeclaration())) {
				case "main":
					mainProjection = projection;
				case "upperField":
					helperProjection = projection;
				case _:
			}
		assertTrue(mainProjection != null && helperProjection != null, "fixture lost its main or helper projection");

		final mainField = mainProjection.getFieldReadCatalog().findByProjectedName("value");
		assertTrue(mainField != null, "main projection omitted its exact bare field read: " + facts.join("; "));
		assertTrue(mainField.getField().getCanonicalKey() == "Main#static#value", "main projection selected the wrong field identity");
		assertTrue(mainField.getField().getType().getSemanticKey() == "primitive:String", "main projection lost the field's exact String type");
		final local = mainProjection.getLocalCatalog().findByProjectedName("value_1");
		assertTrue(local != null && local.getBinding().getType().getSemanticKey() == "primitive:Int",
			"shadowing Int local did not receive its reserved deterministic transport name");

		final helperField = helperProjection.getFieldReadCatalog().findByProjectedName("value");
		assertTrue(helperField != null && helperField.getField().getCanonicalKey() == mainField.getField().getCanonicalKey(),
			"helper projection did not receive its own exact field-read catalog");
	}

	static function assertConflictingFactsFail():Void {
		final owner = new TyNominalTypeId("Main");
		final exact = new TyFieldInfo(owner, "Main", "value", TyType.fromHintText("String"), true, true, false, false, true);
		final stale = new TyFieldInfo(owner, "Main", "value", TyType.fromHintText("Int"), true, true, false, false, true);
		var failed = false;
		try {
			new TypedBackendFieldReadCatalog([
				new TypedBackendFieldReadProjection("value", exact),
				new TypedBackendFieldReadProjection("value", stale)
			]);
		} catch (_:Dynamic) {
			failed = true;
		}
		assertTrue(failed, "conflicting exact field facts did not fail before rendering");
	}

	static function emit(program:MacroExpandedProgram, outputDir:String, outputPath:String):String {
		if (!FileSystem.exists(outputDir))
			FileSystem.createDirectory(outputDir);
		BackendRegistry.requireForTarget("lua-native").emit(program, new BackendContext(outputDir, outputPath, "Main", true, false, new StringMap<String>()));
		return File.getContent(outputPath);
	}

	static function runLua(path:String):String {
		final process = new sys.io.Process("lua", [path]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		assertTrue(code == 0, "generated Lua failed with exit " + code + ": " + stderr);
		return StringTools.trim(stdout);
	}

	static function main():Void {
		assertConflictingFactsFail();
		final typedProgram = program();
		assertProjection(typedProgram);
		final tmpRoot = Path.normalize(".tmp/m14_lua_typed_field_projection_" + Std.string(Date.now().getTime()));
		final directDir = Path.join([tmpRoot, "direct"]);
		final directPath = Path.join([directDir, "Main.lua"]);
		final repeatedDir = Path.join([tmpRoot, "repeated"]);
		final repeatedPath = Path.join([repeatedDir, "Main.lua"]);
		final afterFailureDir = Path.join([tmpRoot, "after-failure"]);
		final afterFailurePath = Path.join([afterFailureDir, "Main.lua"]);
		deleteRecursive(tmpRoot);

		var failure:Null<String> = null;
		try {
			final direct = emit(typedProgram, directDir, directPath);
			final repeated = emit(program(), repeatedDir, repeatedPath);
			assertTrue(direct == repeated, "equivalent Lua requests produced different exact field-projection output");
			assertContains(direct, 'local value = "field"', "static field should retain its bare transport name");
			assertContains(direct, "local value_1 = 7", "shadowing local should not replace the field transport name");
			assertContains(direct, "print(__hxhx_string_to_upper_case(value))", "main field read should select the Lua String helper from exact field facts");
			assertContains(direct, "print(__hxhx_string_to_lower_case(value))", "field read after the nested local should retain exact String behavior");
			assertContains(direct, "return __hxhx_string_to_upper_case(value)", "helper field read should select the Lua String helper from its own catalog");

			final blockedPath = Path.join([tmpRoot, "blocked.lua"]);
			FileSystem.createDirectory(blockedPath);
			var failedWrite = false;
			try {
				emit(program(), tmpRoot, blockedPath);
			} catch (_:Dynamic) {
				failedWrite = true;
			}
			assertTrue(failedWrite, "fixture output-path failure did not occur");

			final afterFailure = emit(program(), afterFailureDir, afterFailurePath);
			assertTrue(afterFailure == direct, "a failed Lua request changed the next exact field-projection output");
			if (commandAvailable("lua"))
				assertTrue(runLua(afterFailurePath) == "FIELD\n7\nfield\nFIELD", "generated Lua did not preserve field/local/helper behavior");
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
