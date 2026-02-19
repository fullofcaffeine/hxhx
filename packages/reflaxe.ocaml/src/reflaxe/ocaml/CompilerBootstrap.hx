package reflaxe.ocaml;

#if macro
import haxe.io.Path;
import haxe.macro.Compiler;
import haxe.macro.Context;

/**
 * Macro-time bootstrap utilities for reflaxe.ocaml.
 *
 * Keeps staged std overrides isolated to the OCaml target while still allowing
 * the haxelib to be present on the classpath for other targets/tools.
 */
class CompilerBootstrap {
	public static function InjectClassPaths():Void {
		var isOcamlTarget = Context.defined("ocaml_output")
			|| Context.definedValue("target.name") == "ocaml"
			|| Context.definedValue("reflaxe-target") == "ocaml";

		var repoRoot = getRepoRoot();
		if (repoRoot == null)
			return;

		// Always add std/ (portable + ocaml.* surface) for this haxelib.
		addClassPathIfExists(Path.normalize(Path.join([repoRoot, "std"])));

		// Add staged std overrides only for OCaml target builds.
		if (isOcamlTarget) {
			addClassPathIfExists(Path.normalize(Path.join([repoRoot, "std/_std"])));
		}
	}

	static function getRepoRoot():Null<String> {
		try {
			// <root>/src/reflaxe/ocaml/CompilerBootstrap.hx
			var thisFile = Context.resolvePath("reflaxe/ocaml/CompilerBootstrap.hx");
			var d0 = Path.directory(thisFile); // .../src/reflaxe/ocaml
			var d1 = Path.directory(d0); // .../src/reflaxe
			var d2 = Path.directory(d1); // .../src
			return Path.directory(d2); // .../
		} catch (_:Dynamic) {
			return null;
		}
	}

	static function addClassPathIfExists(path:String):Void {
		try {
			Compiler.addClassPath(path);
		} catch (_:Dynamic) {}
	}
}
#end
