import haxe.io.Path;
import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;
import sys.FileSystem;
import sys.io.File;

/** JavaScript must select its real target providers while retaining user source priority. */
class M14JsStandardLibraryPathsIntegrationTest {
	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	/** Remove only this test's allocated directory and artifacts. */
	static function removeTree(path:String):Void {
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				removeTree(Path.join([path, entry]));
			FileSystem.deleteDirectory(path);
		} else
			FileSystem.deleteFile(path);
	}

	static function main():Void {
		final root = Path.normalize(Sys.getCwd() + "/.tmp/js_std_paths_" + Date.now().getTime());
		final std = root + "/std";
		final project = root + "/project";
		for (directory in [std + "/js/_std", std + "/neko/_std", project])
			FileSystem.createDirectory(directory);
		// These files test resolver precedence only; runtime tests use real providers.
		for (directory in [std, std + "/js/_std", std + "/neko/_std"])
			File.saveContent(directory + "/Probe.hx", "class Probe {}\n");
		File.saveContent(std + "/CommonOnly.hx", "class CommonOnly {}\n");
		function paths(explicit:Array<String>, target:String = "js"):Array<String> {
			final args = Stage1Args.parse(explicit.concat(["--std", std, "-main", "Main"]), true);
			require(args != null, "provider fixture arguments must parse");
			return Stage3SetupSupport.projectClassPaths({
				explicitPaths: Stage1Args.getExplicitClassPaths(args),
				libraries: [],
				cwd: root,
				standardRoot: Stage1Args.getStandardLibraryRoot(args),
				targetDefine: target
			});
		}
		final sources = new CompilerSourceProvider();
		require(sources.resolveModuleFile(paths([]), "Probe") == std + "/js/_std/Probe.hx", "JavaScript override must precede common declaration");
		require(sources.resolveModuleFile(paths([]), "CommonOnly") == std + "/CommonOnly.hx", "missing module override must use common provider");
		require(paths([]).indexOf(std + "/neko/_std") == -1 && paths([], "neko").indexOf(std + "/js/_std") == -1,
			"target providers must not leak between JavaScript and Neko");
		File.saveContent(project + "/Probe.hx", "class Probe {}\n");
		require(sources.resolveModuleFile(paths(["-cp", project]), "Probe") == project + "/Probe.hx", "explicit project provider must win");
		File.saveContent(root + "/Probe.hx", "class Probe {}\n");
		require(sources.resolveModuleFile(paths([]), "Probe") == root + "/Probe.hx", "implicit working directory must win");
		final explicit = paths(["-cp", std + "/."]);
		require(sources.resolveModuleFile(explicit, "Probe") == std + "/Probe.hx", "explicit common root must retain user priority");
		require([for (path in explicit) if (path == std) path].length == 1, "equivalent common roots must not duplicate");
		FileSystem.deleteFile(root + "/Probe.hx");
		removeTree(std + "/js");
		require(sources.resolveModuleFile(paths([]), "Probe") == std + "/Probe.hx", "missing override directory must use common provider");
		assertRealProviders(root);
		removeTree(root);
		Sys.println("JS_STANDARD_LIBRARY_PATHS:PASS");
	}

	/** Observe actual upstream JavaScript selection without reading or copying compiler implementation. */
	static function assertRealProviders(root:String):Void {
		final args = Stage1Args.parse(["-main", "Main"], true);
		final common = Path.normalize(Stage1Args.getStandardLibraryRoot(args));
		final paths = Stage3SetupSupport.projectClassPaths({
			explicitPaths: [],
			libraries: [],
			cwd: root,
			standardRoot: common,
			targetDefine: "js"
		});
		final sources = new CompilerSourceProvider();
		for (module in ["Math", "Std"])
			require(sources.resolveModuleFile(paths, module) == common + "/js/_std/" + module + ".hx", "real JavaScript provider missing for " + module);
		File.saveContent(root + "/Main.hx", "class Main { static function main():Void { final selected = Math; trace(selected != null); } }\n");
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", [
			"60",
			"node_modules/.bin/haxe",
			"-v",
			"-cp",
			root,
			"-main",
			"Main",
			"-js",
			root + "/main.js"
		]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final status = process.exitCode();
		process.close();
		require(status == 0, "upstream provider observer failed: " + stdout + stderr);
		for (module in ["Math", "Std"])
			require((stdout + stderr).indexOf("Parsed " + common + "/js/_std/" + module + ".hx") >= 0, "upstream selected a different provider for " + module);
	}
}
