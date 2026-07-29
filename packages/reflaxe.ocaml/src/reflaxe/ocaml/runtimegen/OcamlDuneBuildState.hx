package reflaxe.ocaml.runtimegen;

#if (macro || reflaxe_runtime)
import haxe.io.Path;
import sys.FileSystem;

/**
	Owns the stable Dune build-state path for one generated OCaml project.

	Reflaxe may replace the complete generated-source directory after a successful
	transaction. Dune's `_build` state therefore lives in a hidden sibling whose
	name is derived only from the stable public output directory. Dune remains the
	sole owner of the files below that path.
**/
class OcamlDuneBuildState {
	public static inline final PATH_SUFFIX = ".reflaxe-ocaml-dune-build";

	/** Returns the project-local Dune build directory for one public output tree. **/
	public static function forOutputDirectory(outputDirectory:String):String {
		final absoluteOutput = Path.normalize(FileSystem.absolutePath(outputDirectory));
		final name = Path.withoutDirectory(absoluteOutput);
		final parent = Path.directory(absoluteOutput);
		if (name.length == 0 || parent == absoluteOutput)
			throw 'Cannot derive Dune build state from output directory "$outputDirectory".';
		return Path.join([parent, '.$name$PATH_SUFFIX']);
	}

	/** Adds the stable root and optional external build directory to a Dune command. **/
	public static function commandArguments(root:String, buildDirectory:Null<String>, target:String):Array<String> {
		final result = ["--root", root];
		if (buildDirectory != null) {
			result.push("--build-dir");
			result.push(buildDirectory);
		}
		result.push(target);
		return result;
	}
}
#end
