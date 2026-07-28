package reflaxe.ocaml.ast;

#if (macro || reflaxe_runtime)
import haxe.macro.Type.TypedExpr;
import reflaxe.ocaml.lowered.OcamlBytesAccessModel.OcamlBytesAccessArgumentConversion;
import reflaxe.ocaml.lowered.OcamlBytesAccessModel.OcamlBytesAccessContract;
import reflaxe.ocaml.lowered.OcamlBytesAccessModel.OcamlBytesAccessDecision;
import reflaxe.ocaml.lowered.OcamlBytesAccessModel.OcamlBytesAccessInvocationKind;
import reflaxe.ocaml.lowered.OcamlBytesAccessModel.OcamlBytesAccessKind;

/**
	Constructs OCaml syntax from one already-validated Bytes access decision.

	The helper only materializes the sealed receiver/argument schedule and calls
	the recorded `HxBytes` operation. It cannot choose bounds, byte values,
	mutation, aliasing, declaration identity, or result shape.
**/
class OcamlBytesAccessSyntax {
	public static function build(decision:OcamlBytesAccessDecision, receiver:Null<TypedExpr>, arguments:Array<TypedExpr>,
			buildExpression:TypedExpr->OcamlExpr, freshName:String->String):OcamlExpr {
		OcamlBytesAccessContract.requireDecision(decision);
		if (arguments.length != decision.argumentCount)
			throw 'reflaxe.ocaml [ocaml-bytes:access-syntax-arity-mismatch]: access "${decision.id}" expected ${decision.argumentCount} arguments but received ${arguments.length}';

		final materialized:Array<{name:String, value:OcamlExpr}> = [];
		var receiverValue:Null<OcamlExpr> = null;
		final argumentValues:Array<Null<OcamlExpr>> = [for (_ in 0...decision.argumentCount) null];
		for (slot in decision.evaluationOrder) {
			if (slot == -1) {
				if (decision.invocationKind != OcamlBytesAccessInvocationKind.Instance || receiver == null || receiverValue != null)
					throw 'reflaxe.ocaml [ocaml-bytes:access-syntax-schedule-mismatch]: access "${decision.id}" has an invalid receiver step';
				final name = freshName("bytes_access_receiver");
				materialized.push({name: name, value: buildExpression(receiver)});
				receiverValue = OcamlExpr.EIdent(name);
			} else {
				if (slot < 0 || slot >= arguments.length || argumentValues[slot] != null)
					throw 'reflaxe.ocaml [ocaml-bytes:access-syntax-schedule-mismatch]: access "${decision.id}" has an invalid argument step $slot';
				final name = freshName("bytes_access_arg_" + slot);
				final input = buildExpression(arguments[slot]);
				final converted = switch (decision.argumentConversions[slot]) {
					case Identity:
						input;
					case RequireNonNullInt:
						OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "nullable_int_unwrap"), [input]);
				}
				materialized.push({name: name, value: converted});
				argumentValues[slot] = OcamlExpr.EIdent(name);
			}
		}
		if (decision.invocationKind == OcamlBytesAccessInvocationKind.Instance && receiverValue == null)
			throw 'reflaxe.ocaml [ocaml-bytes:access-syntax-schedule-mismatch]: access "${decision.id}" did not materialize its receiver';
		if (decision.invocationKind == OcamlBytesAccessInvocationKind.Static && (receiver != null || receiverValue != null))
			throw 'reflaxe.ocaml [ocaml-bytes:access-syntax-schedule-mismatch]: static access "${decision.id}" unexpectedly received a receiver';
		for (index in 0...argumentValues.length)
			if (argumentValues[index] == null)
				throw 'reflaxe.ocaml [ocaml-bytes:access-syntax-schedule-mismatch]: access "${decision.id}" did not materialize argument $index';

		final callArguments:Array<OcamlExpr> = [];
		if (receiverValue != null)
			callArguments.push(required(decision, receiverValue, "receiver"));
		for (index in 0...argumentValues.length)
			callArguments.push(required(decision, argumentValues[index], 'argument $index'));
		if (decision.kind == OcamlBytesAccessKind.GetData)
			callArguments.push(OcamlExpr.EConst(OcamlConst.CUnit));
		var out = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxBytes"), decision.runtimeOperation), callArguments);
		for (offset in 0...materialized.length) {
			final binding = materialized[materialized.length - 1 - offset];
			out = OcamlExpr.ELet(binding.name, binding.value, out, false);
		}
		return out;
	}

	static function required(decision:OcamlBytesAccessDecision, value:Null<OcamlExpr>, label:String):OcamlExpr {
		if (value == null)
			throw 'reflaxe.ocaml [ocaml-bytes:access-syntax-schedule-mismatch]: access "${decision.id}" has no $label';
		return value;
	}
}
#end
