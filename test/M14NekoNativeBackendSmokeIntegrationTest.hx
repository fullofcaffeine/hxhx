import backend.BackendContext;
import backend.BackendDispatchBoundary;
import backend.BackendRegistry;
import backend.vm.NekoTargetCore;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

class M14NekoNativeBackendSmokeIntegrationTest {
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

	static function program(source:String) {
		final parsed = ParserStage.parse(source, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function main():Void {
		final outDir = Path.join([".tmp", "m14_neko_native_backend_smoke"]);
		deleteRecursive(outDir);
		FileSystem.createDirectory(outDir);

		final defines = new haxe.ds.StringMap<String>();
		defines.set(NekoTargetCore.SOURCE_ONLY_DEFINE, "1");
		final outputHint = Path.join([outDir, "main.n"]);
		final context = new BackendContext(outDir, outputHint, "Main", true, false, defines);
		final backend = BackendRegistry.createForTarget("neko-native");
		final result = BackendDispatchBoundary.emit(backend, program('class Main { static function main() { Sys.println("hello neko"); } }'), context);

		final sourcePath = Path.join([outDir, "main.neko"]);
		assertTrue(result.entryPath == sourcePath, "source-only mode should report the generated Neko source as entry path");
		assertTrue(FileSystem.exists(sourcePath), "expected generated Neko source file");
		final source = File.getContent(sourcePath);
		assertContains(source, "var Main_main = function()", "expected generated static main function");
		assertContains(source, "$print(\"hello neko\", \"\\n\")", "expected Sys.println lowering");
		assertContains(source, "Main_main();", "expected entrypoint invocation");

		deleteRecursive(outDir);
	}
}
