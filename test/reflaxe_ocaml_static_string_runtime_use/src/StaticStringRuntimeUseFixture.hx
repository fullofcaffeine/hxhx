import haxe.macro.Context;
import haxe.macro.Expr;
import reflaxe.ocaml.ast.OcamlBuilder;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.lowered.OcamlStaticStringPlan;
import reflaxe.ocaml.lowered.OcamlStaticStringPlan.OcamlStaticStringDecision;
import reflaxe.ocaml.lowered.OcamlStaticStringPlan.OcamlStaticStringPlanner;
import reflaxe.ocaml.lowered.OcamlStaticStringPlan.OcamlStaticStringSourceKind;
import reflaxe.ocaml.runtimegen.OcamlFinalRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementLedger;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

using StringTools;

/**
	Defines the static String conversions that require `HxString.toStdString`.

	The expected conversion kinds and helper name come from the authored Haxe
	cases. This fixture does not inspect the target builder or generated OCaml.
**/
@:access(reflaxe.ocaml.ast.OcamlBuilder)
class StaticStringRuntimeUseFixture {
	static final binding:OcamlFunctionPlanBinding = {
		functionId: "StaticStringRuntimeUseFixture.main",
		programRevision: "program:static-string",
		bodyRevision: "body:static-string",
		pipelineRevision: "pipeline:static-string"
	};

	public static macro function run():Expr {
		final typed = Context.typeExpr(macro {
			final nullable:Null<String> = null;
			final text:String = "text";
			final textAlias:StaticStringTextAlias = "alias";
			final nullableTextAlias:StaticStringNullableTextAlias = null;
			final value:Dynamic = text;
			final inferredNullable = if (value == null) text else null;
			Std.string(nullable);
			Std.string(textAlias);
			Std.string(nullableTextAlias);
			text + nullable;
			text + inferredNullable;
			var assigned:Null<String> = nullable;
			assigned += text;
			Reflect.field({name: 1}, text);
			Std.string(value);
			Std.string("literal");
			() -> Std.string(nullable);
		});

		final plan = new OcamlStaticStringPlanner(binding).plan(typed);
		final decisions = plan.decisions();
		assertKindCount(decisions, OcamlStaticStringSourceKind.StdString, 3);
		assertKindCount(decisions, OcamlStaticStringSourceKind.StringConcat, 4);
		assertKindCount(decisions, OcamlStaticStringSourceKind.StringCompoundLeft, 1);
		assertKindCount(decisions, OcamlStaticStringSourceKind.StringCompoundRight, 1);
		assertKindCount(decisions, OcamlStaticStringSourceKind.ReflectFieldName, 1);
		if (decisions.length != 10)
			throw 'Expected ten outer static String decisions, received ${decisions.length}.';

		for (decision in decisions)
			proveRuntimeUse(decision);

		// A lowering decision names one source conversion. Function assembly can
		// copy its checked OCaml expression into more than one final branch. This
		// fixture uses the builder's real output-role policy, so an omitted static
		// String role fails with the same duplicate-use error as a real target.
		final repeatedDecision = Lambda.find(decisions, decision -> decision.sourceKind == OcamlStaticStringSourceKind.StringConcat);
		if (repeatedDecision == null)
			throw "The repeated static-String fixture has no concatenation decision.";
		final repeatedOutput = new OcamlFinalRuntimeUseAuthority();
		repeatedOutput.beginProgram(binding.programRevision, "portable");
		final repeatedAuthority = new OcamlRuntimeUseAuthority(repeatedDecision.revision, "portable",
			OcamlRuntimeRequirementLedger.requirementsForStaticString(repeatedDecision), repeatedDecision.runtimeUseOccurrences, repeatedOutput);
		final repeatedOccurrence = repeatedDecision.runtimeUseOccurrences[0];
		final repeatedReference = OcamlExpr.ERuntimeIdent(repeatedAuthority.expressionIdentifier(repeatedOccurrence.id, repeatedOccurrence.planRevision,
			repeatedOccurrence.exactSymbol));
		repeatedAuthority.reconcileExpression(repeatedReference);
		final distinctOutput = repeatedOutput.distinctRepeatedRolesForOutput(OcamlExpr.ESeq([repeatedReference, repeatedReference]),
			OcamlBuilder.repeatedRuntimeUseOutputRoles(binding.functionId, false));
		repeatedOutput.observeExpression(distinctOutput);
		repeatedOutput.finishProgram();

		expectFailure("duplicate decision", "sealed more than once", () -> new OcamlStaticStringPlan([decisions[0], decisions[0]]));
		expectFailure("stale binding", "belongs to another function or target pipeline", () -> plan.requirePlanBinding({
			functionId: binding.functionId,
			programRevision: binding.programRevision,
			bodyRevision: binding.bodyRevision,
			pipelineRevision: binding.pipelineRevision + ":stale"
		}));
		expectFailure("changed source kind", "stale or conflicting runtime facts",
			() -> OcamlStaticStringPlan.requireDecision(copyDecision(decisions[0], OcamlStaticStringSourceKind.StringConcat)));
		expectFailure("non-canonical alias spelling", "incomplete or incompatible facts",
			() -> OcamlStaticStringPlan.requireDecision(copyDecision(decisions[0], decisions[0].sourceKind, null, "StaticStringTextAlias")));

		Sys.println("REFLAXE_OCAML_STATIC_STRING_RUNTIME_USE:PASS");
		return macro null;
	}

