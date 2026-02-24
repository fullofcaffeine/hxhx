import backend.BackendContext;
import backend.ocaml.MetalProfileVerifier;
import backend.ocaml.OcamlTargetCore;
import haxe.io.Path;
import sys.FileSystem;

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
		final context = new BackendContext(tmpOut, null, "Main", true, false, HxDefineMap.fromRawDefines(["ocaml_profile=metal"]));
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
		assertContains(failureMessage, "context: Main.main", "verifier should include function context");

		final reflectionIndex = failureMessage.indexOf("[reflection_call]");
		final untypedIndex = failureMessage.indexOf("[untyped_expr]");
		assertTrue(reflectionIndex >= 0 && untypedIndex >= 0 && reflectionIndex < untypedIndex,
			"verifier diagnostics should be deterministic and preserve source order");

		final coreFailure = expectTargetCoreMetalFailure(failingSource, "MetalProfileCoreFail.hx");
		assertContains(coreFailure, "[untyped_expr]", "metal profile verifier should run before emit in OcamlTargetCore");
	}
}
