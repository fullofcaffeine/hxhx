import haxe.macro.Context;
import haxe.macro.Expr;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.lowered.OcamlStringFieldPlan;
import reflaxe.ocaml.lowered.OcamlStringFieldPlan.OcamlStringFieldDecision;
import reflaxe.ocaml.lowered.OcamlStringFieldPlan.OcamlStringFieldPlanner;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementLedger;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

using StringTools;

/**
	Defines the expected runtime helper for a direct `String.length` read.

	The expected field, types, schedule, and helper name are written here. The
	fixture does not inspect the target builder or generated OCaml.
**/
class StringFieldRuntimeUseFixture {
	static final binding:OcamlFunctionPlanBinding = {
		functionId: "StringFieldRuntimeUseFixture.main",
		programRevision: "program:string-field",
		bodyRevision: "body:string-field",
		pipelineRevision: "pipeline:string-field"
	};

	public static macro function run():Expr {
		final typed = Context.typeExpr(macro {
			final text = "abc";
			text.length;
		});
		final plan = new OcamlStringFieldPlanner(binding).plan(typed);
		final decisions = plan.decisions();
		if (decisions.length != 1)
			throw 'Expected one direct String.length decision, received ${decisions.length}.';

		proveRuntimeUse(decisions[0]);
		expectFailure("missing decision", "has no sealed source occurrence", () -> plan.requireFor(Context.typeExpr(macro "other".length)));
		expectFailure("duplicate decision", "sealed more than once", () -> new OcamlStringFieldPlan([decisions[0], decisions[0]]));
		expectFailure("stale binding", "belongs to another function or target pipeline", () -> plan.requirePlanBinding({
			functionId: binding.functionId,
			programRevision: binding.programRevision,
			bodyRevision: binding.bodyRevision,
			pipelineRevision: binding.pipelineRevision + ":stale"
		}));

		Sys.println("REFLAXE_OCAML_STRING_FIELD_RUNTIME_USE:PASS");
		return macro null;
	}

	static function proveRuntimeUse(decision:OcamlStringFieldDecision):Void {
		OcamlStringFieldPlan.requireDecision(decision);
		if (decision.fieldName != "length"
			|| decision.receiverSemanticTypeId != "String"
			|| decision.resultSemanticTypeId != "Int"
			|| decision.evaluationOrder.join(",") != "receiver,runtime-read")
			throw 'Decision "${decision.id}" has the wrong field, type, or evaluation schedule.';

		final requirements = OcamlRuntimeRequirementLedger.requirementsForStringField(decision);
		if (requirements.length != 1
			|| requirements[0].semanticCapability != "haxe-string-field-read"
			|| requirements[0].rootModules.join(",") != "HxString")
			throw 'Decision "${decision.id}" has the wrong runtime requirement.';

		final occurrence = decision.runtimeUseOccurrences[0];
		if (occurrence.exactSymbol != "HxString.length" || occurrence.role != "read-length")
			throw 'Decision "${decision.id}" must own one HxString.length read.';
		final authority = new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements, decision.runtimeUseOccurrences);
		final checked = OcamlExpr.ERuntimeIdent(authority.expressionIdentifier(occurrence.id, occurrence.planRevision, occurrence.exactSymbol));
		authority.reconcileExpression(OcamlExpr.EApp(checked, [OcamlExpr.EIdent("receiver")]));

