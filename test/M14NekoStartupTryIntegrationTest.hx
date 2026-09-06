import backend.BackendContext;
import backend.BackendDispatchBoundary;
import backend.BackendRegistry;
import backend.vm.NekoTargetCore;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import sys.io.Process;

/** Proves that a Neko startup probe keeps structured try-expression behavior. **/
class M14NekoStartupTryIntegrationTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
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

	static function run(command:String, arguments:Array<String>):{exitCode:Int, stdout:String, stderr:String} {
		final process = new Process(command, arguments);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final exitCode = process.exitCode();
		process.close();
		return {exitCode: exitCode, stdout: stdout, stderr: stderr};
	}

	static function main():Void {
		final source = [
			"class Main {",
			"  static function available(fail:Bool):Bool {",
			'    function load():Dynamic { if (fail) throw "missing"; return "loaded"; }',
			"    return try load() != null catch (error:Dynamic) false;",
			"  }",
			"  static function main() {",
			"    Sys.println(available(false));",
			"    Sys.println(available(true));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(source, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		final program = MacroStage.expandProgram([typed], []);

		final outputDirectory = Path.join([".tmp", "m14_neko_startup_try"]);
		deleteRecursive(outputDirectory);
		FileSystem.createDirectory(outputDirectory);
		final defines = new haxe.ds.StringMap<String>();
		defines.set(NekoTargetCore.SOURCE_ONLY_DEFINE, "1");
		final outputPath = Path.join([outputDirectory, "main.n"]);
		final context = new BackendContext(outputDirectory, outputPath, "Main", true, false, defines);
		final backend = BackendRegistry.createForTarget("neko-native");
		final emitted = BackendDispatchBoundary.emit(backend, program, context);
		final generated = File.getContent(emitted.entryPath);
		assertTrue(generated.indexOf("try { return (load() != null); } catch error { return false; }") >= 0,
			"generated Neko lost the startup call, comparison, or catch result");

		final nekoc = Sys.getEnv("NEKOC_BIN") == null ? "nekoc" : Sys.getEnv("NEKOC_BIN");
		final compiled = run(nekoc, ["-o", outputDirectory, emitted.entryPath]);
		assertTrue(compiled.exitCode == 0, "nekoc rejected the generated startup probe: " + compiled.stderr);
		final neko = Sys.getEnv("NEKO_BIN") == null ? "neko" : Sys.getEnv("NEKO_BIN");
		final executed = run(neko, [outputPath]);
		assertTrue(executed.exitCode == 0, "neko rejected the compiled startup probe: " + executed.stderr);
		assertTrue(executed.stdout == "true\nfalse\n", "unexpected startup probe result: " + executed.stdout);
		deleteRecursive(outputDirectory);
	}
}
