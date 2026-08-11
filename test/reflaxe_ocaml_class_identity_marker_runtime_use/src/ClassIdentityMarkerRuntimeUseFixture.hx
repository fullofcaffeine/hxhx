package;

import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import reflaxe.ocaml.ast.OcamlConst;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.lowered.OcamlClassIdentityMarkerPlan;
import reflaxe.ocaml.lowered.OcamlClassIdentityMarkerPlan.OcamlClassIdentityMarkerDecision;
import reflaxe.ocaml.runtimegen.OcamlFinalRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementLedger;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementCause;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementSourceKind;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementSubjectKind;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

using StringTools;

/**
	Checks that each generated class record owns its private class marker.

	A class marker is the hidden `HxType.class_ "package.Class"` value stored in
	every generated instance. It lets `Type.getClass` recover the Haxe class. This
	fixture proves that the constructor and empty-instance records get separate,
	typed permissions for that same private runtime call.
**/
class ClassIdentityMarkerRuntimeUseFixture {
	static inline final PROGRAM_REVISION = "program:class-marker";
	static inline final PIPELINE_REVISION = "pipeline:class-marker";
	static inline final PROFILE = "portable";

	public static macro function run():Expr {
		final classType = markerClass();
		final constructor = seal(classType, OcamlClassIdentityMarkerPlan.CONSTRUCTOR_ROLE);
		final empty = seal(classType, OcamlClassIdentityMarkerPlan.EMPTY_INSTANCE_ROLE);
		if (constructor.id == empty.id
			|| constructor.runtimeRequirementIds[0] == empty.runtimeRequirementIds[0]
			|| constructor.runtimeUseOccurrences[0].id == empty.runtimeUseOccurrences[0].id)
			throw "Constructor and empty-instance markers must have different identities.";

		proveRequirement(constructor);
		proveRequirement(empty);
		proveCheckedMarker(constructor);
		proveCheckedMarker(empty);
		proveDecisionFailures(classType, constructor);
		proveAuthorityFailures(constructor);
		proveFinalOutput(constructor, empty);

		Sys.println("REFLAXE_OCAML_CLASS_IDENTITY_MARKER_RUNTIME_USE:PASS");
		return macro null;
	}

	static function markerClass():ClassType {
		return switch (Context.getType("fixture.Marker")) {
			case TInst(classRef, _): classRef.get();
			case _: throw "fixture.Marker did not resolve to a class.";
		};
	}

	static function seal(classType:ClassType, role:String):OcamlClassIdentityMarkerDecision {
		final decision = OcamlClassIdentityMarkerPlan.seal(classType, "fixture.Marker", role, PROGRAM_REVISION, PIPELINE_REVISION);
		OcamlClassIdentityMarkerPlan.requireDecision(decision);
		if (decision.sourceDeclarationId != "fixture.Marker"
			|| decision.runtimeClassName != "fixture.Marker"
			|| decision.emissionRole != role)
			throw 'Class marker $role did not retain its exact typed class facts.';
		return decision;
	}

	static function proveRequirement(decision:OcamlClassIdentityMarkerDecision):Void {
		final requirements = OcamlRuntimeRequirementLedger.requirementsForClassIdentityMarker(decision);
		if (requirements.length != 1)
			throw 'Class marker ${decision.id} must own one runtime requirement.';
		final requirement = requirements[0];
		if (requirement.id != decision.runtimeRequirementIds[0]
			|| requirement.sourceKind != OcamlRuntimeRequirementSourceKind.RepresentationDecision
			|| requirement.sourceId != "fixture.Marker"
			|| requirement.cause != OcamlRuntimeRequirementCause.RepresentationDecision
			|| requirement.decisionId != decision.id
			|| requirement.subject.kind != OcamlRuntimeRequirementSubjectKind.HaxeType
			|| requirement.subject.id != "fixture.Marker"
			|| requirement.rootModules.join(",") != "HxType"
			|| requirement.profileEligibility.join(",") != "metal,portable")
			throw 'Class marker ${decision.id} did not produce the exact HxType requirement.';
	}

	static function proveCheckedMarker(decision:OcamlClassIdentityMarkerDecision):Void {
		checkedMarker(decision);
	}

	static function checkedMarker(decision:OcamlClassIdentityMarkerDecision, ?finalOutput:OcamlFinalRuntimeUseAuthority):OcamlExpr {
		final requirements = OcamlRuntimeRequirementLedger.requirementsForClassIdentityMarker(decision);
		final occurrence = decision.runtimeUseOccurrences[0];
		final authority = new OcamlRuntimeUseAuthority(decision.revision, PROFILE, requirements, decision.runtimeUseOccurrences, finalOutput);
		final reference = authority.expressionIdentifier(occurrence.id, occurrence.planRevision, occurrence.exactSymbol);
		final marker = OcamlExpr.EApp(OcamlExpr.ERuntimeIdent(reference), [OcamlExpr.EConst(OcamlConst.CString(decision.runtimeClassName))]);
		authority.reconcileExpression(marker);
		return marker;
	}

