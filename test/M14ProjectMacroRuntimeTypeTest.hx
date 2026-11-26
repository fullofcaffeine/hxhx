import hxhx.macro.ProjectMacroPluginCache;
import sys.FileSystem;
import sys.io.File;

/**
	A project macro whose module holds a runtime type test builds as a plugin (haxe_ocaml-kbtmo).

	The plugin entry finds each macro declaration's parameters by its owner class. It read every
	compiled module through the declaration-only backend view, which rejects a module with a
	runtime type operand. Upstream's test builder reaches `haxe.Exception.caught`
	(`Std.isOfType`) through its `try`/`catch`, so its plugin failed with "declaration-only backend
	does not support runtime type operands in haxe.Exception#static:caught". The lookup needs only
	names and type hints, which the authored declaration has.

	`test/fixtures/project-macro-runtime-type`'s macro uses `Std.isOfType`. Its plugin must build
	(the interpreter runs the child compiler, then `dune`), and upstream must print
	`expected.stdout`; `test:macro-runtime:project-module` runs the native program.
**/
class M14ProjectMacroRuntimeTypeTest {
	static inline final FIXTURE = "test/fixtures/project-macro-runtime-type";

	static function main():Void {
		final repo = Sys.getCwd();
		final expected = File.getContent(FIXTURE + "/expected.stdout");
		require(run("node_modules/.bin/haxe", ["-cp", FIXTURE + "/src", "--run", "Main"]) == expected, "upstream output differs from expected.stdout");

		final root = haxe.io.Path.normalize(".tmp/m14_project_macro_runtime_type_" + Std.string(Date.now().getTime()));
		FileSystem.createDirectory(root);
		final sources = FileSystem.absolutePath(FIXTURE + "/src");
		final progress = new Array<String>();
		final built = try {
			ProjectMacroPluginCache.ensure({
				declarations: ["Checks.describe"],
				macroClassPaths: [sources],
				classPaths: [sources],
				defines: [],
				cwd: repo,
				supportClassPath: repo + "/packages/hxhx-core/src",
				contextClassPath: repo + "/packages/hxhx-core/macro_plugin_std",
				runtimeSourceDirectories: [repo + "/packages/reflaxe.ocaml/std/runtime", repo + "/packages/hxhx-core/shims"],
				cacheRoot: FileSystem.absolutePath(root) + "/cache",
				compilerIdentity: "m14-project-macro-runtime-type",
				ocamlVersion: ocamlVersion(),
				compiler: {
					program: "haxe",
					leadingArgs: [
						"-cp",
						"test",
						"-cp",
						"packages/hxhx-core/src",
						"-cp",
						"packages/hxhx/src",
						"-cp",
						"packages/reflaxe.ocaml/src",
						"-D",
						"reflaxe",
						"--run",
						"M14ProjectMacroPluginTestCompiler"
					]
				},
				dune: "dune",
				ocamlopt: "ocamlopt",
				artifactKind: "native",
				lockTimeoutSeconds: 900,
				buildTimeoutSeconds: 1800,
				progress: line -> progress.push(line)
			});
		} catch (error:String) {
			throw "a macro whose module holds a runtime type test must build as a plugin:\n" + error;
		}
		require(built != null, "the plugin cache returned no plugin");

		deleteRecursive(root);
		Sys.println("M14_PROJECT_MACRO_RUNTIME_TYPE:PASS");
	}

	static function ocamlVersion():String
		return StringTools.trim(run("ocamlopt", ["-version"]));

	static function run(command:String, arguments:Array<String>):String {
		final process = new sys.io.Process(command, arguments);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		require(code == 0, command + " exited " + code + ": " + errors);
		return output;
	}

	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function deleteRecursive(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				deleteRecursive(path + "/" + entry);
			FileSystem.deleteDirectory(path);
		} else {
			FileSystem.deleteFile(path);
		}
	}
}
