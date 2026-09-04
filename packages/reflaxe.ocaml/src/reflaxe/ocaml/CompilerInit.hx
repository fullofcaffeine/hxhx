package reflaxe.ocaml;

#if (macro || reflaxe_runtime)
import reflaxe.ReflectCompiler;

/**
 * Initialization and registration of the OCaml compiler.
 *
 * Intended to be called from `haxe_libraries/reflaxe.ocaml.hxml`:
 * `--macro reflaxe.ocaml.CompilerInit.Start()`
 */
class CompilerInit {
	public static function Start():Void {
		#if macro
		// `haxelib run reflaxe.ocaml` compiles the package's host-side Run class
		// with this library on the command line. That tooling process must not
		// register the OCaml target or rewrite its own typed expressions.
		if (Sys.getEnv("HAXELIB_RUN") == "1" && Sys.getEnv("HAXELIB_RUN_NAME") == "reflaxe.ocaml") {
			return;
		}

		if (haxe.macro.Context.defined("reflaxe_ocaml_debug_init")) {
			haxe.macro.Context.warning("reflaxe.ocaml CompilerInit.Start()", haxe.macro.Context.currentPos());
		}
		#end

		// Haxe 5 custom-target gating (no-op on Haxe 4.x).
		#if (haxe >= version("5.0.0"))
		switch (haxe.macro.Compiler.getConfiguration().platform) {
			case CustomTarget("ocaml"):
			case _:
				return;
		}
		#end

		#if macro
		final isOcamlTarget = haxe.macro.Context.defined("ocaml_output")
			|| haxe.macro.Context.definedValue("target.name") == "ocaml"
			|| haxe.macro.Context.definedValue("reflaxe-target") == "ocaml";
		if (isOcamlTarget)
			OcamlTargetDefinition.prepareHost();
		#end

		final target = OcamlTargetDefinition.create();
		ReflectCompiler.AddCompiler(target.compiler, target.options);
	}
}
#end
