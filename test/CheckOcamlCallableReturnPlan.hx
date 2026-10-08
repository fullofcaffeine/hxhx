#if macro
import haxe.macro.Context;
import haxe.macro.Type;
import haxe.macro.TypedExprTools;
import reflaxe.lifecycle.FunctionBodyRevision;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallPlanner;
import reflaxe.ocaml.lowered.OcamlCallableReturnContract;
import reflaxe.ocaml.lowered.OcamlCallableViewRepresentation.describe;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.callableShape;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin;
#end

/** Supplies actual typed return occurrences to the native component without claiming compiler integration. */
class CheckOcamlCallableReturnPlan {
	/** Each test factory uses its own producer, declared result and exact typed body. */
	public static macro function selected(fieldName:String):haxe.macro.Expr {
		final owner = switch (Context.getType("Main")) {
			case TInst(reference, []): reference.get();
			case _: throw "missing stored callback fixture";
		};
		final selected = reflaxe.ocaml.lowered.OcamlCallableProgramSelection.select([owner]);
		final field = owner.statics.get().filter(field -> field.name == fieldName)[0];
		final calleeId = OcamlCallPlanner.calleeId(owner, field);
		if (!Lambda.exists(selected, method -> method.calleeId == calleeId))
			throw "callback return fixture has an unsupported consumer";
		final expression = field.expr();
		final body = expression == null ? null : switch (expression.expr) {
			case TFunction(body): body;
			case _: null;
		};
		if (body == null)
			throw "callback return fixture has no typed body";
		final binding:OcamlFunctionPlanBinding = {
			functionId: "callback-return-fixture:" + calleeId,
			programRevision: "callback-return-fixture-program",
			bodyRevision: FunctionBodyRevision.initial(expression).id,
			pipelineRevision: "callback-return-fixture-pipeline"
		};
		function declaration(field:ClassField):OcamlCallableInvocationReference {
			final shape = callableShape(field.type);
			if (shape == null)
				throw "callback return fixture has no closed invocation signature";
			return {
				calleeId: OcamlCallPlanner.calleeId(owner, field),
				layout: describe(shape),
				programRevision: binding.programRevision,
				pipelineRevision: binding.pipelineRevision
			};
		}
		final declared = declaration(field);
		final boundary:OcamlCallableReturnBoundary = {
			calleeId: declared.calleeId,
			layout: declared.layout,
			programRevision: declared.programRevision,
			pipelineRevision: declared.pipelineRevision,
			functionId: binding.functionId,
			bodyRevision: binding.bodyRevision
		};
		final returns:Array<TypedExpr> = [];
		function visit(current:TypedExpr):Void {
			switch (current.expr) {
				case TFunction(_):
					return;
				case TReturn(value) if (value != null):
					returns.push(value);
				case _:
					TypedExprTools.iter(current, visit);
			}
		}
		visit(body.expr);
		if (returns.length != 1)
			throw "callback component expects one authored return";
		final returned = returns[0];
		final input:OcamlCallableReturnInput = switch (returned.expr) {
			case TLocal(local):
				final index = body.args.map(argument -> argument.v.id).indexOf(local.id);
				if (index < 0)
					throw "callback return fixture refers to an unselected local";
				Parameter(index);
			case TCall({expr: TField(_, FStatic(reference, called))}, _):
				if (reference.get().module != owner.module
					|| !Lambda.exists(selected, method -> method.calleeId == OcamlCallPlanner.calleeId(owner, called.get())))
					throw "callback return fixture calls an unselected declaration";
				CallResult(binding.functionId + ":call:0", declaration(called.get()));
			case _:
				final origin = reflaxe.ocaml.lowered.OcamlCallableOrigin.classify(returned);
				final shape = callableShape(returned.t);
				if (origin == null || shape == null)
					throw "callback return fixture has an unsupported producer";
				Producer(origin, describe(shape));
		};
		return Context.makeExpr(seal({
			binding: binding,
			boundary: boundary,
			ordinal: 0,
			source: OcamlLoweredOrigin.sourceSpan(returned.pos),
			input: input
		}), Context.currentPos());
	}
}
