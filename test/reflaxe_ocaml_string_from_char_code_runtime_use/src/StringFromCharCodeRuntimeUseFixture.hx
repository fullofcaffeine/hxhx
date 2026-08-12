import haxe.macro.Context;
import haxe.macro.Expr;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.lowered.OcamlStringFromCharCodePlan;
import reflaxe.ocaml.lowered.OcamlStringFromCharCodePlan.OcamlStringFromCharCodeArgumentCarrier;
import reflaxe.ocaml.lowered.OcamlStringFromCharCodePlan.OcamlStringFromCharCodeDecision;
import reflaxe.ocaml.lowered.OcamlStringFromCharCodePlan.OcamlStringFromCharCodeForm;
import reflaxe.ocaml.lowered.OcamlStringFromCharCodePlan.OcamlStringFromCharCodePlanner;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementLedger;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

using StringTools;

/**
	Defines the expected runtime ownership for `String.fromCharCode`.

	This fixture starts from typed Haxe expressions. It names the required helper
	sequence independently from `OcamlBuilder`, so a syntax change cannot update
	the expectation by accident.
**/
class StringFromCharCodeRuntimeUseFixture {
	static final binding:OcamlFunctionPlanBinding = {
		functionId: "StringFromCharCodeRuntimeUseFixture.main",
		programRevision: "program:string-from-char-code",
		bodyRevision: "body:string-from-char-code",
		pipelineRevision: "pipeline:string-from-char-code"
	};

	public static macro function run():Expr {
		final typed = Context.typeExpr(macro {
			String.fromCharCode(65);
			final nullable:Null<Int> = 66;
			String.fromCharCode(nullable);
			final encode:Int->String = String.fromCharCode;
			encode(67);
			final nested = () -> String.fromCharCode(68);
			nested;
		});

		final plan = new OcamlStringFromCharCodePlanner(binding).plan(typed);
		final decisions = plan.decisions();
		assertDecision(decisions, OcamlStringFromCharCodeForm.DirectCall, OcamlStringFromCharCodeArgumentCarrier.ExactInt, ["HxString.fromCharCode"]);
		assertDecision(decisions, OcamlStringFromCharCodeForm.DirectCall, OcamlStringFromCharCodeArgumentCarrier.NullableInt,
			["HxString.fromCharCode", "HxRuntime.hx_null"]);
		assertDecision(decisions, OcamlStringFromCharCodeForm.FunctionValue, null, ["HxString.fromCharCode"]);
		if (decisions.length != 3)
			throw 'Expected three outer-root decisions, received ${decisions.length}.';

		for (decision in decisions)
			proveRuntimeUses(decision);
		expectFailure("stale binding", "belongs to another function or target pipeline", () -> plan.requirePlanBinding({
			functionId: binding.functionId,
			programRevision: binding.programRevision,
			bodyRevision: binding.bodyRevision,
			pipelineRevision: binding.pipelineRevision + ":stale"
		}));

		Sys.println("REFLAXE_OCAML_STRING_FROM_CHAR_CODE_RUNTIME_USE:PASS");
		return macro null;
	}

	static function proveRuntimeUses(decision:OcamlStringFromCharCodeDecision):Void {
		OcamlStringFromCharCodePlan.requireDecision(decision);
		final requirements = OcamlRuntimeRequirementLedger.requirementsForStringFromCharCode(decision);
		if (requirements.length != 1)
			throw 'Decision "${decision.id}" must own one runtime requirement.';
		final authority = new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements, decision.runtimeUseOccurrences);
		final references = decision.runtimeUseOccurrences.map(use -> OcamlExpr.ERuntimeIdent(authority.expressionIdentifier(use.id, use.planRevision,
			use.exactSymbol)));
		authority.reconcileExpression(OcamlExpr.ESeq(references));

		final first = decision.runtimeUseOccurrences[0];
		expectFailure("wrong symbol", "wrong target symbol",
			() -> new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements,
				decision.runtimeUseOccurrences).expressionIdentifier(first.id, first.planRevision, first.exactSymbol + "_wrong"));
		expectFailure("missing helper", "missing runtime use",
			() -> new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements,
				decision.runtimeUseOccurrences).reconcileExpression(OcamlExpr.ESeq([])));
		expectFailure("duplicate helper", "invalid-runtime-use",
			() -> OcamlStringFromCharCodePlan.requireDecision(copyDecision(decision, decision.form, decision.argumentCarrier,
				decision.runtimeUseOccurrences.concat([first]))));
		if (decision.runtimeUseOccurrences.length == 2) {
			final reordered = [decision.runtimeUseOccurrences[1], decision.runtimeUseOccurrences[0]];
			expectFailure("reordered helper", "invalid-runtime-use",
				() -> OcamlStringFromCharCodePlan.requireDecision(copyDecision(decision, decision.form, decision.argumentCarrier, reordered)));
		}
		final wrongOwner = copyOccurrence(first, first.ownerId + ":wrong");
		expectFailure("wrong owner", "invalid-runtime-use",
			() -> OcamlStringFromCharCodePlan.requireDecision(copyDecision(decision, decision.form, decision.argumentCarrier,
				[wrongOwner].concat(decision.runtimeUseOccurrences.slice(1)))));
		final wrongForm = decision.form == OcamlStringFromCharCodeForm.DirectCall ? OcamlStringFromCharCodeForm.FunctionValue : OcamlStringFromCharCodeForm.DirectCall;
		expectFailure("wrong form", "invalid-form",
			() -> OcamlStringFromCharCodePlan.requireDecision(copyDecision(decision, wrongForm, decision.argumentCarrier, decision.runtimeUseOccurrences)));
	}

	static function assertDecision(decisions:Array<OcamlStringFromCharCodeDecision>, form:OcamlStringFromCharCodeForm,
			argumentCarrier:Null<OcamlStringFromCharCodeArgumentCarrier>, expectedSymbols:Array<String>):Void {
		final selected = decisions.filter(decision -> decision.form == form && decision.argumentCarrier == argumentCarrier);
		if (selected.length != 1)
			throw 'Expected one ${(form : String)}/${argumentCarrier == null ? "none" : (argumentCarrier : String)} decision, received ${selected.length}.';
		final actualSymbols = selected[0].runtimeUseOccurrences.map(use -> use.exactSymbol);
		if (actualSymbols.join(",") != expectedSymbols.join(","))
			throw '${(form : String)} expected ${expectedSymbols.join(",")}, received ${actualSymbols.join(",")}.';
	}

	static function copyDecision(source:OcamlStringFromCharCodeDecision, form:OcamlStringFromCharCodeForm,
			argumentCarrier:Null<OcamlStringFromCharCodeArgumentCarrier>,
			runtimeUseOccurrences:Array<OcamlRuntimeUseOccurrence>):OcamlStringFromCharCodeDecision {
		return {
			id: source.id,
			revision: source.revision,
			source: {file: source.source.file, min: source.source.min, max: source.source.max},
			form: form,
			argumentCarrier: argumentCarrier,
			argumentSemanticTypeId: source.argumentSemanticTypeId,
			resultSemanticTypeId: source.resultSemanticTypeId,
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

	static function copyOccurrence(source:OcamlRuntimeUseOccurrence, ownerId:String):OcamlRuntimeUseOccurrence {
		return {
			id: source.id,
			planRevision: source.planRevision,
			ownerId: ownerId,
			requirementId: source.requirementId,
			domain: source.domain,
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
