import backend.BackendContext;
import backend.BackendRegistry;
import backend.GenIrProgram;
import haxe.ds.StringMap;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

class M14SourceNativeBackendSmokeIntegrationTest {
	static function assertTrue(cond:Bool, message:String):Void {
		if (!cond)
			throw message;
	}

	static function assertContains(haystack:String, needle:String, message:String):Void {
		if (haystack.indexOf(needle) < 0)
			throw message + " (missing `" + needle + "` in `" + haystack + "`)";
	}

	static function deleteRecursive(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				deleteRecursive(Path.join([path, entry]));
			FileSystem.deleteDirectory(path);
		} else {
			FileSystem.deleteFile(path);
		}
	}

	static function program(label:String):GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    Sys.println(\"source-native:\" + \"" + label + "\");",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function unsupportedIfProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    if (true) {",
			"      Sys.println(\"branch\");",
			"    }",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function emit(targetId:String, label:String, expectedFile:String, expectedNeedle:String):Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_" + targetId + "_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget(targetId);
		final defines = new StringMap<String>();
		defines.set(label, "1");
		final result = backend.emit(program(label), new BackendContext(tmpRoot, null, "Main", true, false, defines));
		final expectedPath = Path.join([tmpRoot, expectedFile]);
		assertTrue(result.entryPath == expectedPath, "unexpected entry path for " + targetId + ": " + result.entryPath);
		assertTrue(FileSystem.exists(expectedPath), "missing emitted source artifact for " + targetId);
		assertTrue(result.artifacts.length == 1, "expected one source artifact for " + targetId);
		assertTrue(result.artifacts[0].path == expectedPath, "unexpected artifact path for " + targetId);
		assertContains(File.getContent(expectedPath), expectedNeedle, "emitted source missing target print shape for " + targetId);
		deleteRecursive(tmpRoot);
	}

	static function assertUnsupportedDiagnostic():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_unsupported_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		var message = "";
		try {
			backend.emit(unsupportedIfProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		} catch (e:String) {
			message = e;
		}
		assertContains(message, "Python source backend MVP unsupported statement: SIf", "unsupported statement diagnostic should name the AST kind");
		deleteRecursive(tmpRoot);
	}

	static function main():Void {
		emit("python-native", "python", "Main.py", "print(\"source-native:\" + \"python\")");
		emit("java-native", "java", "Main.java", "System.out.println(\"source-native:\" + \"java\");");
		emit("cs-native", "cs", "Main.cs", "System.Console.WriteLine(\"source-native:\" + \"cs\");");
		emit("php-native", "php", "index.php", "echo \"source-native:\" . \"php\" . PHP_EOL;");
		emit("lua-native", "lua", "Main.lua", "print(\"source-native:\" .. \"lua\")");
		assertUnsupportedDiagnostic();
	}
}
