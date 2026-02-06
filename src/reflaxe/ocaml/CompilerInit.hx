package reflaxe.ocaml;

#if (macro || reflaxe_runtime)

import reflaxe.ReflectCompiler;
import reflaxe.preprocessors.ExpressionPreprocessor;
import reflaxe.preprocessors.ExpressionPreprocessor.ExpressionPreprocessorHelper;
import reflaxe.ocaml.preprocessor.InlineSwitchTempImpl;

/**
 * Initialization and registration of the OCaml compiler.
 *
 * Intended to be called from `haxe_libraries/reflaxe.ocaml.hxml`:
 * `--macro reflaxe.ocaml.CompilerInit.Start()`
 */
class CompilerInit {
	public static function Start():Void {
		#if macro
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

			// Ensure std/_std injection is only applied when targeting OCaml.
			CompilerBootstrap.InjectClassPaths();
			#if macro
			final isOcamlTarget =
				haxe.macro.Context.defined("ocaml_output") ||
				haxe.macro.Context.definedValue("target.name") == "ocaml" ||
				haxe.macro.Context.definedValue("reflaxe-target") == "ocaml";
			if (isOcamlTarget) {
				// Force-link OCaml-only std overrides that are reached via backend intrinsics
				// rather than direct Haxe references (so DCE/module reachability would drop them).
				//
				// Important: `Compiler.include("sys.io")` pulls in the whole package and bloats
				// small outputs/snapshots. We only need `sys.io.Stdio` for backend-intrinsic
				// lowering of `Sys.stdin/stdout/stderr`, so we load that module explicitly.
				try {
					haxe.macro.Context.getType("sys.io.Stdio");
				} catch (_:Dynamic) {
					haxe.macro.Context.error(
						"reflaxe.ocaml: failed to load sys.io.Stdio (required for Sys stdio lowering).",
						haxe.macro.Context.currentPos()
					);
				}
			}
			#end

		// Expression preprocessors rewrite typed expressions to be more codegen-friendly.
		//
		// NOTE (Gate1 bring-up):
		// Some upstream test workloads are extremely sensitive to any typed-AST mutation that
		// happens before Haxe's internal expression filters (e.g. `renameVars`) run.
		//
		// To keep Gate1 stable while we iterate on where and how we apply rewrites,
		// allow disabling all preprocessors via a define.
		var prepasses:Array<ExpressionPreprocessor> =
			#if macro
			if (haxe.macro.Context.defined("reflaxe_ocaml_disable_expression_preprocessors")) []
			else
			#end
			ExpressionPreprocessorHelper.defaults();

		// Run early so later preprocessors operate on cleaner shapes.
		// This pass is purely "pretty output" for OCaml, so it is safe to skip in bring-up runs.
		if (prepasses.length > 0) {
			prepasses.unshift(ExpressionPreprocessor.Custom(new InlineSwitchTempImpl()));
		}

		ReflectCompiler.AddCompiler(new OcamlCompiler(), {
			fileOutputExtension: ".ml",
			outputDirDefineName: "ocaml_output",
			fileOutputType: FilePerModule,
			ignoreTypes: [],
			reservedVarNames: [
				"and", "as", "assert", "asr", "begin",
				"class", "constraint",
				"do", "done", "downto",
				"else", "end", "exception", "external",
				"false", "for", "fun", "function", "functor",
				"if", "in", "include", "inherit", "initializer",
				"land", "lazy", "let", "lor", "lsl", "lsr", "lxor",
				"match", "method", "mod", "module", "mutable",
				"new", "nonrec",
				"object", "of", "open", "or",
				"private",
				"rec",
				"sig", "struct",
				"then", "to", "true", "try", "type",
				"val", "virtual",
				"when", "while", "with"
			],
			targetCodeInjectionName: "__ocaml__",
			ignoreBodilessFunctions: false,
			ignoreExterns: true,
			expressionPreprocessors: prepasses
		});
	}
}

#end
