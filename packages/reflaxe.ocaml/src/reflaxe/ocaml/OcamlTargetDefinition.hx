package reflaxe.ocaml;

#if (macro || reflaxe_runtime)
import reflaxe.BaseCompiler.BaseCompilerOptions;
import reflaxe.lifecycle.SemanticLifecycleOptions;
import reflaxe.ocaml.lifecycle.OcamlPlaceLifecycleFamily;
import reflaxe.ocaml.lowered.OcamlFunctionPlanRegistry;
import reflaxe.ocaml.macros.StrictModeEnforcer;
import reflaxe.ocaml.preprocessor.FinalizePlaceAssignmentsImpl;
import reflaxe.ocaml.preprocessor.InlineSwitchTempImpl;
import reflaxe.ocaml.preprocessor.PreservePlaceAssignmentsImpl;
import reflaxe.preprocessors.ExpressionPreprocessor;
import reflaxe.preprocessors.ExpressionPreprocessor.ExpressionPreprocessorHelper;

/**
	One complete standalone OCaml target definition.

	The definition owns the real semantic compiler and every option that changes
	target behavior. Host-specific activation code may register the returned
	compiler, but it must not reconstruct preprocessing, lifecycle, output, or
	naming policy. Keeping those decisions together is the first boundary needed
	for stock Haxe and native `hxhx` to execute one target implementation.
**/
class OcamlTargetDefinition {
	public static inline final TARGET_ID = "reflaxe.ocaml";
	public static inline final DEFINITION_REVISION = "reflaxe-ocaml-target-definition-v1";

	/**
		Prepare public compiler services required by the standalone target.

		The activation shell calls this only after selecting the OCaml target. The
		target definition owns these choices so another host cannot accidentally
		register the same compiler with different runtime reachability or strictness.
	**/
	public static function prepareHost():Void {
		#if macro
		if (!haxe.macro.Context.defined("target.threaded"))
			haxe.macro.Compiler.define("target.threaded", "1");
		StrictModeEnforcer.init(OcamlBuildContext.resolve());
		requireType("sys.io.Stdio", "Sys stdio lowering");
		requireType("haxe.ValueException", "typed catch lowering");
		#end
	}

	/** Build a fresh request-local compiler and its matching Reflaxe options. **/
	public static function create():OcamlTargetDefinitionInstance {
		var prepasses:Array<ExpressionPreprocessor> = #if macro if (haxe.macro.Context.defined("reflaxe_ocaml_disable_expression_preprocessors"))
			[]
		else #end
		ExpressionPreprocessorHelper.defaults();

		// Run the presentation-only cleanup first when the generic passes are active.
		if (prepasses.length > 0)
			prepasses.unshift(ExpressionPreprocessor.Custom(new InlineSwitchTempImpl()));

		// Place ownership must survive every generic rewrite and be finalized last.
		final preserveIndex = prepasses.length > 0 ? 1 : 0;
		prepasses.insert(preserveIndex, ExpressionPreprocessor.Custom(new PreservePlaceAssignmentsImpl()));
		prepasses.push(ExpressionPreprocessor.Custom(new FinalizePlaceAssignmentsImpl()));

		final compiler = new OcamlCompiler();
		final captureLifecycleTrace = #if macro haxe.macro.Context.defined("reflaxe_ocaml_semantic_lifecycle_trace") #else false #end;
		final transactionalFileOutput = #if macro haxe.macro.Context.defined("reflaxe_output_transaction") #else false #end;
		final options:BaseCompilerOptions = {
			fileOutputExtension: ".ml",
			outputDirDefineName: "ocaml_output",
			fileOutputType: FilePerModule,
			transactionalFileOutput: transactionalFileOutput,
			ignoreTypes: [],
			reservedVarNames: reservedVariableNames(),
			targetCodeInjectionName: "__ocaml__",
			ignoreBodilessFunctions: false,
			ignoreExterns: true,
			expressionPreprocessors: prepasses,
			semanticLifecycle: new SemanticLifecycleOptions([new OcamlPlaceLifecycleFamily(compiler.functionPlanRegistry)],
				OcamlFunctionPlanRegistry.PIPELINE_REVISION, captureLifecycleTrace)
		};
		return {compiler: compiler, options: options};
	}

	static function reservedVariableNames():Array<String> {
		return [
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
		];
	}

	#if macro
	static function requireType(typePath:String, reason:String):Void {
		try {
			haxe.macro.Context.getType(typePath);
		} catch (_:Dynamic) {
			haxe.macro.Context.error('reflaxe.ocaml: failed to load $typePath (required for $reason).', haxe.macro.Context.currentPos());
		}
	}
	#end
}

/** A fresh semantic compiler paired with the exact options it requires. **/
typedef OcamlTargetDefinitionInstance = {
	final compiler:OcamlCompiler;
	final options:BaseCompilerOptions;
}
#end
