package;

import haxe.macro.Context;
import haxe.macro.Expr;
import reflaxe.ocaml.ast.OcamlConst;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.lowered.OcamlReflectRuntimeUsePlan;
import reflaxe.ocaml.lowered.OcamlReflectRuntimeUsePlan.OcamlReflectRuntimeUseDecision;
import reflaxe.ocaml.lowered.OcamlReflectRuntimeUsePlan.OcamlReflectRuntimeUseKind;
import reflaxe.ocaml.lowered.OcamlReflectRuntimeUsePlan.OcamlReflectRuntimeUsePlanner;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementLedger;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

using StringTools;

/**
	Checks the private OCaml helpers selected by direct standard Reflect calls.

	The fixture types real Haxe calls before it inspects the plan. This keeps the
	test tied to resolved standard-library declarations instead of matching source
	text that happens to contain a method name.
**/
class ReflectRuntimeUseFixture {
	static final binding:OcamlFunctionPlanBinding = {
		functionId: "ReflectRuntimeUseFixture.main",
		programRevision: "program:reflect-runtime-use",
		bodyRevision: "body:reflect-runtime-use",
		pipelineRevision: "pipeline:reflect-runtime-use"
	};

	public static macro function run():Expr {
		final typed = Context.typeExpr(macro {
			final receiver:Dynamic = {value: 3};
			final method:Dynamic = function(value:Int):Int return value + 1;
			final enumValue:Dynamic = ReflectRuntimeUseEnum.Some;
			Reflect.callMethod(receiver, method, [2]);
			Reflect.isFunction(method);
			Reflect.makeVarArgs(function(arguments:Array<Dynamic>):Dynamic return arguments.length);
			Reflect.makeVarArgs(function(arguments:Array<Dynamic>):Void Sys.println(arguments.length));
			Reflect.isObject(receiver);
			Reflect.isEnumValue(enumValue);
			Reflect.compareMethods(method, method);
			final nested = () -> Reflect.isFunction(method);
			nested;
		});

		final plan = new OcamlReflectRuntimeUsePlanner(binding).plan(typed);
		final decisions = plan.decisions();
		assertKind(decisions, OcamlReflectRuntimeUseKind.CallMethod, 1, "HxReflect.callMethod");
		assertKind(decisions, OcamlReflectRuntimeUseKind.IsFunction, 1, "HxReflect.isFunction");
		assertKind(decisions, OcamlReflectRuntimeUseKind.MakeVarArgs, 1, "HxReflect.makeVarArgs");
		assertKind(decisions, OcamlReflectRuntimeUseKind.MakeVarArgsVoid, 1, "HxReflect.makeVarArgsVoid");
		assertKind(decisions, OcamlReflectRuntimeUseKind.IsObject, 1, "HxReflect.isObject");
		assertKind(decisions, OcamlReflectRuntimeUseKind.IsEnumValue, 1, "HxReflect.isEnumValue");
		assertKind(decisions, OcamlReflectRuntimeUseKind.CompareMethods, 1, "HxReflect.same_closure");
		if (decisions.length != 7)
			throw 'Expected seven outer-function Reflect decisions, received ${decisions.length}.';

		for (decision in decisions)
			proveRuntimeUse(decision);

		expectFailure("stale binding", "belongs to another function or target pipeline", () -> plan.requirePlanBinding({
			functionId: binding.functionId,
			programRevision: binding.programRevision,
			bodyRevision: binding.bodyRevision,
			pipelineRevision: binding.pipelineRevision + ":stale"
		}));

		Sys.println("REFLAXE_OCAML_REFLECT_RUNTIME_USE:PASS");
		return macro null;
	}

	static function proveRuntimeUse(decision:OcamlReflectRuntimeUseDecision):Void {
		final requirements = OcamlRuntimeRequirementLedger.requirementsForReflectRuntimeUse(decision);
		if (requirements.length != 1 || decision.runtimeUseOccurrences.length != 1)
			throw 'Reflect decision "${decision.id}" must own one requirement and one runtime use.';
		final occurrence = decision.runtimeUseOccurrences[0];
		final authority = new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements, decision.runtimeUseOccurrences);
		final reference = authority.expressionIdentifier(occurrence.id, occurrence.planRevision, occurrence.exactSymbol);
		authority.reconcileExpression(OcamlExpr.ERuntimeIdent(reference));

		expectFailure("plain helper", "plain private runtime reference",
			() -> new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements,
				decision.runtimeUseOccurrences).reconcileExpression(privateReference(occurrence.exactSymbol)));
		expectFailure("missing helper", "missing runtime use",
			() -> new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements,
				decision.runtimeUseOccurrences).reconcileExpression(OcamlExpr.EConst(OcamlConst.CUnit)));
		expectFailure("stale helper", "stale runtime use",
			() -> new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements,
				decision.runtimeUseOccurrences).expressionIdentifier(occurrence.id, occurrence.planRevision + ":stale", occurrence.exactSymbol));
		expectFailure("wrong symbol", "wrong target symbol",
			() -> new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements,
				decision.runtimeUseOccurrences).expressionIdentifier(occurrence.id, occurrence.planRevision, occurrence.exactSymbol + "_wrong"));
		expectFailure("duplicate helper", "constructed more than once", () -> {
			final duplicate = new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements, decision.runtimeUseOccurrences);
			duplicate.expressionIdentifier(occurrence.id, occurrence.planRevision, occurrence.exactSymbol);
			duplicate.expressionIdentifier(occurrence.id, occurrence.planRevision, occurrence.exactSymbol);
		});
		final wrongOwner = copyOccurrence(occurrence, occurrence.ownerId + ":wrong");
		expectFailure("wrong owner", "invalid-runtime-use", () -> OcamlReflectRuntimeUsePlan.requireDecision(copyDecision(decision, [wrongOwner])));
	}

	static function privateReference(symbol:String):OcamlExpr {
		final parts = symbol.split(".");
		return OcamlExpr.EField(OcamlExpr.EIdent(parts[0]), parts[1]);
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

	static function copyDecision(source:OcamlReflectRuntimeUseDecision, runtimeUseOccurrences:Array<OcamlRuntimeUseOccurrence>):OcamlReflectRuntimeUseDecision {
		return {
			id: source.id,
			revision: source.revision,
			source: {file: source.source.file, min: source.source.min, max: source.source.max},
			kind: source.kind,
			sourceMethod: source.sourceMethod,
			exactSymbol: source.exactSymbol,
			argumentSemanticTypeIds: source.argumentSemanticTypeIds.copy(),
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

	static function assertKind(decisions:Array<OcamlReflectRuntimeUseDecision>, kind:OcamlReflectRuntimeUseKind, expected:Int, symbol:String):Void {
		final selected = decisions.filter(decision -> decision.kind == kind);
		if (selected.length != expected || selected[0].exactSymbol != symbol)
			throw 'Expected $expected ${(kind : String)} decision for $symbol.';
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
