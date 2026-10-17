package reflaxe.ocaml.target;

import reflaxe.ocaml.ast.OcamlConst;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.lowered.OcamlClassIdentityMarkerPlan;
import reflaxe.ocaml.lowered.OcamlClassIdentityMarkerPlan.OcamlClassIdentityMarkerDecision;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin;
import reflaxe.ocaml.runtimegen.OcamlFinalRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirement;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementCause;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementSourceKind;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementSubjectKind;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseAuthority;

/** Checked class identity syntax and the runtime requirements its publisher must record. **/
typedef OcamlTargetLoweredClassMarker = {
	final expression:OcamlExpr;
	final runtimeRequirements:Array<OcamlRuntimeRequirement>;
}

/**
	Emit the existing Haxe class marker from one sealed class and allocation role.

	Each constructor or empty allocation owns a separate occurrence of HxType.class_.
	The shared authority checks its symbol, revision and profile, and observes that
	occurrence in the final output. Hosts supply actual class decisions; this module
	does not infer a class from generated text or invent a replacement marker value.
**/
function lowerClassMarker(decision:OcamlClassIdentityMarkerDecision, profile:String, ?finalOutput:OcamlFinalRuntimeUseAuthority):OcamlTargetLoweredClassMarker {
	OcamlClassIdentityMarkerPlan.requireDecision(decision);
	final requirements = requirementsForClassMarker(decision);
	final authority = new OcamlRuntimeUseAuthority(decision.revision, profile, requirements, decision.runtimeUseOccurrences, finalOutput);
	final occurrence = decision.runtimeUseOccurrences[0];
	final reference = authority.expressionIdentifier(occurrence.id, occurrence.planRevision, occurrence.exactSymbol);
	final expression = OcamlExpr.EApp(OcamlExpr.ERuntimeIdent(reference), [OcamlExpr.EConst(OcamlConst.CString(decision.runtimeClassName))]);
	authority.reconcileExpression(expression);
	return {expression: expression, runtimeRequirements: requirements};
}

/**
	Copy the checked marker's runtime dependency without importing host planners.

	Both native lowering and the standalone compiler's ledger use this one
	definition. The decision validates the variable facts; the remaining fields
	are fixed by the class-marker contract. All nested values are owned copies.
 */
function requirementsForClassMarker(decision:OcamlClassIdentityMarkerDecision):Array<OcamlRuntimeRequirement> {
	OcamlClassIdentityMarkerPlan.requireDecision(decision);
	return [
		{
			id: decision.runtimeRequirementIds[0],
			sourceKind: OcamlRuntimeRequirementSourceKind.RepresentationDecision,
			sourceId: StringTools.trim(decision.sourceDeclarationId),
			source: {
				file: OcamlLoweredOrigin.normalizeSourcePath(decision.source.file),
				min: decision.source.min,
				max: decision.source.max
			},
			semanticCapability: OcamlClassIdentityMarkerPlan.RUNTIME_CAPABILITY,
			cause: OcamlRuntimeRequirementCause.RepresentationDecision,
			decisionId: decision.id,
			subject: {
				kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
				id: StringTools.trim(decision.sourceDeclarationId)
			},
			implementationFeature: OcamlClassIdentityMarkerPlan.IMPLEMENTATION_FEATURE,
			rootModules: ["HxType"],
			profileEligibility: decision.profileEligibility.copy(),
			explanation: 'The generated ${decision.emissionRole} for ${decision.sourceDeclarationId} stores the exact Haxe runtime class marker used by Type.getClass.'
		}
	];
}
