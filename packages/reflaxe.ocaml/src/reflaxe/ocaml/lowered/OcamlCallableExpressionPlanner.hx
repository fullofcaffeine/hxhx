package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.macro.Type;
import haxe.macro.TypedExprTools;
import reflaxe.lifecycle.LexicalLocalIdentityPlan;
import reflaxe.ocaml.lowered.OcamlCallPlan;
import reflaxe.ocaml.lowered.OcamlCallableViewContract;
import reflaxe.ocaml.lowered.OcamlCallableViewContract.OcamlCallableViewInput;
import reflaxe.ocaml.lowered.OcamlCallableViewRepresentation;
import reflaxe.ocaml.lowered.OcamlCallableViewRepresentation.OcamlCallableViewDescriptor;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion;
import reflaxe.ocaml.lowered.OcamlCallableComparison.OcamlCallableComparisonDecision;

/** One actual source producer joined to local, call, or published declaration evidence. */
typedef OcamlCallableExpressionProof = {
	final input:OcamlCallableViewInput;
	final layout:OcamlCallableViewDescriptor;
};

/**
	Resolves callback values after local storage choices exist.

	A function type describes an invocation shape but does not prove a native view.
	This planner joins each value to its actual local representation, selected call
	result, or raw producer. The syntax builder consumes these prepared facts and
	does not reconstruct a calling convention from source types.
**/
class OcamlCallableExpressionPlanner {
	final representations:OcamlRepresentationRegistry;
	final binding:OcamlFunctionPlanBinding;
	final locals:Null<OcamlLocalRepresentationPlan>;
	final identities:Null<LexicalLocalIdentityPlan>;
	final declaration:(ClassType, ClassField) -> Null<OcamlCallableDeclarationPlan>;
	final call:TypedExpr->Null<OcamlCallDecision>;

	public function new(representations:OcamlRepresentationRegistry, binding:OcamlFunctionPlanBinding, locals:Null<OcamlLocalRepresentationPlan>,
			identities:Null<LexicalLocalIdentityPlan>, declaration:(ClassType, ClassField) -> Null<OcamlCallableDeclarationPlan>,
			call:TypedExpr->Null<OcamlCallDecision>) {
		this.representations = representations;
		this.binding = binding;
		this.locals = locals;
		this.identities = identities;
		this.declaration = declaration;
		this.call = call;
	}

	/** Return only a proof for the exact source value; unknown producers remain unadmitted. */
	public function source(expression:TypedExpr):Null<OcamlCallableExpressionProof> {
		final current = unwrap(expression);
		return switch (current.expr) {
			case TLocal(local):
				final reference = locals == null || identities == null ? null : locals.referenceFor(identities.requireHostId(local.id).id);
				if (reference == null) null; else {
					final representation = representations.require(reference.representationId, binding.programRevision);
					if (representation.boxingPolicy != CallableIdentityView)
						null;
					else
						{
							input: ExistingView(reference),
							layout: representations.requireCallableView(reference.representationId, reference.representationRevision, binding.programRevision)
						};
				}
			case TCall(_, _): final selected = call(current); selected == null || selected.result == null || selected.result.callableView == null ? null : {
					input: CallResult(selected.source),
					layout: describe(selected.result.callableView.shape)
				};
			case _:
				final shape = callableShape(current.t);
				final origin = OcamlCallableOrigin.classify(current);
				if (shape == null || origin == null) null; else if (OcamlCallableValueOperation.isScalarArrow(shape)) {
					input: RawOrigin(origin),
					layout: describe(shape)
				}; else switch (current.expr) {
					case TField(_, FStatic(owner, field)):
						final selected = declaration(owner.get(), field.get());
						if (selected == null || selected.proofId != OcamlCallableDeclarationCarrier.SIGNATURE_PROOF) null; else {
							final layout = describe(shape);
							OcamlCallableDeclarationCarrier.requireSignature(layout, selected.arguments, selected.result);
							{
								input: DeclaredOrigin({
									calleeId: selected.calleeId,
									layout: layout,
									programRevision: selected.programRevision,
									pipelineRevision: selected.pipelineRevision
								}),
								layout: layout
							};
						}
					case _: null;
				}
		};
	}

