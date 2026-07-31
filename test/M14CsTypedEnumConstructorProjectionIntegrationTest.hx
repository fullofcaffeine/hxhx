import backend.BackendContext;
import backend.BackendRegistry;
import haxe.ds.StringMap;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import TypedExpr.TypedExprTag;

/**
	Proves that C# enum-constructor calls consume exact typed declarations.

	The real Haxe source uses bare constructors from two enums in one module and
	also calls a constructor from a support method. Typing must attach the
	canonical enum owner before projection. Direct, repeated, and post-failure
	requests must then emit identical qualified C# calls without process-global
	name lookup.
**/
class M14CsTypedEnumConstructorProjectionIntegrationTest {
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

	static function source():String {
		return [
			"package demo;",
			"",
			"enum Alpha {",
			"  AlphaValue(value:Int);",
			"}",
			"",
			"enum Beta {",
			"  BetaValue(value:Int);",
			"}",
			"",
			"class Helper {",
			"  public static function wrap(value:Int):Alpha {",
			"    return AlphaValue(value);",
			"  }",
			"}",
			"",
			"class Main {",
			"  static function make(value:Int):Beta {",
			"    return BetaValue(value);",
			"  }",
			"",
			"  static function main() {",
			"    var alpha = AlphaValue(1);",
			"    var beta = BetaValue(2);",
			"    var qualified = Alpha.AlphaValue(3);",
			"    var helper = Helper.wrap(4);",
			"    var made = make(5);",
			"    Sys.println(Std.string(alpha));",
			"    Sys.println(Std.string(beta));",
			"    Sys.println(Std.string(qualified));",
			"    Sys.println(Std.string(helper));",
			"    Sys.println(Std.string(made));",
			"  }",
			"}"
		].join("\n");
	}

	static function program():MacroExpandedProgram {
		final filePath = "demo/Main.hx";
		final parsed = ParserStage.parse(source(), filePath);
		final resolved = new ResolvedModule("demo.Main", filePath, parsed);
		final index = TyperIndex.build([resolved]);
		return MacroStage.expandProgram([TyperStage.typeResolvedModule(resolved, index)], []);
	}

	static function supportProgram():MacroExpandedProgram {
		final filePath = "demo/Helper.hx";
		final source = [
			"package demo;",
			"",
			"enum Alpha {",
			"  AlphaValue(value:Int);",
			"}",
			"",
			"class Helper {",
			"  public static function wrap(value:Int):Alpha {",
			"    return AlphaValue(value);",
			"  }",
			"}"
		].join("\n");
		final parsed = ParserStage.parse(source, filePath);
		final resolved = new ResolvedModule("demo.Helper", filePath, parsed);
		final index = TyperIndex.build([resolved]);
		return MacroStage.expandProgram([TyperStage.typeResolvedModule(resolved, index)], []);
	}

