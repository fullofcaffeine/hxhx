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

/**
	Selects callback storage only for a complete, closed set of local uses.

	An immutable scalar callback can originate in a literal/static method or copy
	another selected local. Every read must be a direct invocation, an alias write,
	or an identity comparison with another selected local. Escapes, captures,
	writes, and higher-order boundaries require their own complete plans. Rejecting
	one use rejects the whole connected set, so an arrow consumer never receives a
	view tuple through an unconverted alias.
**/
function plan(expression:TypedExpr, identities:LexicalLocalIdentityPlan, storage:OcamlLocalStoragePlan, registry:OcamlRepresentationRegistry,
		binding:OcamlFunctionPlanBinding):{
	locals:Array<OcamlLocalRepresentationDecision>,
	writes:Array<OcamlCallableViewLocalDecision>
} {
	final locals:Map<Int, TVar> = [];
	final initializers:Map<Int, TypedExpr> = [];
	final shapes:Map<Int, OcamlGenericValueShape> = [];
	final rejected:Map<Int, Bool> = [];
	final edges:Map<Int, Array<Int>> = [];
	function scalar(shape:OcamlGenericValueShape):Bool {
		return switch (shape) {
			case Integer, Boolean, Text(_), NullableInteger, NullableBoolean, DynamicValue: true;
			case _: false;
		};
	}
	function collect(current:TypedExpr):Void {
		switch (current.expr) {
			case TFunction(_):
				return;
			case TVar(local, value):
				final shape = callableShape(local.t);
				final admitted = shape != null && switch (shape) {
					case FunctionValue(arguments, result): Lambda.foreach(arguments, scalar) && (result == EffectOnly || scalar(result));
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
	function visit(current:TypedExpr):Void {
		switch (current.expr) {
			case TFunction(_):
				rejectReads(current);
				return;
			case TVar(local, value) if (locals.exists(local.id) && value != null):
				final input = candidate(value);
				if (input != null) {
					connect(local.id, input);
					final source = shapes.get(input);
					final target = shapes.get(local.id);
					if (source == null || target == null || crossing(source, target) == null)
						rejected.set(local.id, true);
				} else {
					final origin = reflaxe.ocaml.lowered.OcamlCallableOrigin.classify(value);
					final source = callableShape(value.t);
					final target = shapes.get(local.id);
					final scalarSource = source != null && switch (source) {
						case FunctionValue(arguments, result): Lambda.foreach(arguments, scalar) && (result == EffectOnly || scalar(result));
						case _: false;
					};
					if (origin == null || source == null || target == null || !scalarSource || crossing(source, target) == null)
						rejected.set(local.id, true);
					rejectReads(value);
				}
				return;
			case TCall(callee, arguments) if (candidate(callee) != null):
				for (argument in arguments)
					visit(argument);
				return;
			case TBinop(OpEq | OpNotEq, left, right):
				final leftId = candidate(left);
				final rightId = candidate(right);
				if (leftId != null && rightId != null) {
					connect(leftId, rightId);
					return;
				}
			case TLocal(local) if (locals.exists(local.id)):
				rejected.set(local.id, true);
			case _:
		}
		TypedExprTools.iter(current, visit);
	}
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
		if (rejected.exists(id))
			continue;
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
		final value = initializers.get(id);
		if (value == null)
			throw "reflaxe.ocaml [ocaml-callable-local:missing-producer]: selected callback lost its initializer";
		final inputId = candidate(value);
		if (inputId == null) {
			writes.push(sealProducer(registry, binding, Initializer, value, output));
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
