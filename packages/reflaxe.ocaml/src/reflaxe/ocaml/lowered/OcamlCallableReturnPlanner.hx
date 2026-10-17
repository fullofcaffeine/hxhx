package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.macro.Type;
import haxe.macro.TypedExprTools;
import reflaxe.data.ClassFuncData;
import reflaxe.ocaml.lowered.OcamlCallPlan;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallPlanner;
import reflaxe.ocaml.lowered.OcamlCallableReturnContract;
import reflaxe.ocaml.lowered.OcamlCallableViewRepresentation;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion;

/**
	Seals real callback return occurrences against the published declaration.

	A lambda or scalar static method creates an identity at the producer. A
	parameter or a selected call result already owns an identity and preserves it.
	Source types alone cannot prove the latter: parameters must be actual argument
	variables and calls must resolve both an occurrence plan and a catalog entry.
	Local aliases must resolve to their final lexical storage and view layout.
	Each early return also needs a control payload joined to this occurrence.
**/
function plan(data:ClassFuncData, declaration:OcamlCallableDeclarationPlan, binding:OcamlFunctionPlanBinding, call:TypedExpr->Null<OcamlCallDecision>,
		catalog:Null<String->Null<OcamlCallableDeclarationPlan>>,
		?localSource:TypedExpr->Null<OcamlCallableExpressionPlanner.OcamlCallableExpressionProof>):Array<OcamlCallableReturnDecision> {
	final body = data.expr;
	final tfunc = data.tfunc;
	if (body == null
		|| tfunc == null
		|| declaration.result == null
		|| declaration.result.callableView == null
		|| declaration.programRevision != binding.programRevision
		|| declaration.pipelineRevision != binding.pipelineRevision)
		throw "reflaxe.ocaml [callback-return:missing-definition]: callback result requires its final typed function body";
	final signature = callableShape(data.field.type);
	if (signature == null)
		throw "reflaxe.ocaml [callback-return:missing-signature]: callback return lost its declared signature";
	final boundary:OcamlCallableReturnBoundary = {
		calleeId: declaration.calleeId,
		layout: describe(signature),
		programRevision: binding.programRevision,
		pipelineRevision: binding.pipelineRevision,
		functionId: binding.functionId,
		bodyRevision: binding.bodyRevision
	};
	final returns:Array<TypedExpr> = [];
	function visit(expression:TypedExpr):Void {
		switch (expression.expr) {
			case TFunction(_):
			case TReturn(value) if (value != null):
				returns.push(value);
			case _:
				TypedExprTools.iter(expression, visit);
		}
	}
	visit(body);
	// A typed body can throw or loop forever without producing a callback.
	// Its complete return inventory is empty, rather than missing.
	final decisions:Array<OcamlCallableReturnDecision> = [];
	for (ordinal in 0...returns.length) {
		final returned = returns[ordinal];
		final input:OcamlCallableReturnInput = switch (unwrap(returned).expr) {
			case TLocal(local):
				final index = tfunc.args.map(argument -> argument.v.id).indexOf(local.id);
				if (index >= 0
					&& index < declaration.arguments.length
					&& declaration.arguments[index].callableView != null) Parameter(index); else {
					final proof = localSource == null ? null : localSource(returned);
					if (proof == null)
						throw "reflaxe.ocaml [callback-return:unsealed-local]: returned callback has no final local representation";
					switch (proof.input) {
						case ExistingView(reference): LocalView(reference, proof.layout);
						case _: throw "reflaxe.ocaml [callback-return:unsealed-local]: returned local lost its lexical storage evidence";
					}
				}
			case TCall({expr: TField(_, FStatic(owner, field))}, _):
				final calleeId = OcamlCallPlanner.calleeId(owner.get(), field.get());
				final selected = call(returned);
				final target = catalog == null ? null : catalog(calleeId);
				final targetShape = callableShape(field.get().type);
				if (selected == null
					|| target == null
					|| targetShape == null
					|| selected.calleeId != calleeId
					|| target.result == null
					|| target.result.callableView == null
					|| selected.result == null
					|| !OcamlCallPlan.sameCallResult(selected.resultKind, selected.result, target.resultKind, target.result))
					throw "reflaxe.ocaml [callback-return:unsealed-call]: returned callback has no matching call occurrence and declaration";
				CallResult(selected.id, {
					calleeId: calleeId,
					layout: describe(targetShape),
					programRevision: target.programRevision,
					pipelineRevision: target.pipelineRevision
				});
			case _:
				final origin = OcamlCallableOrigin.classify(returned);
				final shape = callableShape(returned.t);
				if (origin == null || shape == null)
					throw "reflaxe.ocaml [callback-return:unsealed-producer]: returned callback has no selected origin";
				Producer(origin, describe(shape));
		};
		final selected = seal({
			binding: binding,
			boundary: boundary,
			ordinal: ordinal,
			source: OcamlLoweredOrigin.sourceSpan(returned.pos),
			input: input
		});
		if (!OcamlCallableDeclarationCarrier.same(operation(selected).outputLayout, declaration.result.callableView))
			throw "reflaxe.ocaml [callback-return:catalog-mismatch]: returned callback layout differs from its catalog entry";
		decisions.push(selected);
	}
	return decisions;
}

/** These wrappers do not change either the callback producer or its representation. */
private function unwrap(expression:TypedExpr):TypedExpr {
	return switch (expression.expr) {
		case TMeta(_, inner), TParenthesis(inner): unwrap(inner);
		case _: expression;
	};
}
#end