		expectFailure("wrong symbol", "wrong target symbol",
			() -> new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements,
				decision.runtimeUseOccurrences).expressionIdentifier(occurrence.id, occurrence.planRevision, occurrence.exactSymbol + "_wrong"));
		expectFailure("missing helper", "missing runtime use",
			() -> new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements,
				decision.runtimeUseOccurrences).reconcileExpression(OcamlExpr.EIdent("receiver")));
		expectFailure("wrong profile", "not eligible for profile",
			() -> new OcamlRuntimeUseAuthority(decision.revision, "unsupported-profile", requirements,
				decision.runtimeUseOccurrences).expressionIdentifier(occurrence.id, occurrence.planRevision, occurrence.exactSymbol));
		expectFailure("plain private helper", "plain private runtime reference",
			() -> new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements,
				decision.runtimeUseOccurrences).reconcileExpression(plainPrivateIdentifier(occurrence.exactSymbol)));
		expectFailure("duplicate helper", "incomplete or incompatible facts",
			() -> OcamlStringFieldPlan.requireDecision(copyDecision(decision, decision.runtimeUseOccurrences.concat([occurrence]))));
		expectFailure("wrong owner", "stale or conflicting runtime facts",
			() -> OcamlStringFieldPlan.requireDecision(copyDecision(decision, [copyOccurrence(occurrence, occurrence.ownerId + ":wrong")])));
		expectFailure("wrong domain", "stale or conflicting runtime facts", () -> OcamlStringFieldPlan.requireDecision(copyDecision(decision, [
			copyOccurrence(occurrence, occurrence.ownerId, OcamlRuntimeUseDomain.TypeIdentifier)
		])));
		expectFailure("changed result", "incomplete or incompatible facts",
			() -> OcamlStringFieldPlan.requireDecision(copyDecision(decision, decision.runtimeUseOccurrences, "String")));
		expectFailure("changed schedule", "incomplete or incompatible facts",
			() -> OcamlStringFieldPlan.requireDecision(copyDecision(decision, decision.runtimeUseOccurrences, null, ["runtime-read", "receiver"])));
	}

	static function copyDecision(source:OcamlStringFieldDecision, runtimeUseOccurrences:Array<OcamlRuntimeUseOccurrence>, ?resultSemanticTypeId:String,
			?evaluationOrder:Array<String>):OcamlStringFieldDecision {
		return {
			id: source.id,
			revision: source.revision,
			source: {file: source.source.file, min: source.source.min, max: source.source.max},
			fieldName: source.fieldName,
			receiverSemanticTypeId: source.receiverSemanticTypeId,
			resultSemanticTypeId: resultSemanticTypeId ?? source.resultSemanticTypeId,
			evaluationOrder: evaluationOrder == null ? source.evaluationOrder.copy() : evaluationOrder.copy(),
			order: source.order,
			profileEligibility: source.profileEligibility.copy(),
			runtimeRequirementIds: source.runtimeRequirementIds.copy(),
			runtimeUseOccurrences: runtimeUseOccurrences,
			proofId: source.proofId,
			proofClaim: source.proofClaim,
			functionId: source.functionId,
			programRevision: source.programRevision,
			bodyRevision: source.bodyRevision,
			pipelineRevision: source.pipelineRevision
		};
	}

	static function copyOccurrence(source:OcamlRuntimeUseOccurrence, ownerId:String, ?domain:OcamlRuntimeUseDomain):OcamlRuntimeUseOccurrence {
		return {
			id: source.id,
			planRevision: source.planRevision,
			ownerId: ownerId,
			requirementId: source.requirementId,
			domain: domain ?? source.domain,
			exactSymbol: source.exactSymbol,
			role: source.role,
			order: source.order,
			source: {
				file: source.source.file,
				min: source.source.min,
				max: source.source.max
			},
			profileEligibility: source.profileEligibility.copy(),
			cardinality: source.cardinality
		};
	}

	static function plainPrivateIdentifier(symbol:String):OcamlExpr {
		final separator = symbol.indexOf(".");
		return separator < 0 ? OcamlExpr.EIdent(symbol) : OcamlExpr.EField(OcamlExpr.EIdent(symbol.substr(0, separator)), symbol.substr(separator + 1));
	}

	static function expectFailure(label:String, marker:String, operation:Void->Void):Void {
		var message:Null<String> = null;
		try {
			operation();
		} catch (error:Dynamic) {
			message = Std.string(error);
		}
		if (message == null || !message.contains(marker))
			throw '$label must fail with "$marker", received ${message == null ? "no failure" : message}.';
	}
}
