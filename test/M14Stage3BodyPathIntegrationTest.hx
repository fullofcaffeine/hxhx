import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Checks that moving a module into a directory named std preserves its body.
	The native executable observes both a local return value and an earlier effect.
	This test supplies resolved modules directly; fully qualified calls keep import
	resolution outside the body-emission contract.
**/
class M14Stage3BodyPathIntegrationTest {
	static function removeTree(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				removeTree(Path.join([path, entry]));
			FileSystem.deleteDirectory(path);
		} else
			FileSystem.deleteFile(path);
	}

	static function check(directory:String):Void {
		final root = Path.join([".tmp", "stage3-body-path-" + directory]);
		removeTree(root);
		FileSystem.createDirectory(root);
		final helperDir = Path.join([root, directory, "probe"]);
		FileSystem.createDirectory(helperDir);
		final mainPath = Path.join([root, "Main.hx"]);
		final helperPath = Path.join([helperDir, "Helper.hx"]);
		final mainSource = "class Main { static function main() { Sys.println(probe.Helper.answer()); } }";
		final helperSource = "package probe; class Helper { public static function answer():Int { final result = 7; Sys.println(\"effect\"); return result; } }";
		File.saveContent(mainPath, mainSource);
		File.saveContent(helperPath, helperSource);
		try {
			final modules = [
				new ResolvedModule("Main", mainPath, ParserStage.parse(mainSource, mainPath)),
				new ResolvedModule("probe.Helper", helperPath, ParserStage.parse(helperSource, helperPath))
			];
			final index = TyperIndex.build(modules);
			final typed = modules.map(module -> TyperStage.typeResolvedModule(module, index));
			final expanded = MacroStage.expandProgram(typed, []);
			final executable = EmitterStage.emitToDir(expanded, Path.join([root, "out"]), true);
			final process = new sys.io.Process(executable, []);
			final stdout = process.stdout.readAll().toString();
			final stderr = process.stderr.readAll().toString();
			final code = process.exitCode();
			process.close();
			if (code != 0 || stdout != "effect\n7\n")
				throw "body changed under " + directory + ": " + stdout + stderr;
		} catch (error:haxe.Exception) {
			removeTree(root);
			throw error;
		}
		removeTree(root);
	}

	static function main():Void {
		check("ordinary");
		check("std");
		Sys.println("M14_STAGE3_BODY_PATH:PASS");
	}
}