	static function proveDecisionFailures(classType:ClassType, decision:OcamlClassIdentityMarkerDecision):Void {
		expectFailure("wrong runtime class", "wrong-runtime-name",
			() -> OcamlClassIdentityMarkerPlan.seal(classType, "fixture.Other", decision.emissionRole, PROGRAM_REVISION, PIPELINE_REVISION));
		expectFailure("unsupported record role", "unsupported-role",
			() -> OcamlClassIdentityMarkerPlan.seal(classType, "fixture.Marker", "some-other-record", PROGRAM_REVISION, PIPELINE_REVISION));
		expectFailure("stale pipeline", "stale-decision",
			() -> OcamlClassIdentityMarkerPlan.requireDecision(copyDecision(decision, PIPELINE_REVISION + ":stale")));

		final occurrence = decision.runtimeUseOccurrences[0];
		expectFailure("wrong occurrence owner", "stale-runtime-use",
			() -> OcamlClassIdentityMarkerPlan.requireDecision(copyDecision(decision, null,
				[copyOccurrence(occurrence, null, occurrence.ownerId + ":wrong")])));
		expectFailure("wrong occurrence symbol", "stale-runtime-use", () -> OcamlClassIdentityMarkerPlan.requireDecision(copyDecision(decision, null, [
			copyOccurrence(occurrence, null, null, OcamlClassIdentityMarkerPlan.EXACT_SYMBOL + "_wrong")
		])));
		expectFailure("wrong occurrence domain", "stale-runtime-use",
			() -> OcamlClassIdentityMarkerPlan.requireDecision(copyDecision(decision, null,
				[copyOccurrence(occurrence, OcamlRuntimeUseDomain.TypeIdentifier)])));
		expectFailure("wrong occurrence profile", "stale-runtime-use",
			() -> OcamlClassIdentityMarkerPlan.requireDecision(copyDecision(decision, null, [copyOccurrence(occurrence, null, null, null, ["metal"])])));
		expectFailure("missing occurrence", "stale-decision", () -> OcamlClassIdentityMarkerPlan.requireDecision(copyDecision(decision, null, [])));
		expectFailure("duplicate occurrence", "stale-decision",
			() -> OcamlClassIdentityMarkerPlan.requireDecision(copyDecision(decision, null, [occurrence, occurrence])));
	}

	static function proveAuthorityFailures(decision:OcamlClassIdentityMarkerDecision):Void {
		final requirements = OcamlRuntimeRequirementLedger.requirementsForClassIdentityMarker(decision);
		final occurrence = decision.runtimeUseOccurrences[0];
		expectFailure("missing marker", "missing runtime use",
			() -> new OcamlRuntimeUseAuthority(decision.revision, PROFILE, requirements,
				decision.runtimeUseOccurrences).reconcileExpression(OcamlExpr.EConst(OcamlConst.CUnit)));
		expectFailure("plain marker", "plain private runtime reference HxType.class_",
			() -> new OcamlRuntimeUseAuthority(decision.revision, PROFILE, requirements,
				decision.runtimeUseOccurrences).reconcileExpression(OcamlExpr.EField(OcamlExpr.EIdent("HxType"), "class_")));
		expectFailure("stale marker", "stale runtime use",
			() -> new OcamlRuntimeUseAuthority(decision.revision, PROFILE, requirements,
				decision.runtimeUseOccurrences).expressionIdentifier(occurrence.id, occurrence.planRevision + ":stale", occurrence.exactSymbol));
		expectFailure("wrong marker symbol", "wrong target symbol",
			() -> new OcamlRuntimeUseAuthority(decision.revision, PROFILE, requirements,
				decision.runtimeUseOccurrences).expressionIdentifier(occurrence.id, occurrence.planRevision, occurrence.exactSymbol + "_wrong"));
		expectFailure("wrong marker domain", "wrong target domain",
			() -> new OcamlRuntimeUseAuthority(decision.revision, PROFILE, requirements,
				decision.runtimeUseOccurrences).typeIdentifier(occurrence.id, occurrence.planRevision, occurrence.exactSymbol));
		final metalOnly = copyOccurrence(occurrence, null, null, null, ["metal"]);
		expectFailure("wrong marker profile", "not eligible for profile portable",
			() -> new OcamlRuntimeUseAuthority(decision.revision, PROFILE, requirements,
				[metalOnly]).expressionIdentifier(metalOnly.id, metalOnly.planRevision, metalOnly.exactSymbol));

		final duplicate = new OcamlRuntimeUseAuthority(decision.revision, PROFILE, requirements, decision.runtimeUseOccurrences);
		duplicate.expressionIdentifier(occurrence.id, occurrence.planRevision, occurrence.exactSymbol);
		expectFailure("duplicate marker construction", "constructed more than once",
			() -> duplicate.expressionIdentifier(occurrence.id, occurrence.planRevision, occurrence.exactSymbol));

		final duplicateOutput = new OcamlRuntimeUseAuthority(decision.revision, PROFILE, requirements, decision.runtimeUseOccurrences);
		final reference = duplicateOutput.expressionIdentifier(occurrence.id, occurrence.planRevision, occurrence.exactSymbol);
		expectFailure("duplicate marker output", "duplicate runtime use",
			() -> duplicateOutput.reconcileExpression(OcamlExpr.ESeq([OcamlExpr.ERuntimeIdent(reference), OcamlExpr.ERuntimeIdent(reference)])));
	}

