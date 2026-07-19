package reflaxe.ocaml.tooling;

import sys.FileSystem;

/**
	Entry point for `haxelib run reflaxe.ocaml`.

	Haxelib runs this class from the installed package and appends the caller's
	working directory to the argument list. Direct `haxe --run` invocations do
	not add that directory, so the small adapter accepts both shapes before
	handing control to the package-owned CLI.
**/
class ReflaxeOcamlRun {
	public static function main():Void {
		final packageRoot = FileSystem.absolutePath(Sys.getCwd());
		final args = Sys.args();
		var projectRoot = packageRoot;

		if (hasHaxelibWorkingDirectory(args)) {
			final haxelibProjectRoot = args.pop();
			if (haxelibProjectRoot != null) {
				projectRoot = FileSystem.absolutePath(haxelibProjectRoot);
			}
		}

		Sys.exit(ReflaxeOcamlCli.run(args, packageRoot, projectRoot));
	}

	static function hasHaxelibWorkingDirectory(args:Array<String>):Bool {
		if (Sys.getEnv("HAXELIB_RUN") != "1" || Sys.getEnv("HAXELIB_RUN_NAME") != "reflaxe.ocaml" || args.length == 0) {
			return false;
		}
		final candidate = args[args.length - 1];
		return FileSystem.exists(candidate) && FileSystem.isDirectory(candidate);
	}
}