	static function proveRuntimeUse(decision:OcamlStaticStringDecision):Void {
		OcamlStaticStringPlan.requireDecision(decision);
		if (decision.semanticTypeId != "String" && decision.semanticTypeId != "Null<String>")
			throw 'Decision "${decision.id}" accepts an unexpected type ${decision.semanticTypeId}.';
		final requirements = OcamlRuntimeRequirementLedger.requirementsForStaticString(decision);
		if (requirements.length != 1
			|| requirements[0].semanticCapability != "haxe-static-string-conversion"
			|| requirements[0].rootModules.join(",") != "HxString")
			throw 'Decision "${decision.id}" has the wrong runtime requirement.';

		final occurrence = decision.runtimeUseOccurrences[0];
		if (occurrence.exactSymbol != "HxString.toStdString")
			throw 'Decision "${decision.id}" must own one HxString.toStdString use.';
		final authority = new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements, decision.runtimeUseOccurrences);
		final checked = OcamlExpr.ERuntimeIdent(authority.expressionIdentifier(occurrence.id, occurrence.planRevision, occurrence.exactSymbol));
		authority.reconcileExpression(OcamlExpr.EApp(checked, [OcamlExpr.EIdent("value")]));

		expectFailure("wrong symbol", "wrong target symbol",
			() -> new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements,
				decision.runtimeUseOccurrences).expressionIdentifier(occurrence.id, occurrence.planRevision, occurrence.exactSymbol + "_wrong"));
		expectFailure("missing helper", "missing runtime use",
			() -> new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements,
				decision.runtimeUseOccurrences).reconcileExpression(OcamlExpr.EIdent("value")));
		expectFailure("wrong profile", "not eligible for profile",
			() -> new OcamlRuntimeUseAuthority(decision.revision, "unsupported-profile", requirements,
				decision.runtimeUseOccurrences).expressionIdentifier(occurrence.id, occurrence.planRevision, occurrence.exactSymbol));
		expectFailure("plain private helper", "plain private runtime reference",
			() -> new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements,
				decision.runtimeUseOccurrences).reconcileExpression(OcamlExpr.EField(OcamlExpr.EIdent("HxString"), "toStdString")));
		expectFailure("duplicate helper", "incomplete or incompatible facts",
			() -> OcamlStaticStringPlan.requireDecision(copyDecision(decision, decision.sourceKind, decision.runtimeUseOccurrences.concat([occurrence]))));
		expectFailure("wrong owner", "stale or conflicting runtime facts",
			() -> OcamlStaticStringPlan.requireDecision(copyDecision(decision, decision.sourceKind,
				[copyOccurrence(occurrence, occurrence.ownerId + ":wrong")])));
		expectFailure("wrong domain", "stale or conflicting runtime facts",
			() -> OcamlStaticStringPlan.requireDecision(copyDecision(decision, decision.sourceKind, [
				copyOccurrence(occurrence, occurrence.ownerId, OcamlRuntimeUseDomain.TypeIdentifier)
			])));
	}

	static function copyDecision(source:OcamlStaticStringDecision, sourceKind:OcamlStaticStringSourceKind,
			?runtimeUseOccurrences:Array<OcamlRuntimeUseOccurrence>, ?semanticTypeId:String):OcamlStaticStringDecision {
		return {
			id: source.id,
			revision: source.revision,
			source: {file: source.source.file, min: source.source.min, max: source.source.max},
			ownerSource: {file: source.ownerSource.file, min: source.ownerSource.min, max: source.ownerSource.max},
			sourceKind: sourceKind,
			semanticTypeId: semanticTypeId ?? source.semanticTypeId,
			inputCarrierTypeId: source.inputCarrierTypeId,
			order: source.order,
			profileEligibility: source.profileEligibility.copy(),
			runtimeRequirementIds: source.runtimeRequirementIds.copy(),
			runtimeUseOccurrences: runtimeUseOccurrences == null ? source.runtimeUseOccurrences.copy() : runtimeUseOccurrences,
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

	static function assertKindCount(decisions:Array<OcamlStaticStringDecision>, kind:OcamlStaticStringSourceKind, expected:Int):Void {
		final actual = decisions.filter(decision -> decision.sourceKind == kind).length;
		if (actual != expected)
			throw 'Expected $expected ${(kind : String)} decision(s), received $actual.';
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