	static function ambiguousProgram():MacroExpandedProgram {
		final filePath = "demo/Ambiguous.hx";
		final source = [
			"package demo;",
			"",
			"enum First {",
			"  Same(value:Int);",
			"}",
			"",
			"enum Second {",
			"  Same(value:Int);",
			"}",
			"",
			"class Ambiguous {",
			"  static function probe() {",
			"    var ambiguous = Same(1);",
			"    var qualified = First.Same(2);",
			"  }",
			"}"
		].join("\n");
		final parsed = ParserStage.parse(source, filePath);
		final resolved = new ResolvedModule("demo.Ambiguous", filePath, parsed);
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

	static function collectEnumCallsInExpression(expression:TypedExpr, out:Array<TyDeclarationInfo>):Void {
		if (expression.getTag() == TypedExprTag.Call) {
			final declaration = expression.getDeclaration();
			if (declaration != null && declaration.getIsEnumConstructor())
				out.push(declaration);
		}
		for (child in expression.getExpressions())
			collectEnumCallsInExpression(child, out);
	}

	static function collectEnumCallsInStatement(statement:TypedStmt, out:Array<TyDeclarationInfo>):Void {
		for (expression in statement.getExpressions())
			collectEnumCallsInExpression(expression, out);
		for (child in statement.getStatements())
			collectEnumCallsInStatement(child, out);
	}

	static function exactEnumDeclarations(program:MacroExpandedProgram):Array<TyDeclarationInfo> {
		final out = new Array<TyDeclarationInfo>();
		for (module in program.getTypedModules())
			for (typedClass in module.getTypedClasses())
				for (typedFunction in typedClass.getFunctions())
					for (statement in typedFunction.getBody().getStatements())
						collectEnumCallsInStatement(statement, out);
		return out;
	}

	/**
		Prove the source-shaped marker remains transparent outside C# lowering.

		Other targets still consume the original source call, and PHP dependency
		discovery still observes its owner/member names before rendering support
		classes.
	**/
	static function assertCrossTargetFallback():Void {
		final exact = TypedExactEnumConstructorSource.encode("demo.Main.Alpha", "demo.Main", "demo.Main.Alpha#static:AlphaValue(Int)->demo.Main.Alpha@0",
			"AlphaValue", EField(EIdent("Alpha"), "AlphaValue"), [EInt(7)]);
		final python = @:privateAccess backend.source.SourceTargetCommon.renderExpr(backend.source.SourceNativeTarget.Python, exact);
		assertTrue(python == "Alpha.AlphaValue(7)", "non-C# rendering did not recover the original enum-constructor call");
		final referenced = new Map<String, Bool>();
		@:privateAccess backend.source.SourceTargetCommon.phpRecordReferencedMemberExpr(exact, referenced);
		assertTrue(referenced.exists("Alpha") && referenced.exists("AlphaValue"),
			"PHP dependency discovery could not see through the exact enum-constructor marker");
	}

	static function emit(outputDir:String):{entry:String, helper:String} {
		final defines = new StringMap<String>();
		defines.set("no-compilation", "1");
		final executableDir = Path.join([outputDir, "executable"]);
		BackendRegistry.requireForTarget("cs-native").emit(program(), new BackendContext(executableDir, null, "demo.Main", true, true, defines));
		final libraryDir = Path.join([outputDir, "library"]);
		BackendRegistry.requireForTarget("cs-native")
			.emit(supportProgram(), new BackendContext(libraryDir, null, "demo.Helper", false, false, new StringMap<String>()));
		return {
			entry: File.getContent(Path.join([executableDir, "src", "demo", "__HxMain.cs"])),
			helper: File.getContent(Path.join([libraryDir, "src", "demo", "Helper.cs"]))
		};
	}

	static function main():Void {
		assertCrossTargetFallback();
		final declarations = exactEnumDeclarations(program());
		assertTrue(declarations.length == 5, "real-source typing did not retain all five exact enum-constructor calls");
		final owners = [for (declaration in declarations) declaration.getOwner().getCanonicalName()];
		assertTrue(owners.filter(owner -> owner == "demo.Main.Alpha").length == 3, "Alpha constructor calls did not retain their canonical enum owner");
		assertTrue(owners.filter(owner -> owner == "demo.Main.Beta").length == 2, "Beta constructor calls did not retain their canonical enum owner");
		for (declaration in declarations) {
			assertTrue(declaration.getModulePath() == "demo.Main", "enum constructor lost its owning module identity");
			assertTrue(declaration.getIdentity().getCanonicalKey().indexOf(declaration.getOwner().getCanonicalName() + "#static:") == 0,
				"enum constructor declaration identity is not canonical");
		}
		final ambiguous = ambiguousProgram();
		final ambiguousCall = variableInitializer(ambiguous, "ambiguous");
		assertTrue(ambiguousCall.getTag() == TypedExprTag.Call && ambiguousCall.getDeclaration() == null,
			"duplicate bare enum constructors must not select an owner by traversal order");
		final qualifiedCall = variableInitializer(ambiguous, "qualified");
		assertTrue(qualifiedCall.getTag() == TypedExprTag.Call
			&& qualifiedCall.getDeclaration() != null
			&& qualifiedCall.getDeclaration().getOwner().getCanonicalName() == "demo.Ambiguous.First",
			"qualified duplicate enum constructor did not retain its exact owner");

		final tmpRoot = Path.normalize(".tmp/m14_cs_typed_enum_constructor_projection_" + Std.string(Date.now().getTime()));
		final directDir = Path.join([tmpRoot, "direct"]);
		final repeatedDir = Path.join([tmpRoot, "repeated"]);
		final afterFailureDir = Path.join([tmpRoot, "after-failure"]);
		deleteRecursive(tmpRoot);

		var failure:Null<String> = null;
		try {
			final direct = emit(directDir);
			final repeated = emit(repeatedDir);
			assertTrue(direct.entry == repeated.entry && direct.helper == repeated.helper,
				"equivalent C# requests produced different exact enum-constructor output");
			assertContains(direct.entry, "global::demo.Alpha.AlphaValue(1)", "bare Alpha constructor did not lower through its exact typed owner");
			assertContains(direct.entry, "global::demo.Beta.BetaValue(2)", "bare Beta constructor did not lower through its exact typed owner");
			assertContains(direct.entry, "global::demo.Alpha.AlphaValue(3)", "qualified Alpha constructor lost its exact typed owner");
			assertContains(direct.entry, "return global::demo.Beta.BetaValue(value);",
				"main helper constructor did not use the request-owned identity catalog");
			assertContains(direct.helper, "return global::demo.Alpha.AlphaValue(value);",
				"support helper constructor did not use the request-owned identity catalog");
			assertNotContains(direct.entry, "var alpha = AlphaValue(1);", "C# output retained a bare enum constructor after exact lowering");
			assertNotContains(direct.entry, "var beta = BetaValue(2);", "C# output retained a bare enum constructor after exact lowering");

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
			assertTrue(afterFailure.entry == direct.entry && afterFailure.helper == direct.helper,
				"a failed C# request changed the next exact enum-constructor output");
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
