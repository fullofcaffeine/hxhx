import backend.BackendContext;
import backend.BackendRegistry;
import haxe.ds.StringMap;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Proves that C# Dynamic-call lowering consumes exact typed-local projections.

	The fixture reuses `value` for an outer Dynamic local and an inner String
	local, then also passes a Dynamic parameter through a support method. Only
	the exact Dynamic bindings may select reflection dispatch. Repeated requests
	and a failed output write must not change later generated source.
**/
class M14CsTypedDynamicLocalProjectionIntegrationTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function assertContains(haystack:String, needle:String, message:String):Void {
		if (haystack.indexOf(needle) < 0)
			throw message + " (missing `" + needle + "`)";
	}

	static function assertNotContains(haystack:String, needle:String, message:String):Void {
		if (haystack.indexOf(needle) >= 0)
			throw message + " (unexpected `" + needle + "`)";
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

	static function helperSource():String {
		return [
			"class Helper {",
			"  public static function dynamicCall(value:Dynamic):Dynamic {",
			"    return value.test();",
			"  }",
			"}",
		].join("\n");
	}

	static function program():MacroExpandedProgram {
		final mainSource = [
			"class Main {",
			"  static function dynamicCall(value:Dynamic):Dynamic {",
			"    return value.test();",
			"  }",
			"  static function castDynamicCall(value:Dynamic):Dynamic {",
			"    return cast(value, Dynamic).test();",
			"  }",
			"  static function main() {",
			"    var value:Dynamic = getType();",
			"    {",
			"      var value:String = \"inner\";",
			"      Sys.println(value.toUpperCase());",
			"    }",
			"    Sys.println(Std.string(value.test()));",
			"    Sys.println(Std.string(dynamicCall(value)));",
			"    Sys.println(Std.string(castDynamicCall(value)));",
			"    Sys.println(Std.string(Helper.dynamicCall(value)));",
			"  }",
			"  static function getType():Dynamic {",
			"    return null;",
			"  }",
			"}"
		].join("\n");
		return MacroStage.expandProgram([
			TyperStage.typeModule(ParserStage.parse(mainSource, "Main.hx")),
			TyperStage.typeModule(ParserStage.parse(helperSource(), "Helper.hx"))
		], []);
	}

	static function supportProgram():MacroExpandedProgram {
		return MacroStage.expandProgram([TyperStage.typeModule(ParserStage.parse(helperSource(), "Helper.hx"))], []);
	}

	static function functionProjection(program:MacroExpandedProgram, className:String, name:String):TypedBackendFunctionProjection {
		final modules = program.getTypedModules();
		assertTrue(modules.length == 2, "fixture should produce main and helper typed modules");
		for (module in modules)
			for (cls in module.getBackendProjection().getClasses())
				if (HxClassDecl.getName(cls.getDeclaration()) == className)
					for (fn in cls.getFunctions())
						if (HxFunctionDecl.getName(fn.getDeclaration()) == name)
							return fn;
		throw "fixture projection is missing " + className + "." + name;
	}

	static function emit(outputDir:String):{entry:String, support:String} {
		final defines = new StringMap<String>();
		defines.set("no-compilation", "1");
		final executableDir = Path.join([outputDir, "executable"]);
		BackendRegistry.requireForTarget("cs-native").emit(program(), new BackendContext(executableDir, null, "Main", true, true, defines));
		final libraryDir = Path.join([outputDir, "library"]);
		BackendRegistry.requireForTarget("cs-native")
			.emit(supportProgram(), new BackendContext(libraryDir, null, "Helper", false, false, new StringMap<String>()));
		return {
			entry: File.getContent(Path.join([executableDir, "src", "__HxMain.cs"])),
			support: File.getContent(Path.join([libraryDir, "src", "Helper.cs"]))
		};
	}

	static function main():Void {
		final firstProgram = program();
		final mainProjection = functionProjection(firstProgram, "Main", "main");
		final valueEntries = [
			for (entry in mainProjection.getLocalCatalog().getEntries())
				if (entry.getBinding().getSourceName() == "value") entry
		];
		assertTrue(valueEntries.length == 2, "main projection did not retain both shadowed value declarations");
		assertTrue(valueEntries[0].getProjectedName() != valueEntries[1].getProjectedName(),
			"Dynamic and String locals received the same backend transport name");
		final valueTypes = [for (entry in valueEntries) entry.getBinding().getType()];
		assertTrue(valueTypes.filter(type -> type.isDynamic()).length == 1, "main projection did not retain exactly one Dynamic value binding");
		assertTrue(valueTypes.filter(type -> type.getSemanticKey() == "primitive:String").length == 1,
			"main projection did not retain exactly one String value binding");

		final mainHelperEntries = functionProjection(firstProgram, "Main", "dynamicCall").getLocalCatalog().getEntries();
		assertTrue(mainHelperEntries.length == 1
			&& mainHelperEntries[0].getBinding().getKind() == Parameter
			&& mainHelperEntries[0].getBinding().getType().isDynamic(),
			"main static helper projection did not retain its exact Dynamic parameter");
		final helperEntries = functionProjection(firstProgram, "Helper", "dynamicCall").getLocalCatalog().getEntries();
		assertTrue(helperEntries.length == 1
			&& helperEntries[0].getBinding().getKind() == Parameter
			&& helperEntries[0].getBinding().getType().isDynamic(),
			"support method projection did not retain its exact Dynamic parameter");

		final tmpRoot = Path.normalize(".tmp/m14_cs_typed_dynamic_local_projection_" + Std.string(Date.now().getTime()));
		final directDir = Path.join([tmpRoot, "direct"]);
		final repeatedDir = Path.join([tmpRoot, "repeated"]);
		final afterFailureDir = Path.join([tmpRoot, "after-failure"]);
		deleteRecursive(tmpRoot);

		var failure:Null<String> = null;
		try {
			final direct = emit(directDir);
			final repeated = emit(repeatedDir);
			assertTrue(direct.entry == repeated.entry && direct.support == repeated.support,
				"equivalent C# requests produced different strict-projection output");
			assertContains(direct.entry, "dynamic value = global::Main.getType();", "outer Dynamic binding should retain its exact projected declaration");
			assertContains(direct.entry, "var value_1 = \"inner\";", "inner String binding should retain its distinct projected declaration");
			assertContains(direct.entry, "global::hxhx.__HxRuntime.callField((object)value, \"test\")",
				"outer Dynamic binding should select reflection dispatch");
			assertContains(direct.entry,
				"public static object dynamicCall(object value) {\n    return global::hxhx.__HxRuntime.callField((object)value, \"test\");",
				"main static helper Dynamic parameter should select reflection dispatch from its own function catalog");
			assertContains(direct.entry,
				"public static object castDynamicCall(object value) {\n    return global::hxhx.__HxRuntime.callField((object)value, \"test\");",
				"an explicit cast around the exact Dynamic parameter should preserve reflection dispatch");
			assertNotContains(direct.entry, "global::hxhx.__HxRuntime.callField((object)value_1",
				"inner String binding must not borrow the outer Dynamic binding's call policy");
			assertContains(direct.support, "global::hxhx.__HxRuntime.callField((object)value, \"test\")",
				"support method Dynamic parameter should select reflection dispatch from its own function catalog");

			final blockedOutputDir = Path.join([tmpRoot, "blocked"]);
			File.saveContent(blockedOutputDir, "not-a-directory");
			var failedWrite = false;
			try {
				emit(blockedOutputDir);
			} catch (_:Dynamic) {
				failedWrite = true;
			}
			assertTrue(failedWrite, "fixture output-directory failure did not occur");

			final afterFailure = emit(afterFailureDir);
			assertTrue(afterFailure.entry == direct.entry && afterFailure.support == direct.support,
				"a failed C# request changed the next strict-projection output");
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