	static function proveFinalOutput(constructor:OcamlClassIdentityMarkerDecision, empty:OcamlClassIdentityMarkerDecision):Void {
		final finalOutput = new OcamlFinalRuntimeUseAuthority();
		finalOutput.beginProgram(PROGRAM_REVISION, PROFILE);
		final constructorMarker = checkedMarker(constructor, finalOutput);
		final emptyMarker = checkedMarker(empty, finalOutput);
		finalOutput.observeExpression(constructorMarker, "fixture.Marker::create::__hx_type");
		finalOutput.observeExpression(emptyMarker, "fixture.Marker::__empty::__hx_type");
		finalOutput.finishProgram();

		final missingOutput = new OcamlFinalRuntimeUseAuthority();
		missingOutput.beginProgram(PROGRAM_REVISION, PROFILE);
		checkedMarker(constructor, missingOutput);
		expectFailure("missing final marker", "missing final runtime use", missingOutput.finishProgram);

		final duplicateOutput = new OcamlFinalRuntimeUseAuthority();
		duplicateOutput.beginProgram(PROGRAM_REVISION, PROFILE);
		final duplicateMarker = checkedMarker(constructor, duplicateOutput);
		duplicateOutput.observeExpression(duplicateMarker, "fixture.Marker::create:first");
		expectFailure("duplicate final marker", "duplicate final runtime use",
			() -> duplicateOutput.observeExpression(duplicateMarker, "fixture.Marker::create:second"));
	}

	static function copyDecision(source:OcamlClassIdentityMarkerDecision, ?pipelineRevision:String,
			?runtimeUseOccurrences:Array<OcamlRuntimeUseOccurrence>):OcamlClassIdentityMarkerDecision {
		return {
			id: source.id,
			revision: source.revision,
			programRevision: source.programRevision,
			pipelineRevision: pipelineRevision == null ? source.pipelineRevision : pipelineRevision,
			source: {
				file: source.source.file,
				min: source.source.min,
				max: source.source.max
			},
			sourceDeclarationId: source.sourceDeclarationId,
			runtimeClassName: source.runtimeClassName,
			emissionRole: source.emissionRole,
			profileEligibility: source.profileEligibility.copy(),
			runtimeRequirementIds: source.runtimeRequirementIds.copy(),
			runtimeUseOccurrences: runtimeUseOccurrences == null ? source.runtimeUseOccurrences.copy() : runtimeUseOccurrences,
			proofId: source.proofId,
			proofClaim: source.proofClaim
		};
	}

	static function copyOccurrence(source:OcamlRuntimeUseOccurrence, ?domain:OcamlRuntimeUseDomain, ?ownerId:String, ?exactSymbol:String,
			?profiles:Array<String>):OcamlRuntimeUseOccurrence {
		return {
			id: source.id,
			planRevision: source.planRevision,
			ownerId: ownerId == null ? source.ownerId : ownerId,
			requirementId: source.requirementId,
			domain: domain == null ? source.domain : domain,
			exactSymbol: exactSymbol == null ? source.exactSymbol : exactSymbol,
			role: source.role,
			order: source.order,
			source: {
				file: source.source.file,
				min: source.source.min,
				max: source.source.max
			},
			profileEligibility: profiles == null ? source.profileEligibility.copy() : profiles,
			cardinality: source.cardinality
		};
	}

	static function expectFailure(label:String, marker:String, operation:Void->Void):Void {
		var message:Null<String> = null;
		try {
			operation();
		} catch (error:Dynamic) {
			message = Std.string(error);
		}
		if (message == null || !message.contains(marker))
			throw '$label must fail with "$marker", received ${message == null ? "no error" : message}.';
	}
}
