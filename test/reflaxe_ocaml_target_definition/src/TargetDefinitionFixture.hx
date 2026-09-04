import haxe.macro.Context;
import haxe.macro.Expr;
import reflaxe.BaseCompiler.BaseCompilerFileOutputType;
import reflaxe.ocaml.OcamlTargetDefinition;
import reflaxe.ocaml.lifecycle.OcamlPlaceLifecycleFamily;
import reflaxe.ocaml.lifecycle.OcamlTargetFunctionLifecycleFamily;
import reflaxe.ocaml.lowered.OcamlFunctionPlanRegistry;
import reflaxe.ocaml.target.HaxeOcamlTargetDeclarationAdapter;
import reflaxe.preprocessors.ExpressionPreprocessor.ExpressionPreprocessorHelper;

/** Verifies that standalone activation receives one complete target definition. **/
class TargetDefinitionFixture {
	public static macro function run():Expr {
		final target = OcamlTargetDefinition.create();
		final options = target.options;
		assertTrue(OcamlTargetDefinition.TARGET_ID == "reflaxe.ocaml", "unexpected target identity");
		assertTrue(options.fileOutputExtension == ".ml", "standalone target lost its OCaml output extension");
		assertTrue(options.outputDirDefineName == "ocaml_output", "standalone target lost its output define");
		assertTrue(options.fileOutputType == BaseCompilerFileOutputType.FilePerModule, "standalone target lost module-shaped output");
		assertTrue(options.targetCodeInjectionName == "__ocaml__", "standalone target lost target-code injection");
		assertTrue(options.ignoreExterns, "standalone target must continue to ignore extern declarations");
		assertTrue(!options.ignoreBodilessFunctions, "standalone target must diagnose unsupported bodiless functions");
		assertTrue(options.reservedVarNames.indexOf("module") >= 0 && options.reservedVarNames.indexOf("with") >= 0,
			"standalone target lost OCaml reserved names");

		final prepasses = options.expressionPreprocessors;
		assertTrue(prepasses != null && prepasses.length >= 2, "standalone target lost its semantic preprocessing pipeline");
		final lifecycle = options.semanticLifecycle;
		assertTrue(lifecycle != null, "standalone target lost semantic lifecycle validation");
		assertTrue(lifecycle.pipelineRevision == OcamlFunctionPlanRegistry.PIPELINE_REVISION, "standalone target lifecycle revision drifted");
		final lifecycleFamilyIds = lifecycle.families.map(family -> family.id);
		assertTrue(lifecycleFamilyIds.contains(OcamlPlaceLifecycleFamily.ID), "standalone target lost place-plan lifecycle validation");
		assertTrue(lifecycleFamilyIds.contains(OcamlTargetFunctionLifecycleFamily.ID), "standalone target lost shared-function lifecycle validation");
		assertTrue(ExpressionPreprocessorHelper.lifecycleId(prepasses[prepasses.length - 1]) == "reflaxe.ocaml.finalize-place-assignments",
			"place finalization must remain the last expression preprocessor");
		final declarationRequest = HaxeOcamlTargetDeclarationAdapter.fromModuleTypes("stock-target-definition-fixture", []);
		assertTrue(declarationRequest.copyClasses().length == 0, "empty standalone program produced declaration facts");
		return macro null;
	}

	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			Context.error(message, Context.currentPos());
	}
}
