package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.macro.Type;
import haxe.macro.TypedExprTools;
import reflaxe.lifecycle.LexicalLocalIdentityPlan;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan.OcamlLocalRepresentationDecision;
import reflaxe.ocaml.lowered.OcamlLocalConversionModel.OcamlLocalRepresentationReference;
import reflaxe.ocaml.lowered.OcamlCallableViewLocalConversion;
import reflaxe.ocaml.lowered.OcamlCallableViewContract;
import reflaxe.ocaml.lowered.OcamlCallableViewContract.OcamlCallableViewLocalDecision;
import reflaxe.ocaml.lowered.OcamlCallPlan;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallPlanner;

/** Actual function parameters and the published declarations available to this final body. */
typedef OcamlCallableLocalContext = {
	final parameters:Array<TVar>;
	final boundary:Null<OcamlCallableBoundaryPlan>;
	final declaration:String->Null<OcamlCallableDeclarationPlan>;
};

/**
	Selects callback storage only for a complete, closed set of local uses.

	An immutable callback can originate in a literal, a static method, a declared
	parameter, a selected call result, or another selected local. Every read must
	have a supported invocation, alias, comparison, argument or return owner.
	Rejecting one use rejects the whole connected set. If a published declaration
	already requires a view, an unsupported use fails before syntax instead of
	sending that view to a consumer that expects an ordinary function.
**/
function plan(expression:TypedExpr, identities:LexicalLocalIdentityPlan, storage:OcamlLocalStoragePlan, registry:OcamlRepresentationRegistry,
		binding:OcamlFunctionPlanBinding, ?context:OcamlCallableLocalContext):{
	locals:Array<OcamlLocalRepresentationDecision>,
	writes:Array<OcamlCallableViewLocalDecision>
} {
	final locals:Map<Int, TVar> = [];
	final initializers:Map<Int, TypedExpr> = [];
	final shapes:Map<Int, OcamlGenericValueShape> = [];
	final rejected:Map<Int, Bool> = [];
	final edges:Map<Int, Array<Int>> = [];
	final parameters:Map<Int, Bool> = [];
	final required:Map<Int, Bool> = [];
	function scalar(shape:OcamlGenericValueShape):Bool {
		return switch (shape) {
			case Integer, Boolean, Text(_), NullableInteger, NullableBoolean, DynamicValue: true;
			case _: false;
		};
	}
	function supported(shape:OcamlGenericValueShape):Bool {
		return scalar(shape) || switch (shape) {
			case FunctionValue(arguments, result): Lambda.foreach(arguments, supported) && (result == EffectOnly || supported(result));
			case _: false;
		};
	}
	if (context != null && context.boundary != null) {
		for (index in 0...context.parameters.length) {
			if (index >= context.boundary.arguments.length || context.boundary.arguments[index].callableView == null)
				continue;
			final parameter = context.parameters[index];
			final layout = context.boundary.arguments[index].callableView;
			locals.set(parameter.id, parameter);
			shapes.set(parameter.id, layout.shape);
			edges.set(parameter.id, []);
			parameters.set(parameter.id, true);
			required.set(parameter.id, true);
			if (storage.decisionFor(identities.requireHostId(parameter.id).id) != null)
				rejected.set(parameter.id, true);
		}
	}
	function collect(current:TypedExpr):Void {
		switch (current.expr) {
			case TFunction(_):
				return;
			case TVar(local, value):
				final shape = callableShape(local.t);
				final admitted = shape != null && switch (shape) {
					case FunctionValue(_, _): supported(shape);
					case _: false;
				};
				if (admitted && shape != null) {
					locals.set(local.id, local);
					shapes.set(local.id, shape);
					edges.set(local.id, []);
					if (value == null || storage.decisionFor(identities.requireHostId(local.id).id) != null)
						rejected.set(local.id, true);
					if (value != null)
						initializers.set(local.id, value);
				}
			case _:
		}
		TypedExprTools.iter(current, collect);
	}
	collect(expression);
	function unwrap(current:TypedExpr):TypedExpr {
		return switch (current.expr) {
			case TParenthesis(inner), TMeta(_, inner): unwrap(inner);
			case _: current;
		};
	}
	function candidate(current:TypedExpr):Null<Int> {
		return switch (unwrap(current).expr) {
			case TLocal(local) if (locals.exists(local.id)): local.id;
			case _: null;
		};
	}
	function connect(left:Int, right:Int):Void {
		final leftEdges = edges.get(left);
		final rightEdges = edges.get(right);
		if (leftEdges == null || rightEdges == null)
			throw "reflaxe.ocaml [ocaml-callable-local:missing-candidate]: callback graph lost a declared local";
		if (!leftEdges.contains(right))
			leftEdges.push(right);
		if (!rightEdges.contains(left))
			rightEdges.push(left);
	}
	function rejectReads(current:TypedExpr):Void {
		switch (current.expr) {
			case TLocal(local) if (locals.exists(local.id)):
				rejected.set(local.id, true);
			case _:
		}
		TypedExprTools.iter(current, rejectReads);
	}
	function declaration(current:TypedExpr):Null<OcamlCallableDeclarationPlan> {
		if (context == null)
			return null;
		return switch (unwrap(current).expr) {
			case TField(_, FStatic(owner, field)):
				final selected = context.declaration(OcamlCallPlanner.calleeId(owner.get(), field.get()));
				final shape = callableShape(current.t);
				if (selected != null && selected.proofId == OcamlCallableDeclarationCarrier.SIGNATURE_PROOF && shape != null) {
					OcamlCallPlan.requireCallableDeclarationPlan(selected);
					OcamlCallableDeclarationCarrier.requireSignature(OcamlCallableViewRepresentation.describe(shape), selected.arguments, selected.result);
					selected;
				} else null;
			case _: null;
		};
	}
	function invocation(current:TypedExpr):Null<OcamlGenericValueShape> {
		final local = candidate(current);
		return local != null ? shapes.get(local) : declaration(current) == null ? null : callableShape(current.t);
	}
	var visit:TypedExpr->Void = null;
	var acceptValue:(TypedExpr, OcamlGenericValueShape, Null<Int>) -> Bool = null;
	function acceptCall(callee:TypedExpr, arguments:Array<TypedExpr>, root:Null<Int>):Bool {
		final signature = invocation(callee);
		if (signature == null)
			return false;
		final local = candidate(callee);
		if (local != null && root != null)
			connect(root, local);
		return switch (signature) {
			case FunctionValue(expected, _) if (expected.length == arguments.length):
				var accepted = true;
				for (index in 0...arguments.length) {
					switch (expected[index]) {
						case FunctionValue(_, _):
							if (!acceptValue(arguments[index], expected[index], root ?? local)) accepted = false;
						case _: visit(arguments[index]);
					}
				}
				accepted;
			case _: false;
		};
	}
	acceptValue = (current, expected, root) -> {
		final shape = callableShape(current.t);
		if (shape == null || crossing(shape, expected) == null)
			return false;
		final local = candidate(current);
		if (local != null) {
			if (root != null)
				connect(root, local);
			return true;
		}
		final declared = declaration(current);
		if (declared != null) {
			if (root != null)
				required.set(root, true);
			return true;
		}
		switch (unwrap(current).expr) {
			case TCall(callee, arguments):
				if (declaration(callee) != null && root != null)
					required.set(root, true);
				return acceptCall(callee, arguments, root);
			case _:
				final origin = reflaxe.ocaml.lowered.OcamlCallableOrigin.classify(current);
				if (origin == null || !OcamlCallableValueOperation.isScalarArrow(shape))
					return false;
				rejectReads(current);
				return true;
		}
	};
	visit = current -> {
		switch (current.expr) {
			case TFunction(_):
				rejectReads(current);
				return;
			case TVar(local, value) if (locals.exists(local.id) && value != null):
				final target = shapes.get(local.id);
				if (target == null || !acceptValue(value, target, local.id)) {
					rejected.set(local.id, true);
					rejectReads(value);
				}
				return;
			case TCall(callee, arguments):
				if (acceptCall(callee, arguments, candidate(callee))) return;
			case TReturn(value)
				if (value != null
					&& context != null
					&& context.boundary != null
					&& context.boundary.result != null
					&& context.boundary.result.callableView != null):
				if (acceptValue(value, context.boundary.result.callableView.shape, candidate(value))) return;
			case TBinop(OpEq | OpNotEq, left, right):
				final leftId = candidate(left);
				final rightId = candidate(right);
				final leftShape = callableShape(left.t);
				final rightShape = callableShape(right.t);
				final root = leftId ?? rightId;
				if (leftShape != null && rightShape != null && acceptValue(left, leftShape, root) && acceptValue(right, rightShape, root)) return;
			case TLocal(local) if (locals.exists(local.id)):
				rejected.set(local.id, true);
			case _:
		}
		TypedExprTools.iter(current, visit);
	};
	visit(expression);
	final pending = [for (id in rejected.keys()) id];
	while (pending.length > 0) {
		final id = pending.pop();
		if (id == null)
			break;
		for (linked in edges.get(id) ?? []) {
			if (!rejected.exists(linked)) {
				rejected.set(linked, true);
				pending.push(linked);
			}
		}
	}
	final references:Map<Int, OcamlLocalRepresentationReference> = [];
	final decisions:Array<OcamlLocalRepresentationDecision> = [];
	final writes:Array<OcamlCallableViewLocalDecision> = [];
	for (id => local in locals) {
		if (rejected.exists(id)) {
			if (required.exists(id))
				throw "reflaxe.ocaml [ocaml-callable-local:unplanned-consumer]: a published callback view has an unsupported final-body use";
			continue;
		}
		final shape = shapes.get(id);
		if (shape == null)
			throw "reflaxe.ocaml [ocaml-callable-local:missing-shape]: callback graph lost its signature";
		final representation = registry.selectCallableView(shape, InternalValue);
		final localId = identities.requireHostId(local.id).id;
		references.set(id, {
			localId: localId,
			representationId: representation.id,
			representationRevision: representation.revision,
			semanticTypeId: representation.semanticTypeId,
			domain: representation.domain
		});
		decisions.push({
			localId: localId,
			choice: ProgramDecision(representation.id, representation.revision, representation.semanticTypeId, representation.domain),
			initializerConversion: LegacyCoercion,
			assignmentConversion: LegacyCoercion,
			readConversion: Identity
		});
	}
	for (id => output in references) {
		if (parameters.exists(id))
			continue;
		final value = initializers.get(id);
		if (value == null)
			throw "reflaxe.ocaml [ocaml-callable-local:missing-producer]: selected callback lost its initializer";
		final inputId = candidate(value);
		if (inputId == null) {
			final declared = declaration(value);
			final shape = callableShape(value.t) ?? throw "selected callback producer lost its type";
			final layout = OcamlCallableViewRepresentation.describe(shape);
			if (declared != null) {
				writes.push(sealInput(registry, binding, Initializer, OcamlLoweredOrigin.sourceSpan(value.pos), DeclaredOrigin({
					calleeId: declared.calleeId,
					layout: layout,
					programRevision: declared.programRevision,
					pipelineRevision: declared.pipelineRevision
				}), layout, output));
			} else
				switch (unwrap(value).expr) {
					case TCall(_, _):
						writes.push(sealInput(registry, binding, Initializer, OcamlLoweredOrigin.sourceSpan(value.pos),
							CallResult(OcamlLoweredOrigin.sourceSpan(value.pos)), layout, output));
					case _:
						writes.push(sealProducer(registry, binding, Initializer, value, output));
				}
		} else {
			final input = references.get(inputId);
			if (input == null)
				throw "reflaxe.ocaml [ocaml-callable-local:unconverted-alias]: selected callback refers to unselected storage";
			writes.push(seal(registry, binding, Initializer, OcamlLoweredOrigin.sourceSpan(value.pos), input, output));
		}
	}
	return {locals: decisions, writes: writes};
}
#end
