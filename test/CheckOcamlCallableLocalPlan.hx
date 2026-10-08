#if macro
import haxe.macro.Type;
import haxe.macro.TypedExprTools;
import reflaxe.lifecycle.FunctionBodyRevision;
import reflaxe.lifecycle.LexicalLocalIdentityPlan;
import reflaxe.ocaml.lowered.OcamlCallableViewLocalConversion;
import reflaxe.ocaml.lowered.OcamlCallableViewLocalConversion.OcamlCallableViewLocalDecision;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.OcamlGenericValueConversion;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan.OcamlLocalRepresentationReference;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan.OcamlLocalRepresentationDecision;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin;
import reflaxe.ocaml.lowered.OcamlRepresentationRegistry;
#end

/**
	Checks occurrence ownership before supplying the native component's adapter.

	The test explicitly selects existing views for its two locals. Production
	producer admission is still required before a compiler can make that choice.
**/
class CheckOcamlCallableLocalPlan {
	#if macro
	public static function select(body:TypedExpr, localName:String):OcamlGenericValueConversion {
		var selected:Null<{local:TVar, input:TVar, expression:TypedExpr}> = null;
		function visit(expression:TypedExpr):Void {
			switch (expression.expr) {
				case TVar(local, value) if (local.name == localName && value != null):
					switch (value.expr) {
						case TLocal(input): selected = {local: local, input: input, expression: value};
						case _: throw "callback plan fixture no longer assigns a local view";
					}
				case _:
			}
			TypedExprTools.iter(expression, visit);
		}
		visit(body);
		if (selected == null)
			throw "missing callback plan fixture assignment";
		final binding:OcamlFunctionPlanBinding = {
			functionId: "callback-fixture-main",
			programRevision: "callback-fixture-program",
			bodyRevision: FunctionBodyRevision.initial(body).id,
			pipelineRevision: "callback-fixture-pipeline"
		};
		final identities = LexicalLocalIdentityPlan.build(binding.functionId, body);
		final registry = new OcamlRepresentationRegistry();
		registry.beginProgram(binding.programRevision);
		function reference(local:TVar):OcamlLocalRepresentationReference {
			final shape = callableShape(local.t);
			if (shape == null)
				throw "fixture has no closed callback signature";
			final decision = registry.selectCallableView(shape, InternalValue);
			return {
				localId: identities.requireHostId(local.id).id,
				representationId: decision.id,
				representationRevision: decision.revision,
				semanticTypeId: decision.semanticTypeId,
				domain: decision.domain
			};
		}
		final input = reference(selected.input);
		final output = reference(selected.local);
		final source = OcamlLoweredOrigin.sourceSpan(selected.expression.pos);
		final conversion = seal(registry, binding, Initializer, source, input, output);
		final locals = [choice(input), choice(output)];
		final plan = new OcamlLocalRepresentationPlan(locals, [], [conversion]);
		plan.requirePlanBinding(binding);
		if (plan.revision == new OcamlLocalRepresentationPlan(locals).revision)
			throw "callback conversion did not change its owning local plan revision";
		final resolved = plan.callableViewConversionFor(binding, output.localId, Initializer, source, registry);
		if (resolved == null || plan.callableViewConversionCount != 1)
			throw "local plan lost its callback occurrence";
		requireRegistry(resolved, registry, binding);
		if (plan.callableViewConversionFor(binding, output.localId, Assignment, source, registry) != null
			|| plan.callableViewConversionFor(binding, input.localId, Initializer, source, registry) != null
			|| plan.callableViewConversionFor(binding, output.localId, Initializer, {
				file: source.file,
				min: source.min + 1,
				max: source.max + 1
			}, registry) != null)
			throw "another role, local or source acquired the callback conversion";
		expectRejected(() -> new OcamlLocalRepresentationPlan([choice(output)], [], [conversion]));
		expectRejected(() -> new OcamlLocalRepresentationPlan(locals, [], [conversion, conversion]));
		expectRejected(() -> seal(registry, binding, Read, source, input, output));
		for (changed in ["function", "program", "body", "pipeline"]) {
			final foreign:OcamlFunctionPlanBinding = {
				functionId: changed == "function" ? "other-function" : binding.functionId,
				programRevision: changed == "program" ? "other-program" : binding.programRevision,
				bodyRevision: changed == "body" ? "other-body" : binding.bodyRevision,
				pipelineRevision: changed == "pipeline" ? "other-pipeline" : binding.pipelineRevision
			};
			expectRejected(() -> plan.requirePlanBinding(foreign));
			expectRejected(() -> requireRegistry(resolved, registry, foreign));
		}
		// Both constructor input and returned copies contain mutable adapter arrays.
		// Neither may rewrite the decision retained by the function plan.
		corruptAdapter(conversion);
		corruptAdapter(resolved);
		expectRejected(() -> requireDecision(conversion));
		expectRejected(() -> requireDecision(resolved));
		final retained = plan.callableViewConversionFor(binding, output.localId, Initializer, source, registry);
		if (retained == null)
			throw "callback conversion disappeared after mutating a detached copy";
		requireRegistry(retained, registry, binding);
		registry.beginProgram("reset-program");
		expectRejected(() -> requireRegistry(retained, registry, binding));
		expectRejected(() -> plan.callableViewConversionFor(binding, output.localId, Initializer, source, registry));
		return retained.conversion;
	}

	static function choice(reference:OcamlLocalRepresentationReference):OcamlLocalRepresentationDecision {
		return {
			localId: reference.localId,
			choice: ProgramDecision(reference.representationId, reference.representationRevision, reference.semanticTypeId, reference.domain),
			initializerConversion: LegacyCoercion,
			assignmentConversion: LegacyCoercion,
			readConversion: Identity
		};
	}

	static function corruptAdapter(decision:OcamlCallableViewLocalDecision):Void {
		switch (decision.conversion) {
			case AdaptFunction(arguments, _):
				arguments[0] = Identity;
			case _:
				throw "fixture no longer exercises a real callback adapter";
		}
	}

	static function expectRejected(action:Void->Void):Void {
		try {
			action();
		} catch (error:haxe.Exception) {
			if (error.message.indexOf("reflaxe.ocaml [ocaml-") == 0)
				return;
			throw error;
		}
		throw "stale or foreign callback conversion was accepted";
	}
	#end
}
