import backend.BackendContext;
import backend.ocaml.MetalProfileVerifier;
import backend.ocaml.OcamlTargetCore;
import haxe.io.Path;
import sys.FileSystem;

/** Metal admission must retain reflection exclusions after exact typed call selection. */
class M14MetalProfileVerifierIntegrationTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function assertContains(haystack:String, needle:String, label:String):Void {
		if (haystack.indexOf(needle) < 0)
			throw label + " (missing `" + needle + "`)";
	}

	static function makeProgram(source:String, filePath:String):MacroExpandedProgram {
		final parsed = ParserStage.parse(source, filePath);
		final typed = TyperStage.typeModule(parsed);
		return new MacroExpandedProgram([typed], false, []);
	}

	static function expectVerifierFailure(source:String, filePath:String):String {
		final program = makeProgram(source, filePath);
		try {
			MetalProfileVerifier.verifyProgram(program);
		} catch (e:String) {
			return e;
		}
		throw "expected MetalProfileVerifier failure for " + filePath;
	}

	static function expectTargetCoreMetalFailure(source:String, filePath:String):String {
		final tmpOut = Path.normalize(".tmp/m14_metal_profile_verifier_emit_" + Std.string(Std.int(Date.now().getTime())));
		deleteRecursive(tmpOut);
		final context = new BackendContext(tmpOut, null, "Main", false, HxDefineMap.fromRawDefines(["ocaml_profile=metal"]));
		final program = makeProgram(source, filePath);
		try {
			final core = new OcamlTargetCore();
			core.emit(program, context);
		} catch (e:String) {
			deleteRecursive(tmpOut);
			return e;
		}
		deleteRecursive(tmpOut);
		throw "expected OcamlTargetCore metal verifier failure for " + filePath;
	}

	static function deleteRecursive(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path)) {
				deleteRecursive(Path.join([path, entry]));
			}
			FileSystem.deleteDirectory(path);
			return;
		}
		FileSystem.deleteFile(path);
	}

	static function main():Void {
		assertSelectedReflectionCalls();
		final passingSource = [
			"class Main {",
			"  static function main() {",
			"    var x:Int = 1;",
			"    var y:Int = x + 1;",
			"    Sys.println(Std.string(y));",
			"  }",
			"}"
		].join("\n");
		MetalProfileVerifier.verifyProgram(makeProgram(passingSource, "MetalProfilePass.hx"));

		final failingSource = [
			"class Main {",
			"  static function main() {",
			"    var data = { value: 1 };",
			"    var reflected = Reflect.field(data, \"value\");",
			"    var nativeValue = untyped __ocaml__(\"1\");",
			"    Sys.println(Std.string(reflected));",
			"    Sys.println(Std.string(nativeValue));",
			"  }",
			"}"
		].join("\n");
		final failureMessage = expectVerifierFailure(failingSource, "MetalProfileFail.hx");
		assertContains(failureMessage, "metal profile verification failed", "verifier should fail with metal prefix");
		assertContains(failureMessage, "[reflection_call]", "verifier should report reflection call");
		assertContains(failureMessage, "[untyped_expr]", "verifier should report untyped usage");
		assertContains(failureMessage, "construct: Reflect.field", "verifier should report construct for reflection calls");
		assertContains(failureMessage, "context: Main.main", "verifier should include function context");
		assertContains(failureMessage, "reason:", "verifier should include explicit reason");
		assertContains(failureMessage, "migration:", "verifier should include migration hint");
		assertContains(failureMessage, "next: keep metal by applying the migrations above", "verifier should include explicit next steps");
		assertContains(failureMessage, "no implicit metal->portable fallback", "verifier should state strict fallback policy");

		final reflectionIndex = failureMessage.indexOf("[reflection_call]");
		final untypedIndex = failureMessage.indexOf("[untyped_expr]");
		assertTrue(reflectionIndex >= 0 && untypedIndex >= 0 && reflectionIndex < untypedIndex,
			"verifier diagnostics should be deterministic and preserve source order");

		final coreFailure = expectTargetCoreMetalFailure(failingSource, "MetalProfileCoreFail.hx");
		assertContains(coreFailure, "[untyped_expr]", "metal profile verifier should run before emit in OcamlTargetCore");

		final dynamicHintFailingSource = [
			"class Main {",
			"  static function helper(value:Dynamic):Int {",
			"    var widened:Dynamic = value;",
			"    return 0;",
			"  }",
			"  static function main() {",
			"    Sys.println(Std.string(helper(1)));",
			"  }",
			"}"
		].join("\n");
		final dynamicFailureMessage = expectVerifierFailure(dynamicHintFailingSource, "MetalProfileDynamicTypeFail.hx");
		assertContains(dynamicFailureMessage, "[dynamic_type_hint]", "verifier should report dynamic type hints");
		assertContains(dynamicFailureMessage, "construct: argument `value` type", "verifier should report argument type construct");
		assertContains(dynamicFailureMessage, "replace `Dynamic` with a concrete type", "verifier should include migration guidance for dynamic types");
	}

	/** Aliases and nested calls use real declaration identities; an ordinary method named field is not reflection. */
	static function assertSelectedReflectionCalls():Void {
		final source = 'import Reflect as Mirror;
class Main { static function main():Void {
Mirror.hasField(Mirror.field({nested:{value:1}}, "nested"), "value");
Helper.field(1);
}}
class Helper { public static function field(value:Int):Int return value; }';
		final resolved = new ResolvedModule("Main", "SelectedReflection.hx", ParserStage.parse(source, "SelectedReflection.hx"));
		final arguments = hxhx.Stage1Compiler.Stage1Args.parse(["-main", "Main"], true);
		final paths = hxhx.Stage3SetupSupport.projectClassPaths({
			explicitPaths: [],
			libraries: [],
			cwd: Sys.getCwd(),
			standardRoot: hxhx.Stage1Compiler.Stage1Args.getStandardLibraryRoot(arguments),
			targetDefine: "ocaml"
		});
		final index = TyperIndex.buildHeaders([resolved]);
		final loader = new ModuleLoader(paths, hxhx.Stage3SetupSupport.buildDefinesMap([], "ocaml", "ocaml"), index);
		loader.markResolvedAlready([resolved]);
		final typed = TyperStage.typeResolvedModule(resolved, index, loader, true);
		final program = new MacroExpandedProgram([typed], false);
		final violations = MetalProfileVerifier.collectViolationSummaries(program);
		assertTrue(violations.length == 2, "expected exactly two selected reflection calls, without classifying Helper.field");
		assertTrue(violations[0].code == "reflection_call" && violations[0].construct == "Reflect.hasField",
			"selected alias lost its canonical reflection owner");
		assertTrue(violations[1].code == "reflection_call"
			&& violations[1].construct == "Reflect.field", "selected call traversal lost nested reflection");
		var rejected = false;
		try {
			MetalProfileVerifier.verifyProgram(program);
		} catch (error:String) {
			rejected = error.indexOf("[reflection_call]") >= 0;
		}
		assertTrue(rejected, "metal verifier admitted selected reflection calls");
	}
}
