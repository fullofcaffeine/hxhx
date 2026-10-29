import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Checks that default compilation retains bodies in ordinary and std directories.
	Upstream and native executables observe local values and effects in both primary
	and module-local helper classes, without a body-emission option.
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
		final helperSource = "package probe; private class LocalHelper { public static function value():Int { final number = 7; Sys.println(\"helper\"); return number; } }"
			+ " class Helper { public static function answer():Int { final result = LocalHelper.value(); Sys.println(\"effect\"); return result; } }";
		File.saveContent(mainPath, mainSource);
		File.saveContent(helperPath, helperSource);
		try {
			final expected = "helper\neffect\n7\n";
			M14Stage3RuntimeFixture.observe({
				command: "haxe",
				arguments: ["-cp", root, "-cp", Path.join([root, directory]), "--run", "Main"],
				expected: expected
			});
			final modules = [
				new ResolvedModule("Main", mainPath, ParserStage.parse(mainSource, mainPath)),
				new ResolvedModule("probe.Helper", helperPath, ParserStage.parse(helperSource, helperPath))
			];
			final index = TyperIndex.build(modules);
			final typed = modules.map(module -> TyperStage.typeResolvedModule(module, index));
			final expanded = MacroStage.expandProgram(typed, []);
			final executable = EmitterStage.emitToDir(expanded, Path.join([root, "out"]));
			M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
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
