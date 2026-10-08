import reflaxe.ocaml.lowered.OcamlGenericInstanceCallContract.decision as genericCallDecision;
import reflaxe.ocaml.lowered.OcamlGenericInstanceCallContract.fingerprint as genericCallFingerprint;
import reflaxe.ocaml.lowered.OcamlGenericInstanceCallContract.select as genericCallSelect;
import reflaxe.ocaml.lowered.OcamlGenericInstanceCallContract.require as genericCallRequire;
import haxe.macro.Context;
import haxe.macro.Type;
import haxe.macro.TypedExprTools;
import reflaxe.ocaml.CompilationContext;
import reflaxe.ocaml.lowered.OcamlCallPlan;
import reflaxe.ocaml.lowered.OcamlCallRuntimeUseModel.OcamlCallRuntimeUseContract;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.OcamlGenericValueConversion;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.OcamlGenericValueShape;
import reflaxe.ocaml.lowered.OcamlMonomorphicClassPlanner;
import reflaxe.ocaml.lowered.OcamlRepresentationRegistry;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.reports.OcamlGenericCallReport.targetToReport;
import reflaxe.ocaml.reports.OcamlGenericCallReport.targetFromReport;
import reflaxe.ocaml.reports.OcamlGenericCallReport.callToReport;
import reflaxe.ocaml.reports.OcamlReportJson.encode;

/** Exercises exact typed-call matching and rejects corrupt conversion/runtime decisions. */
class CheckGenericCallPlans {
	public static function install():Void {
		Context.onAfterTyping(types -> {
			final registry = new OcamlRepresentationRegistry();
			registry.beginProgram("generic-call-plan-test");
			final context = new CompilationContext();
			context.virtualTypesComputed = true;
			final scope = switch (Context.getType("Scope")) {
				case TInst(reference, _): reference.get();
				case _: throw "missing Scope";
			};
			OcamlMonomorphicClassPlanner.plan([scope.module], [scope.module => [scope]], context, registry, _ -> true);
			var checked = 0;
			for (type in types)
				switch (type) {
					case TClassDecl(reference) if (reference.get().name == "First"):
						for (field in reference.get().statics.get()) {
							final expression = field.expr();
							if (expression == null)
								continue;
							function visit(current:TypedExpr):Void {
								switch (current.expr) {
									case TCall({expr: TField(_, FInstance(_, _, method))}, _) if (method.get().params.length > 0):
										check(current, registry);
										checked++;
									case _:
								}
								TypedExprTools.iter(current, visit);
							}
							visit(expression);
						}
					case _:
				}
			if (checked != 14)
				throw 'expected 14 sealed generic call checks, got $checked';
			Sys.println("GENERIC_CALL_SEAL_AND_RUNTIME_NEGATIVES:PASS");
		});
	}

