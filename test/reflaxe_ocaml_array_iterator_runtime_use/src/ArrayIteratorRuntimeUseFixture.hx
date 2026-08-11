package;

import haxe.macro.Context;
import haxe.macro.Expr;
import reflaxe.ocaml.ast.OcamlConst;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.ast.OcamlTypeExpr;
import reflaxe.ocaml.lowered.OcamlArrayIteratorPlan.OcamlArrayIteratorDecision;
import reflaxe.ocaml.lowered.OcamlArrayIteratorPlan.OcamlArrayIteratorPlanner;
import reflaxe.ocaml.lowered.OcamlArrayIteratorPlan.OcamlArrayIteratorUseKind;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementLedger;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

using StringTools;

/**
	Checks the standard and structural Array iterator forms owned by this plan.

	The fixture types real Haxe expressions first. It then proves that the target
	uses the standard `ArrayIterator` result when possible. A structural boundary
	must carry the exact planned `HxIterator` expression or carrier type.
**/
class ArrayIteratorRuntimeUseFixture {
	static final binding:OcamlFunctionPlanBinding = {
		functionId: "ArrayIteratorRuntimeUseFixture.main",
		programRevision: "program:array-iterator-runtime-use",
		bodyRevision: "body:array-iterator-runtime-use",
		pipelineRevision: "pipeline:array-iterator-runtime-use"
	};

	public static macro function run():Expr {
		final typed = Context.typeExpr(macro {
			final direct = [1, 2].iterator();
			final values = [3, 4];
			final stored = values.iterator;
			final structural:Iterator<Int> = {
				hasNext: () -> false,
				next: () -> 0
			};
			final count = Lambda.count([5, 6]);
			final nested = () -> {
				final nestedValues = [9, 10];
				return nestedValues.iterator;
			};
			if (direct.hasNext())
				direct.next();
			stored();
			structural;
			count;
			nested;
		});
		final plan = new OcamlArrayIteratorPlanner(binding).plan(typed);
		final decisions = plan.decisions();
		// Haxe 4.3.7 replaces the direct call with `new ArrayIterator` before the
		// target sees it, so that source form needs no private `HxIterator` name.
		assertKindCount(decisions, OcamlArrayIteratorUseKind.DirectCall, 0);
		assertKindCount(decisions, OcamlArrayIteratorUseKind.BoundMethod, 1);
		assertKindCount(decisions, OcamlArrayIteratorUseKind.StructuralAdapter, 1);
		assertKindCount(decisions, OcamlArrayIteratorUseKind.StructuralCarrier, 1);
		if (decisions.length != 3)
			throw 'Expected three Array iterator decisions, received ${decisions.length}.';

		for (decision in decisions)
			proveRuntimeUse(decision);
		expectFailure("stale plan binding", "belongs to another function or target pipeline", () -> plan.requirePlanBinding({
			functionId: binding.functionId,
			programRevision: binding.programRevision,
			bodyRevision: binding.bodyRevision,
			pipelineRevision: binding.pipelineRevision + ":stale"
		}));

		Sys.println("REFLAXE_OCAML_ARRAY_ITERATOR_RUNTIME_USE:PASS");
		return macro null;
	}

