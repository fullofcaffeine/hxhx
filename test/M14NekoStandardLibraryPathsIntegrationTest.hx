import haxe.io.Path;
import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;
import sys.FileSystem;
import sys.io.File;

/** Checks Neko provider selection while preserving explicit project overrides. */
class M14NekoStandardLibraryPathsIntegrationTest {
	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function removeTree(path:String):Void {
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				removeTree(Path.join([path, entry]));
			FileSystem.deleteDirectory(path);
		} else
			FileSystem.deleteFile(path);
	}

	static function main():Void {
		final root = Path.normalize(Sys.getCwd() + "/.tmp/neko_std_paths_" + Date.now().getTime());
		final std = root + "/std";
		final first = root + "/first";
		final second = root + "/second";
		for (directory in [std + "/haxe", std + "/neko/_std/haxe", first + "/haxe", second + "/haxe"])
			FileSystem.createDirectory(directory);
		File.saveContent(std + "/haxe/Exception.hx", "package haxe; extern class Exception {}\n");
		File.saveContent(std + "/neko/_std/haxe/Exception.hx", "package haxe; class Exception {}\n");
		File.saveContent(std + "/haxe/ValueException.hx", "package haxe; class ValueException {}\n");
		final oldStd = Sys.getEnv("HAXE_STD_PATH");
		Sys.putEnv("HAXE_STD_PATH", std);
		try {
			function lookup(arguments:Array<String>, target:String = "neko"):Array<String> {
				final parsed = Stage1Args.parse(arguments.concat(["--std", std, "-main", "Main"]), true);
				require(parsed != null, "parse classpath fixture arguments");
				return Stage3SetupSupport.projectClassPaths({
					explicitPaths: Stage1Args.getExplicitClassPaths(parsed),
					libraries: [],
					cwd: root,
					standardRoot: Stage1Args.getStandardLibraryRoot(parsed),
					targetDefine: target
				});
			}
			final paths = lookup(["-cp", first]);
			final sources = new CompilerSourceProvider();
			require(sources.resolveModuleFile(paths, "haxe.Exception") == std + "/neko/_std/haxe/Exception.hx",
				"Neko must select its concrete exception provider before the common declaration");
			require(sources.resolveModuleFile(paths, "haxe.ValueException") == std + "/haxe/ValueException.hx",
				"a module without a target override must use the common standard library");
			File.saveContent(first + "/haxe/Exception.hx", "package haxe; class Exception {}\n");
			File.saveContent(second + "/haxe/Exception.hx", "package haxe; class Exception {}\n");
			require(sources.resolveModuleFile(lookup(["-cp", first]), "haxe.Exception") == first + "/haxe/Exception.hx",
				"an explicit project provider must precede the Neko standard library");
			require(sources.resolveModuleFile(lookup(["-cp", first, "-cp", second]), "haxe.Exception") == second + "/haxe/Exception.hx",
				"the last explicit classpath must take precedence");
			require(sources.resolveModuleFile(lookup(["-cp", second, "-cp", first]), "haxe.Exception") == first + "/haxe/Exception.hx",
				"reversing explicit classpaths must reverse their precedence");
			FileSystem.createDirectory(root + "/haxe");
			File.saveContent(root + "/haxe/Exception.hx", "package haxe; class Exception {}\n");
			require(sources.resolveModuleFile(lookup([]), "haxe.Exception") == root + "/haxe/Exception.hx",
				"the implicit working directory must precede standard-library providers");
			final explicitCommon = lookup(["-cp", std + "/."]);
			require(sources.resolveModuleFile(explicitCommon, "haxe.Exception") == std + "/haxe/Exception.hx",
				"an explicitly requested common directory must retain user priority");
			require([for (path in explicitCommon) if (path == std) path].length == 1,
				"the inferred standard root must not duplicate an equivalent explicit root");
			require(lookup([], "js").indexOf(std + "/neko/_std") == -1, "Neko providers must not leak into another target");
			FileSystem.deleteFile(root + "/haxe/Exception.hx");
			removeTree(std + "/neko");
			require(sources.resolveModuleFile(lookup([]), "haxe.Exception") == std + "/haxe/Exception.hx",
				"a standard library without Neko overrides must retain its common provider");
			Sys.putEnv("HAXE_STD_PATH", oldStd);
			removeTree(root);
			Sys.println("NEKO_STANDARD_LIBRARY_PATHS:PASS");
		} catch (error:haxe.Exception) {
			Sys.putEnv("HAXE_STD_PATH", oldStd);
			throw error;
		}
	}
}