	static function check(expression:TypedExpr, registry:OcamlRepresentationRegistry):Void {
		final target = genericCallSelect(expression, registry);
		if (target == null)
			throw "actual generic call lost its registered receiver or conversion target";
		// Ordinary callback support must not authorize a new generic method ABI.
		expectRejected(() -> genericCallRequire({
			moduleId: target.moduleId,
			typeName: target.typeName,
			fieldName: target.fieldName,
			receiverTypeId: target.receiverTypeId,
			receiverRepresentationId: target.receiverRepresentationId,
			ownedParameterIds: target.ownedParameterIds.copy(),
			declaration: FunctionValue([], DynamicValue),
			instantiation: FunctionValue([], DynamicValue),
			argumentShapes: [],
			arguments: [],
			resultShape: DynamicValue,
			result: Identity
		}), "ordinary Dynamic acquired a generic declaration proof");
		final binding:OcamlFunctionPlanBinding = {
			functionId: "First|contract",
			programRevision: "generic-call-plan-test",
			bodyRevision: "body:current",
			pipelineRevision: "pipeline:test"
		};
		final decision = genericCallDecision(expression, target, binding);
		OcamlCallPlan.requireCall(decision);
		if (target.resultShape == NullableBoolean && !OcamlCallPlan.decisionProducesNullableBool(decision))
			throw "generic nullable Boolean result lost its carrier classification";
		if (Type.enumEq(target.resultShape, Text(false)) && !OcamlCallPlan.decisionProducesExactString(decision))
			throw "generic String result lost its carrier classification";
		final encoded = encode(targetToReport(target));
		final decoded = targetFromReport(haxe.Json.parse(encoded));
		if (genericCallFingerprint(decoded) != genericCallFingerprint(target) || encode(targetToReport(decoded)) != encoded)
			throw "generic report changed the typed target or canonical bytes";
		encode(callToReport(decision));
		// This test deliberately corrupts parsed JSON at the same boundary as an external report.
		final unknownField:Dynamic = haxe.Json.parse(encoded);
		Reflect.setField(unknownField, "uncheckedConversion", true);
		expectRejected(() -> {
			targetFromReport(unknownField);
		}, "unexpected report field");
		final wrongConversion:Dynamic = haxe.Json.parse(encoded);
		Reflect.setField(wrongConversion, "result", {
			kind: target.result == Identity ? "box-value" : "identity",
			parameter: null,
			children: []
		});
		expectRejected(() -> {
			targetFromReport(wrongConversion);
		}, "changed reported result conversion");
		final inventory = new OcamlCallPlan([decision]);
		if (inventory.decisionFor(expression) == null)
			throw "exact typed call did not resolve";
		if (new OcamlCallPlan([]).decisionFor(expression) != null)
			throw "missing decision was inferred";
		final wrongResult:TypedExpr = {expr: expression.expr, pos: expression.pos, t: Context.getType("Float")};
		if (inventory.decisionFor(wrongResult) != null)
			throw "foreign result shape matched a stored call";
		final changed = genericCallDecision(expression, target, binding);
		changed.genericInstanceTarget.ownedParameterIds[0] = "different-method|T";
		expectRejected(() -> OcamlCallPlan.requireCall(changed), "changed method ownership");
		if (inventory.decisionFor(expression) == null)
			throw "detached decision mutation changed the inventory";
		final reordered = genericCallDecision(expression, target, binding);
		reordered.evaluationSchedule.reverse();
		expectRejected(() -> OcamlCallPlan.requireCall(reordered), "changed evaluation order");
		final conflicting = genericCallDecision(expression, target, {
			functionId: binding.functionId,
			programRevision: binding.programRevision,
			bodyRevision: "body:stale",
			pipelineRevision: binding.pipelineRevision
		});
		expectRejected(() -> {
			new OcamlCallPlan([decision, conflicting]);
		}, "conflicting source occurrence");
		final runtime = inventory.runtimeUsePlanFor(decision.id);
		if (runtime != null) {
			OcamlCallRuntimeUseContract.requireForCall(decision, runtime);
			final missing = OcamlCallRuntimeUseContract.copy(runtime);
			missing.runtimeUseOccurrences.pop();
			expectRejected(() -> OcamlCallRuntimeUseContract.requireForCall(decision, missing), "missing Bool runtime occurrence");
			final foreign = OcamlCallRuntimeUseContract.copy(runtime);
			foreign.runtimeRequirementIds[0] = "foreign-runtime-owner";
			expectRejected(() -> OcamlCallRuntimeUseContract.requireForCall(decision, foreign), "foreign runtime owner");
		}
	}

	static function expectRejected(action:() -> Void, label:String):Void {
		var rejected = false;
		try
			action()
		catch (error:Dynamic) {
			// Compiler validation reports errors as thrown values; narrow immediately to the diagnostic prefix.
			final message = Std.string(error);
			rejected = message.indexOf("reflaxe.ocaml [ocaml-") == 0 || message.indexOf("Generic call report ") == 0;
		}
		if (!rejected)
			throw 'generic call accepted $label';
	}
}
