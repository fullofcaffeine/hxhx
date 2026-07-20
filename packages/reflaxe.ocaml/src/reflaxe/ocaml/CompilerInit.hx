package reflaxe.ocaml;

#if (macro || reflaxe_runtime)
import reflaxe.ReflectCompiler;
import reflaxe.lifecycle.SemanticLifecycleOptions;
import reflaxe.preprocessors.ExpressionPreprocessor;
import reflaxe.preprocessors.ExpressionPreprocessor.ExpressionPreprocessorHelper;
import reflaxe.ocaml.lifecycle.OcamlPlaceLifecycleFamily;
import reflaxe.ocaml.lowered.OcamlFunctionPlanRegistry;
import reflaxe.ocaml.macros.StrictModeEnforcer;
import reflaxe.ocaml.preprocessor.FinalizePlaceAssignmentsImpl;
import reflaxe.ocaml.preprocessor.InlineSwitchTempImpl;
import reflaxe.ocaml.preprocessor.PreservePlaceAssignmentsImpl;

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
		if (isOcamlTarget) {
			// OCaml lane now ships runtime-backed `sys.thread.*` support.
			// Keep this define in-target so upstream stdlib thread modules are available.
			if (!haxe.macro.Context.defined("target.threaded")) {
				haxe.macro.Compiler.define("target.threaded", "1");
			}
			final buildContext = OcamlBuildContext.resolve();
			StrictModeEnforcer.init(buildContext);
			// Force-link OCaml-only std overrides that are reached via backend intrinsics
			// rather than direct Haxe references (so DCE/module reachability would drop them).
			//
			// Important: `Compiler.include("sys.io")` pulls in the whole package and bloats
			// small outputs/snapshots. We only need `sys.io.Stdio` for backend-intrinsic
			// lowering of `Sys.stdin/stdout/stderr`, so we load that module explicitly.
			try {
				haxe.macro.Context.getType("sys.io.Stdio");
			} catch (_:Dynamic) {
				haxe.macro.Context.error("reflaxe.ocaml: failed to load sys.io.Stdio (required for Sys stdio lowering).", haxe.macro.Context.currentPos());
			}
			// Typed catch lowering can wrap non-Exception throws as `haxe.ValueException`.
			// Ensure the OCaml runtime module is always reachable so generated references to
			// `Haxe_ValueException.create` link in stage0/stage3 bootstrap lanes.
			try {
				haxe.macro.Context.getType("haxe.ValueException");
			} catch (_:Dynamic) {
				haxe.macro.Context.error("reflaxe.ocaml: failed to load haxe.ValueException (required for typed catch lowering).",
					haxe.macro.Context.currentPos());
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
		var prepasses:Array<ExpressionPreprocessor> = #if macro if (haxe.macro.Context.defined("reflaxe_ocaml_disable_expression_preprocessors"))
			[]
		else #end
		ExpressionPreprocessorHelper.defaults();

		// Run early so later preprocessors operate on cleaner shapes.
		// This pass is purely "pretty output" for OCaml, so it is safe to skip in bring-up runs.
		if (prepasses.length > 0) {
			prepasses.unshift(ExpressionPreprocessor.Custom(new InlineSwitchTempImpl()));
		}

		// Protect only source shapes that the typed OCaml place lowerer fully owns.
		// This remains active in the bring-up lane: otherwise disabling generic
		// preprocessors would silently select a second semantic assignment path.
		final preserveIndex = prepasses.length > 0 ? 1 : 0;
		prepasses.insert(preserveIndex, ExpressionPreprocessor.Custom(new PreservePlaceAssignmentsImpl()));

		// This must be the final expression preprocessor. It consumes transient
		// protection, recomputes admission on the exact rewritten body, and assigns
		// the stable origins accepted by the semantic place lowerer.
		prepasses.push(ExpressionPreprocessor.Custom(new FinalizePlaceAssignmentsImpl()));

		final compiler = new OcamlCompiler();
		final captureLifecycleTrace = #if macro haxe.macro.Context.defined("reflaxe_ocaml_semantic_lifecycle_trace") #else false #end;
		ReflectCompiler.AddCompiler(compiler, {
			fileOutputExtension: ".ml",
			outputDirDefineName: "ocaml_output",
			fileOutputType: FilePerModule,
			ignoreTypes: [],
			reservedVarNames: [
				"and",
				"as",
				"assert",
				"asr",
				"begin",
				"class",
				"constraint",
				"do",
				"done",
				"downto",
				"else",
				"end",
				"exception",
				"external",
				"false",
				"for",
				"fun",
				"function",
				"functor",
				"if",
				"in",
				"include",
				"inherit",
				"initializer",
				"land",
				"lazy",
				"let",
				"lor",
				"lsl",
				"lsr",
				"lxor",
				"match",
				"method",
				"mod",
				"module",
				"mutable",
				"new",
				"nonrec",
				"object",
				"of",
				"open",
				"or",
				"private",
				"rec",
				"sig",
				"struct",
				"then",
				"to",
				"true",
				"try",
				"type",
				"val",
				"virtual",
				"when",
				"while",
				"with"
			],
			targetCodeInjectionName: "__ocaml__",
			ignoreBodilessFunctions: false,
			ignoreExterns: true,
			expressionPreprocessors: prepasses,
			semanticLifecycle: new SemanticLifecycleOptions([new OcamlPlaceLifecycleFamily(compiler.functionPlanRegistry)],
				OcamlFunctionPlanRegistry.PIPELINE_REVISION, captureLifecycleTrace)
		});
	}
}
#end
