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
	/** The first stored view owns an actual source producer, not an invented input local. */
	public static function selectOrigin(body:TypedExpr, localName:String):{
		kind:reflaxe.ocaml.lowered.OcamlCallableOriginKind,
		conversion:OcamlGenericValueConversion
	} {
		var selected:Null<{local:TVar, expression:TypedExpr}> = null;
		function visit(expression:TypedExpr):Void {
			switch (expression.expr) {
				case TVar(local, value) if (local.name == localName && value != null):
					selected = {local: local, expression: value};
				case _:
			}
			TypedExprTools.iter(expression, visit);
		}
		visit(body);
		if (selected == null)
			throw "missing callback producer fixture";
		final binding:OcamlFunctionPlanBinding = {
			functionId: "callback-fixture-main",
			programRevision: "callback-fixture-program",
			bodyRevision: FunctionBodyRevision.initial(body).id,
			pipelineRevision: "callback-fixture-pipeline"
		};
		final identities = LexicalLocalIdentityPlan.build(binding.functionId, body);
		final registry = new OcamlRepresentationRegistry();
		registry.beginProgram(binding.programRevision);
		final shape = callableShape(selected.local.t);
		if (shape == null)
			throw "missing callback producer signature";
		final representation = registry.selectCallableView(shape, InternalValue);
		final output:OcamlLocalRepresentationReference = {
			localId: identities.requireHostId(selected.local.id).id,
			representationId: representation.id,
			representationRevision: representation.revision,
			semanticTypeId: representation.semanticTypeId,
			domain: representation.domain
		};
		final producer = sealProducer(registry, binding, Initializer, selected.expression, output);
		final source = OcamlLoweredOrigin.sourceSpan(selected.expression.pos);
		final plan = new OcamlLocalRepresentationPlan([choice(output)], [], [producer]);
		plan.requirePlanBinding(binding);
		final retained = plan.callableViewConversionFor(binding, output.localId, Initializer, source, registry);
		if (retained == null || plan.callableViewConversionCount != 1 || localReferences(retained).length != 1)
			throw "callback producer lost its single destination storage reference";
		// Report decoding must preserve the adapter selected from this actual typed producer.
		final report = reflaxe.ocaml.reports.OcamlCallableViewReport.adapterToReport(retained.inputLayout, retained.outputLayout, retained.conversion);
		final restored = reflaxe.ocaml.reports.OcamlCallableViewReport.adapterFromReport(haxe.Json.parse(reflaxe.ocaml.reports.OcamlReportJson.encode(report)));
		if (restored.input.revision != retained.inputLayout.revision
			|| restored.output.revision != retained.outputLayout.revision
			|| Std.string(restored.conversion) != Std.string(retained.conversion))
			throw "callback producer report changed its selected adapter";
		CheckOcamlCallableViewReports.verify();
		final expected = localName == "direct" ? "AdaptFunction([BoxValue],Identity)" : "Identity";
		if (Std.string(retained.conversion) != expected)
			throw "callback producer has the wrong selected conversion";
		expectRejected(() -> sealProducer(registry, binding, Read, selected.expression, output));
		expectRejected(() -> new OcamlLocalRepresentationPlan([], [], [producer]));
		expectRejected(() -> new OcamlLocalRepresentationPlan([choice(output)], [], [producer, producer]));
		if (plan.callableViewConversionFor(binding, output.localId, Assignment, source, registry) != null)
			throw "producer initializer was reused as an assignment";
		// Other callbacks have compatible-looking types but no raw-origin proof.
		function rejectReads(expression:TypedExpr):Void {
			switch (expression.expr) {
				case TVar(local, value) if (value != null && ["first", "returned", "higherSource", "firstLiteral"].contains(local.name)):
					expectRejected(() -> sealProducer(registry, binding, Initializer, value, output));
				case _:
			}
			TypedExprTools.iter(expression, rejectReads);
		}
		rejectReads(body);
		registry.beginProgram("reset-program");
		expectRejected(() -> plan.callableViewConversionFor(binding, output.localId, Initializer, source, registry));
		return switch (retained.input) {
			case RawOrigin(kind): {kind: kind, conversion: retained.conversion};
			case _: throw "raw callback producer became an existing view";
		};
	}

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
