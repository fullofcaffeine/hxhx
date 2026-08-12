import haxe.macro.Context;
import haxe.macro.Expr;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.lowered.OcamlStringMethodPlan;
import reflaxe.ocaml.lowered.OcamlStringMethodPlan.OcamlStringMethodDecision;
import reflaxe.ocaml.lowered.OcamlStringMethodPlan.OcamlStringMethodOperation;
import reflaxe.ocaml.lowered.OcamlStringMethodPlan.OcamlStringMethodOptionalCarrier;
import reflaxe.ocaml.lowered.OcamlStringMethodPlan.OcamlStringMethodPlanner;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementLedger;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

using StringTools;

/**
	Defines the expected source selection for direct Haxe String methods.

	The expected method names and helper symbols are written here independently.
	The fixture does not inspect the target builder or generated OCaml.
**/
class StringMethodRuntimeUseFixture {
	static final binding:OcamlFunctionPlanBinding = {
		functionId: "StringMethodRuntimeUseFixture.main",
		programRevision: "program:string-method",
		bodyRevision: "body:string-method",
		pipelineRevision: "pipeline:string-method"
	};

	public static macro function run():Expr {
		final typed = Context.typeExpr(macro {
			final text = "abcdef";
			final nullableIndex:Null<Int> = 2;
			text.toUpperCase();
			text.toLowerCase();
			text.charAt(1);
			text.charCodeAt(1);
			final exactCode:Int = text.charCodeAt(1);
			text.indexOf("cd");
			text.indexOf("cd", null);
			text.indexOf("cd", nullableIndex);
			text.lastIndexOf("cd");
			text.lastIndexOf("cd", null);
			text.lastIndexOf("cd", nullableIndex);
			text.split(",");
			text.substr(1);
			text.substr(1, null);
			text.substr(1, nullableIndex);
			text.substring(1);
			text.substring(1, null);
			text.substring(1, nullableIndex);
			text.toString();
			exactCode;
		});

		final plan = new OcamlStringMethodPlanner(binding).plan(typed);
		final decisions = plan.decisions();
		if (decisions.length != 19)
			throw 'Expected 19 direct String method decisions, received ${decisions.length}.';
		assertCount(decisions, OcamlStringMethodOperation.ToUpperCase, 1);
		assertCount(decisions, OcamlStringMethodOperation.ToLowerCase, 1);
		assertCount(decisions, OcamlStringMethodOperation.CharAt, 1);
		assertCount(decisions, OcamlStringMethodOperation.CharCodeAt, 2);
		assertCount(decisions, OcamlStringMethodOperation.IndexOf, 3);
		assertCount(decisions, OcamlStringMethodOperation.LastIndexOf, 3);
		assertCount(decisions, OcamlStringMethodOperation.Split, 1);
		assertCount(decisions, OcamlStringMethodOperation.Substr, 3);
		assertCount(decisions, OcamlStringMethodOperation.Substring, 3);
		assertCount(decisions, OcamlStringMethodOperation.ToString, 1);
		assertCarrierCount(decisions, OcamlStringMethodOptionalCarrier.Omitted, 4);
		assertCarrierCount(decisions, OcamlStringMethodOptionalCarrier.ExplicitNull, 4);
		assertCarrierCount(decisions, OcamlStringMethodOptionalCarrier.NullableInt, 4);

		for (decision in decisions)
			proveRuntimeUse(decision);
		expectFailure("stale binding", "belongs to another function or target pipeline", () -> plan.requirePlanBinding({
			functionId: binding.functionId,
			programRevision: binding.programRevision,
			bodyRevision: binding.bodyRevision,
			pipelineRevision: binding.pipelineRevision + ":stale"
		}));

		Sys.println("REFLAXE_OCAML_STRING_METHOD_RUNTIME_USE:PASS");
		return macro null;
	}

	static function proveRuntimeUse(decision:OcamlStringMethodDecision):Void {
		OcamlStringMethodPlan.requireDecision(decision);
		final requirements = OcamlRuntimeRequirementLedger.requirementsForStringMethod(decision);
		if (requirements.length != 1 || requirements[0].rootModules.join(",") != OcamlStringMethodPlan.rootModules(decision).join(","))
			throw 'Decision "${decision.id}" has runtime roots that differ from its helper inventory.';
		if (decision.evaluationOrder[0] != "receiver")
			throw 'Decision "${decision.id}" must evaluate its receiver first.';
		final expectedMethod = "HxString." + (decision.operation : String);
		if (decision.runtimeUseOccurrences.filter(use -> use.exactSymbol == expectedMethod).length != 1)
			throw 'Decision "${decision.id}" must own $expectedMethod.';

		final authority = new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements, decision.runtimeUseOccurrences);
		final references:Array<OcamlExpr> = [];
		for (use in decision.runtimeUseOccurrences)
			references.push(OcamlExpr.ERuntimeIdent(authority.expressionIdentifier(use.id, use.planRevision, use.exactSymbol)));
		authority.reconcileExpression(OcamlExpr.ESeq(references));