	static function proveRuntimeUse(decision:OcamlArrayIteratorDecision):Void {
		final requirements = OcamlRuntimeRequirementLedger.requirementsForArrayIterator(decision);
		if (decision.runtimeUseOccurrences.length == 0) {
			if (decision.kind != OcamlArrayIteratorUseKind.DirectCall && decision.kind != OcamlArrayIteratorUseKind.BoundMethod)
				throw 'Only direct or stored standard Array iterators may omit a private runtime use.';
			if (requirements.length != 0 || decision.runtimeRequirementIds.length != 0)
				throw 'Standard generated ArrayIterator values must not select private HxIterator runtime authority.';
			return;
		}
		final occurrence = decision.runtimeUseOccurrences[0];
		final authority = new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements, decision.runtimeUseOccurrences);
		if (decision.kind == OcamlArrayIteratorUseKind.StructuralCarrier) {
			final reference = authority.typeIdentifier(occurrence.id, occurrence.planRevision, occurrence.exactSymbol);
			authority.reconcileType(OcamlTypeExpr.TRuntimeApp(reference, [OcamlTypeExpr.TIdent("int")]));
			expectFailure("plain iterator carrier", "plain private runtime reference HxIterator.t",
				() -> new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements,
					decision.runtimeUseOccurrences).reconcileType(OcamlTypeExpr.TApp("HxIterator.t", [OcamlTypeExpr.TIdent("int")])));
		} else {
			final reference = authority.expressionIdentifier(occurrence.id, occurrence.planRevision, occurrence.exactSymbol);
			authority.reconcileExpression(OcamlExpr.ERuntimeIdent(reference));
			expectFailure("plain iterator producer", "plain private runtime reference HxIterator.of_array",
				() -> new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements,
					decision.runtimeUseOccurrences).reconcileExpression(OcamlExpr.EField(OcamlExpr.EIdent("HxIterator"), "of_array")));
		}

		expectFailure("missing iterator use", "missing runtime use",
			() -> new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements,
				decision.runtimeUseOccurrences).reconcileExpression(OcamlExpr.EConst(OcamlConst.CUnit)));
		expectFailure("stale iterator use", "stale runtime use",
			() -> createForDomain(new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements, decision.runtimeUseOccurrences), occurrence,
				occurrence.planRevision + ":stale", occurrence.exactSymbol));
		expectFailure("wrong iterator symbol", "wrong target symbol",
			() -> createForDomain(new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements, decision.runtimeUseOccurrences), occurrence,
				occurrence.planRevision, occurrence.exactSymbol + "_wrong"));

		expectFailure("wrong iterator domain", "wrong target domain",
			() -> createForOppositeDomain(new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements, decision.runtimeUseOccurrences),
				occurrence));
		final metalOnly = copyOccurrence(occurrence, occurrence.domain, ["metal"]);
		expectFailure("wrong iterator profile", "not eligible for profile portable",
			() -> createForDomain(new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements, [metalOnly]), metalOnly, metalOnly.planRevision,
				metalOnly.exactSymbol));
	}

	static function createForDomain(authority:OcamlRuntimeUseAuthority, occurrence:OcamlRuntimeUseOccurrence, planRevision:String, exactSymbol:String):Void {
		if (occurrence.domain == OcamlRuntimeUseDomain.TypeIdentifier)
			authority.typeIdentifier(occurrence.id, planRevision, exactSymbol);
		else
			authority.expressionIdentifier(occurrence.id, planRevision, exactSymbol);
	}

	static function createForOppositeDomain(authority:OcamlRuntimeUseAuthority, occurrence:OcamlRuntimeUseOccurrence):Void {
		if (occurrence.domain == OcamlRuntimeUseDomain.TypeIdentifier)
			authority.expressionIdentifier(occurrence.id, occurrence.planRevision, occurrence.exactSymbol);
		else
			authority.typeIdentifier(occurrence.id, occurrence.planRevision, occurrence.exactSymbol);
	}

	static function copyOccurrence(source:OcamlRuntimeUseOccurrence, domain:OcamlRuntimeUseDomain, profiles:Array<String>):OcamlRuntimeUseOccurrence {
		return {
			id: source.id,
			planRevision: source.planRevision,
			ownerId: source.ownerId,
			requirementId: source.requirementId,
			domain: domain,
			exactSymbol: source.exactSymbol,
			role: source.role,
			order: source.order,
			source: {
				file: source.source.file,
				min: source.source.min,
				max: source.source.max
			},
			profileEligibility: profiles,
			cardinality: source.cardinality
		};
	}

	static function assertKindCount(decisions:Array<OcamlArrayIteratorDecision>, kind:OcamlArrayIteratorUseKind, expected:Int):Void {
		final actual = decisions.filter(decision -> decision.kind == kind).length;
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
			throw '$label should fail with "$marker", received ${message == null ? "no failure" : message}.';
	}
}
