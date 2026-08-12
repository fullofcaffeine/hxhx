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
			final fieldName = "value";
			final method:Dynamic = function(value:Int):Int return value + 1;
			final enumValue:Dynamic = ReflectRuntimeUseEnum.Some;
			Reflect.field(receiver, fieldName);
			Reflect.getProperty(receiver, fieldName);
			Reflect.setField(receiver, fieldName, 4);
			Reflect.hasField(receiver, fieldName);
			Reflect.fields(receiver);
			Reflect.deleteField(receiver, fieldName);
			Reflect.copy(receiver);
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
		assertKind(decisions, OcamlReflectRuntimeUseKind.Field, 1, "HxAnon.get");
		assertKind(decisions, OcamlReflectRuntimeUseKind.GetProperty, 1, "HxAnon.get");
		assertKind(decisions, OcamlReflectRuntimeUseKind.SetField, 1, "HxAnon.set");
		assertKind(decisions, OcamlReflectRuntimeUseKind.HasField, 1, "HxAnon.has");
		assertKind(decisions, OcamlReflectRuntimeUseKind.Fields, 1, "HxAnon.fields");
		assertKind(decisions, OcamlReflectRuntimeUseKind.DeleteField, 1, "HxAnon.delete");
		assertKind(decisions, OcamlReflectRuntimeUseKind.Copy, 1, "HxAnon.copy");
		assertKind(decisions, OcamlReflectRuntimeUseKind.CallMethod, 1, "HxReflect.callMethod");
		assertKind(decisions, OcamlReflectRuntimeUseKind.IsFunction, 1, "HxReflect.isFunction");
		assertKind(decisions, OcamlReflectRuntimeUseKind.MakeVarArgs, 1, "HxReflect.makeVarArgs");
		assertKind(decisions, OcamlReflectRuntimeUseKind.MakeVarArgsVoid, 1, "HxReflect.makeVarArgsVoid");
		assertKind(decisions, OcamlReflectRuntimeUseKind.IsObject, 1, "HxReflect.isObject");
		assertKind(decisions, OcamlReflectRuntimeUseKind.IsEnumValue, 1, "HxReflect.isEnumValue");
		assertKind(decisions, OcamlReflectRuntimeUseKind.CompareMethods, 1, "HxReflect.same_closure");
		if (decisions.length != 14)
			throw 'Expected fourteen outer-function Reflect decisions, received ${decisions.length}.';

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
		if (decision.evaluationPolicy != OcamlReflectRuntimeUsePlan.EVALUATION_POLICY)
			throw 'Reflect decision "${decision.id}" has the wrong argument evaluation policy.';
		if (requirements[0].rootModules.join(",") != OcamlReflectRuntimeUsePlan.rootModuleFor(decision.kind))
			throw 'Reflect decision "${decision.id}" has the wrong runtime module.';
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
		final wrongOrder = copyOccurrence(occurrence, occurrence.ownerId, occurrence.order + 1);
		expectFailure("wrong order", "invalid-runtime-use", () -> OcamlReflectRuntimeUsePlan.requireDecision(copyDecision(decision, [wrongOrder])));
		expectFailure("wrong method", "invalid-runtime-use",
			() -> OcamlReflectRuntimeUsePlan.requireDecision(copyDecision(decision, decision.runtimeUseOccurrences, decision.sourceMethod + "Wrong")));
		expectFailure("wrong evaluation policy", "invalid-plan",
			() -> OcamlReflectRuntimeUsePlan.requireDecision(copyDecision(decision, decision.runtimeUseOccurrences, decision.sourceMethod, "unordered")));
		expectFailure("wrong profile", "not eligible for profile",
			() -> new OcamlRuntimeUseAuthority(decision.revision, "unsupported-profile", requirements,
				decision.runtimeUseOccurrences).expressionIdentifier(occurrence.id, occurrence.planRevision, occurrence.exactSymbol));
	}

	static function privateReference(symbol:String):OcamlExpr {
		final parts = symbol.split(".");
		return OcamlExpr.EField(OcamlExpr.EIdent(parts[0]), parts[1]);
	}

	static function copyOccurrence(source:OcamlRuntimeUseOccurrence, ownerId:String, ?order:Int):OcamlRuntimeUseOccurrence {
		return {
			id: source.id,
			planRevision: source.planRevision,
			ownerId: ownerId,
			requirementId: source.requirementId,
			domain: source.domain,
			exactSymbol: source.exactSymbol,
			role: source.role,
			order: order ?? source.order,
			source: {
				file: source.source.file,
				min: source.source.min,
				max: source.source.max
			},
			profileEligibility: source.profileEligibility.copy(),
			cardinality: source.cardinality
		};
	}

	static function copyDecision(source:OcamlReflectRuntimeUseDecision, runtimeUseOccurrences:Array<OcamlRuntimeUseOccurrence>, ?sourceMethod:String,
			?evaluationPolicy:String):OcamlReflectRuntimeUseDecision {
		return {
			id: source.id,
			revision: source.revision,
			source: {file: source.source.file, min: source.source.min, max: source.source.max},
			kind: source.kind,
			sourceMethod: sourceMethod ?? source.sourceMethod,
			exactSymbol: source.exactSymbol,
			argumentSemanticTypeIds: source.argumentSemanticTypeIds.copy(),
			resultSemanticTypeId: source.resultSemanticTypeId,
			evaluationPolicy: evaluationPolicy ?? source.evaluationPolicy,
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