		final first = decision.runtimeUseOccurrences[0];
		expectFailure("wrong symbol", "wrong target symbol",
			() -> new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements,
				decision.runtimeUseOccurrences).expressionIdentifier(first.id, first.planRevision, first.exactSymbol + "_wrong"));
		expectFailure("missing helper", "missing runtime use",
			() -> new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements,
				decision.runtimeUseOccurrences).reconcileExpression(OcamlExpr.ESeq([])));
		expectFailure("wrong profile", "not eligible for profile",
			() -> new OcamlRuntimeUseAuthority(decision.revision, "unsupported-profile", requirements,
				decision.runtimeUseOccurrences).expressionIdentifier(first.id, first.planRevision, first.exactSymbol));
		expectFailure("plain private helper", "plain private runtime reference",
			() -> new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements,
				decision.runtimeUseOccurrences).reconcileExpression(plainPrivateIdentifier(first.exactSymbol)));
		expectFailure("duplicate helper", "stale or conflicting runtime facts",
			() -> OcamlStringMethodPlan.requireDecision(copyDecision(decision, decision.operation, decision.runtimeUseOccurrences.concat([first]))));
		expectFailure("wrong owner", "conflicting helper",
			() -> OcamlStringMethodPlan.requireDecision(copyDecision(decision, decision.operation,
				[copyOccurrence(first, first.ownerId + ":wrong")].concat(decision.runtimeUseOccurrences.slice(1)))));
		final wrongOperation = decision.operation == OcamlStringMethodOperation.ToUpperCase ? OcamlStringMethodOperation.ToLowerCase : OcamlStringMethodOperation.ToUpperCase;
		expectFailure("changed method", "ocaml-string-method:",
			() -> OcamlStringMethodPlan.requireDecision(copyDecision(decision, wrongOperation, decision.runtimeUseOccurrences)));
		final reversedOrder = decision.evaluationOrder.concat(["argument:99"]);
		expectFailure("changed evaluation order", "invalid-shape",
			() -> OcamlStringMethodPlan.requireDecision(copyDecision(decision, decision.operation, decision.runtimeUseOccurrences, reversedOrder)));
		final wrongDomain = copyOccurrence(first, first.ownerId, OcamlRuntimeUseDomain.TypeIdentifier);
		expectFailure("wrong domain", "conflicting helper",
			() -> OcamlStringMethodPlan.requireDecision(copyDecision(decision, decision.operation,
				[wrongDomain].concat(decision.runtimeUseOccurrences.slice(1)))));
		expectFailure("changed argument shape", "ocaml-string-method:",
			() -> OcamlStringMethodPlan.requireDecision(copyDecision(decision, decision.operation, decision.runtimeUseOccurrences, null,
				decision.argumentSemanticTypeIds.concat(["Int"]))));
		expectFailure("changed result", "ocaml-string-method:",
			() -> OcamlStringMethodPlan.requireDecision(copyDecision(decision, decision.operation, decision.runtimeUseOccurrences, null, null,
				decision.resultSemanticTypeId + ":changed")));
		if (decision.runtimeUseOccurrences.length > 1) {
			final reorderedAuthority = new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements, decision.runtimeUseOccurrences);
			final reordered:Array<OcamlExpr> = [];
			for (use in decision.runtimeUseOccurrences)
				reordered.unshift(OcamlExpr.ERuntimeIdent(reorderedAuthority.expressionIdentifier(use.id, use.planRevision, use.exactSymbol)));
			expectFailure("reordered helpers", "does not match planned owner-local order",
				() -> reorderedAuthority.reconcileExpression(OcamlExpr.ESeq(reordered)));
		}
	}

	static function copyDecision(source:OcamlStringMethodDecision, operation:OcamlStringMethodOperation,
			runtimeUseOccurrences:Array<OcamlRuntimeUseOccurrence>, ?evaluationOrder:Array<String>, ?argumentSemanticTypeIds:Array<String>,
			?resultSemanticTypeId:String):OcamlStringMethodDecision {
		return {
			id: source.id,
			revision: source.revision,
			source: {file: source.source.file, min: source.source.min, max: source.source.max},
			operation: operation,
			receiverSemanticTypeId: source.receiverSemanticTypeId,
			argumentSemanticTypeIds: argumentSemanticTypeIds == null ? source.argumentSemanticTypeIds.copy() : argumentSemanticTypeIds.copy(),
			optionalCarrier: source.optionalCarrier,
			optionalDefault: source.optionalDefault,
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

	static function plainPrivateIdentifier(symbol:String):OcamlExpr {
		final separator = symbol.indexOf(".");
		return separator < 0 ? OcamlExpr.EIdent(symbol) : OcamlExpr.EField(OcamlExpr.EIdent(symbol.substr(0, separator)), symbol.substr(separator + 1));
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

	static function assertCarrierCount(decisions:Array<OcamlStringMethodDecision>, carrier:OcamlStringMethodOptionalCarrier, expected:Int):Void {
		final actual = decisions.filter(decision -> decision.optionalCarrier == carrier).length;
		if (actual != expected)
			throw '${(carrier : String)} expected $expected decisions, received $actual.';
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

	static function assertCount(decisions:Array<reflaxe.ocaml.lowered.OcamlStringMethodPlan.OcamlStringMethodDecision>, operation:OcamlStringMethodOperation,
			expected:Int):Void {
		final actual = decisions.filter(decision -> decision.operation == operation).length;
		if (actual != expected)
			throw '${(operation : String)} expected $expected decisions, received $actual.';
	}
}