	/** Prepare a callback once before the call reads its ordinary argument slot. */
	public function argument(callId:String, expression:TypedExpr, boundary:OcamlCallValuePlan, index:Int):Null<OcamlCallValuePlan> {
		final proof = source(expression);
		final output = boundary.callableView;
		if (proof == null || output == null)
			return null;
		final conversion = crossing(proof.layout.shape, output.shape);
		if (conversion == null)
			return null;
		final prepared:OcamlCallableArgumentPlan = {
			input: copyInput(proof.input),
			operation: {
				id: callId + ":callback-argument:" + index,
				role: ArgumentValue,
				source: OcamlLoweredOrigin.sourceSpan(expression.pos),
				binding: binding,
				origin: switch (proof.input) {
					case RawOrigin(kind): kind;
					case DeclaredOrigin(declaration): StaticDeclaration(declaration.calleeId);
					case _: null;
				},
				inputLayout: proof.layout,
				outputLayout: output,
				conversion: conversion,
				invocation: switch (proof.input) {
					case DeclaredOrigin(declaration): declaration;
					case _: null;
				}
			}
		};
		OcamlCallableArgumentPlan.requireArgument(prepared);
		return OcamlCallPlan.copyValueWithCallbackArgument(boundary, prepared);
	}

	/** Only existing views expose a projected invocation; raw arrows still need an origin step. */
	public function invocation(expression:TypedExpr):Null<OcamlCallableInvocationContract.OcamlCallableInvocationPlan> {
		final proof = source(expression);
		if (proof == null)
			return null;
		return switch (proof.input) {
			case ExistingView(_), CallResult(_):
				OcamlCallableInvocationContract.copy({input: proof.input, layout: proof.layout, source: OcamlLoweredOrigin.sourceSpan(unwrap(expression).pos)});
			case _: null;
		};
	}

	/**
		Plan equality after final calls exist, using the same producer evidence as arguments.

		Raw arrows keep ordinary equality unless the other operand already carries a
		callback view. Nested bodies have their own binding and are not part of this
		function's inventory. A selected view cannot fall back to tuple comparison.
	**/
	public function comparisons(expression:TypedExpr):Array<OcamlCallableComparisonDecision> {
		final result:Array<OcamlCallableComparisonDecision> = [];
		function carriesView(proof:Null<OcamlCallableExpressionProof>):Bool {
			return proof != null && switch (proof.input) {
				case ExistingView(_), CallResult(_): true;
				case _: false;
			};
		}
		function visit(current:TypedExpr):Void {
			switch (current.expr) {
				case TFunction(_):
					return;
				case TBinop(op = (OpEq | OpNotEq), left, right):
					final leftProof = source(left);
					final rightProof = source(right);
					if (carriesView(leftProof) || carriesView(rightProof)) {
						if (leftProof == null || rightProof == null)
							throw "reflaxe.ocaml [callback-comparison:unplanned-operand]: selected callback equality lost its producer evidence";
						result.push(OcamlCallableComparison.seal(binding, OcamlLoweredOrigin.sourceSpan(current.pos), op == OpNotEq,
							{source: OcamlLoweredOrigin.sourceSpan(unwrap(left).pos), input: leftProof.input, layout: leftProof.layout},
							{source: OcamlLoweredOrigin.sourceSpan(unwrap(right).pos), input: rightProof.input, layout: rightProof.layout}));
					}
				case _:
			}
			TypedExprTools.iter(current, visit);
		}
		visit(expression);
		return result;
	}

	static function unwrap(expression:TypedExpr):TypedExpr {
		return switch (expression.expr) {
			case TMeta(_, inner), TParenthesis(inner): unwrap(inner);
			case _: expression;
		};
	}
}
#end
