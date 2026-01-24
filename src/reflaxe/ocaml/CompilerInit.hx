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

		var prepasses:Array<ExpressionPreprocessor> = ExpressionPreprocessorHelper.defaults();
		// Run early so later preprocessors operate on cleaner shapes.
		prepasses.unshift(ExpressionPreprocessor.Custom(new InlineSwitchTempImpl()));

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
