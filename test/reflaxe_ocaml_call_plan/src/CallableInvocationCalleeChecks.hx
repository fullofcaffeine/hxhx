import haxe.macro.Context;
import haxe.macro.Type.TypedExpr;
import reflaxe.ocaml.lowered.OcamlCallableInvocationContract.OcamlCallableInvocationPlan;
import reflaxe.ocaml.lowered.OcamlCallableInvocationContract.calleeId as invocationCalleeId;
import reflaxe.ocaml.lowered.OcamlCallableInvocationContract.matchesCallee;
import reflaxe.ocaml.lowered.OcamlCallableViewRepresentation.OcamlCallableViewDescriptor;
import reflaxe.ocaml.lowered.OcamlCallableViewRepresentation.describe as describeView;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.callableShape;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain;

/**
	Check that a callback invocation selects only the exact local it was planned for.

	Haxe can emit one source call twice with a different local callee in each
	copy. The invocation identity must name that local, and matching must reject
	a typed callee whose local maps to another lexical identity, even when the
	source span and the callee form agree.
**/
class CallableInvocationCalleeChecks {
	public static function run():Void {
		final typed = Context.typeExpr(macro {
			final wrap = (text:String) -> text;
			wrap("value");
		});
		var local:Null<TypedExpr> = null;
		var call:Null<TypedExpr> = null;
		function find(expression:TypedExpr):Void {
			switch (expression.expr) {
				case TCall(callee, _):
					call = expression;
					local = callee;
				case _:
			}
			haxe.macro.TypedExprTools.iter(expression, find);
		}
		find(typed);
		final callee = local;
		if (call == null || callee == null)
			return fail("the fixture must contain one call through a local");
		final hostId = switch (callee.expr) {
			case TLocal(value): value.id;
			case _: return fail("the fixture callee must be a local");
		};
		final shape = callableShape(callee.t);
		if (shape == null)
			return fail("the fixture callee must have a closed callable shape");
		final layout = describeView(shape);
		final first = invocation(callee, layout, "1");
		final second = invocation(callee, layout, "2");
		final binding:reflaxe.ocaml.lowered.OcamlFunctionPlanBinding = {
			functionId: "function:callable-invocation-callee",
			programRevision: "program:callable-invocation-callee",
			bodyRevision: "body:callable-invocation-callee",
			pipelineRevision: "pipeline:callable-invocation-callee"
		};
		if (invocationCalleeId(first, binding) == invocationCalleeId(second, binding))
			fail("two different local callees at one source span must get different callee identities");
		final firstId = lexicalId("1");
		final resolve = (id:Int) -> id == hostId ? firstId : null;
		if (!matchesCallee(first, callee, resolve))
			fail("the invocation must match its own local callee");
		if (matchesCallee(second, callee, resolve))
			fail("the invocation must reject a callee that resolves to another local");
		if (matchesCallee(first, callee, _ -> null))
			fail("an unknown host local must not match an existing view");
		if (!matchesCallee(second, callee))
			fail("without a lookup, only the callee span and form are checked");
		if (matchesCallee(first, call, resolve))
			fail("a callee at another source span must not match");
	}

	static function invocation(callee:TypedExpr, layout:OcamlCallableViewDescriptor, seed:String):OcamlCallableInvocationPlan {
		return {
			source: OcamlLoweredOrigin.sourceSpan(callee.pos),
			input: ExistingView({
				localId: lexicalId(seed),
				representationId: "representation:callable-invocation-callee",
				representationRevision: "sha256:callable-invocation-callee",
				semanticTypeId: layout.semanticTypeId,
				domain: OcamlRepresentationDomain.InternalValue
			}),
			layout: layout
		};
	}

	static function lexicalId(seed:String):String {
		return "lexical-local-v1:" + haxe.crypto.Sha256.encode(seed);
	}

	static function fail(message:String):Void {
		Context.error("Callable invocation callee check failed: " + message, Context.currentPos());
	}
}
