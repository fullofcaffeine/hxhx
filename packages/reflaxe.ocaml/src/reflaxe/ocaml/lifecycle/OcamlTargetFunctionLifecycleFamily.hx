package reflaxe.ocaml.lifecycle;

#if (macro || reflaxe_runtime)
import reflaxe.data.ClassFuncData;
import reflaxe.lifecycle.SemanticArtifactBinding;
import reflaxe.lifecycle.SemanticArtifactFamily;
import reflaxe.lifecycle.SemanticArtifactSnapshot;
import reflaxe.lifecycle.SemanticPreprocessorAction;
import reflaxe.ocaml.preprocessor.FinalizePlaceAssignmentsImpl;
import reflaxe.ocaml.preprocessor.InlineSwitchTempImpl;
import reflaxe.ocaml.preprocessor.PreservePlaceAssignmentsImpl;
import reflaxe.ocaml.target.HaxeOcamlTargetFunctionAdapter;
import reflaxe.ocaml.target.OcamlTargetFunctionCatalog;

/** Keeps an admitted preprocessor-free target function authoritative through Reflaxe rewrites. **/
class OcamlTargetFunctionLifecycleFamily extends SemanticArtifactFamily {
	public static inline final ID = "reflaxe.ocaml.target-functions";

	final catalog:OcamlTargetFunctionCatalog;

	public function new(catalog:OcamlTargetFunctionCatalog) {
		super(ID, SemanticArtifactBinding.StructuralEnvelope);
		this.catalog = catalog;
	}

	public function snapshot(data:ClassFuncData):Array<SemanticArtifactSnapshot> {
		final expected = catalog.find(data.id);
		return [
			for (identity in HaxeOcamlTargetFunctionAdapter.markerIdentities(data.expr))
				{
					id: identity,
					fingerprint: expected != null && expected.getCanonicalIdentity() == identity ? identity : "missing-catalog-fact",
					origin: "preprocessor-stable shared target function"
				}
		];
	}

	public function actionFor(preprocessorId:String):SemanticPreprocessorAction {
		return switch (preprocessorId) {
			case PreservePlaceAssignmentsImpl.ID | FinalizePlaceAssignmentsImpl.ID | InlineSwitchTempImpl.ID | "sanitize-everything-is-expression" | "remove-temporary-variables" | "prevent-repeat-variables" | "wrap-lambda-captures" | "remove-pure-expressions" | "remove-single-expression-blocks" | "remove-constant-bool-ifs" | "remove-unnecessary-blocks" | "remove-reassigned-variable-declarations" | "remove-local-variable-aliases" | "mark-unused-variables":
				SemanticPreprocessorAction.Preserve;
			case _:
				SemanticPreprocessorAction.Reject;
		};
	}

	override public function validateFinal(data:ClassFuncData, artifacts:Array<SemanticArtifactSnapshot>):Null<String> {
		final expected = catalog.find(data.id);
		if (expected == null)
			return artifacts.length == 0 ? null : 'function "${data.id}" contains target-function metadata without a catalog fact';
		if (artifacts.length != 1)
			return 'function "${data.id}" must retain exactly one shared target-function envelope';
		final identity = expected.getCanonicalIdentity();
		return artifacts[0].id == identity
			&& artifacts[0].fingerprint == identity ? null : 'function "${data.id}" retained the wrong shared target-function identity';
	}
}
#end
