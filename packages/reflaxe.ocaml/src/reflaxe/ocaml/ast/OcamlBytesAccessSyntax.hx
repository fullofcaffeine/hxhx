package reflaxe.ocaml.ast;

#if (macro || reflaxe_runtime)
import haxe.macro.Type.TypedExpr;
import reflaxe.ocaml.lowered.OcamlBytesAccessModel.OcamlBytesAccessArgumentConversion;
import reflaxe.ocaml.lowered.OcamlBytesAccessModel.OcamlBytesAccessContract;
import reflaxe.ocaml.lowered.OcamlBytesAccessModel.OcamlBytesAccessDecision;
import reflaxe.ocaml.lowered.OcamlBytesAccessModel.OcamlBytesAccessInvocationKind;
import reflaxe.ocaml.lowered.OcamlBytesAccessModel.OcamlBytesAccessKind;
import reflaxe.ocaml.lowered.OcamlInt64RepresentationModel.OcamlInt64RepresentationContract;

/**
	Constructs OCaml syntax from one already-validated Bytes access decision.

	The helper only materializes the sealed receiver/argument schedule and calls
	the recorded `HxBytes` operation. It cannot choose bounds, access width,
	byte order, represented values, mutation, aliasing, declaration identity,
	or result shape.
**/
class OcamlBytesAccessSyntax {
	public static function build(decision:OcamlBytesAccessDecision, receiver:Null<TypedExpr>, arguments:Array<TypedExpr>,
			buildExpression:TypedExpr->OcamlExpr, freshName:String->String):OcamlExpr {
		OcamlBytesAccessContract.requireDecision(decision);
		if (arguments.length != decision.argumentCount)
			throw 'reflaxe.ocaml [ocaml-bytes:access-syntax-arity-mismatch]: access "${decision.id}" expected ${decision.argumentCount} arguments but received ${arguments.length}';

		final evaluated:Array<{name:String, value:OcamlExpr}> = [];
		final converted:Array<{name:String, value:OcamlExpr}> = [];
		var receiverValue:Null<OcamlExpr> = null;
		final argumentValues:Array<Null<OcamlExpr>> = [for (_ in 0...decision.argumentCount) null];
		for (slot in decision.evaluationOrder) {
			if (slot == -1) {
				if (decision.invocationKind != OcamlBytesAccessInvocationKind.Instance || receiver == null || receiverValue != null)
					throw 'reflaxe.ocaml [ocaml-bytes:access-syntax-schedule-mismatch]: access "${decision.id}" has an invalid receiver step';
				final name = freshName("bytes_access_receiver");
				evaluated.push({name: name, value: buildExpression(receiver)});
				receiverValue = OcamlExpr.EIdent(name);
			} else {
				if (slot < 0 || slot >= arguments.length || argumentValues[slot] != null)
					throw 'reflaxe.ocaml [ocaml-bytes:access-syntax-schedule-mismatch]: access "${decision.id}" has an invalid argument step $slot';
				final name = freshName("bytes_access_arg_" + slot);
				evaluated.push({name: name, value: buildExpression(arguments[slot])});
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
		for (index in 0...argumentValues.length) {
			final input = required(decision, argumentValues[index], 'raw argument $index');
			final conversion = decision.argumentConversions[index];
			if (conversion == OcamlBytesAccessArgumentConversion.Identity)
				continue;
			final name = freshName("bytes_access_converted_arg_" + index);
			final value = switch (conversion) {
				case Identity:
					throw 'reflaxe.ocaml [ocaml-bytes:access-syntax-conversion-mismatch]: access "${decision.id}" tried to materialize an identity conversion';
				case RequireNonNullInt:
					OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "nullable_int_unwrap"), [input]);
				case RequireMultiByteIntOrOutsideBounds:
					OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxBytes"), "requireMultiByteInt"), [input]);
			}
			converted.push({name: name, value: value});
			argumentValues[index] = OcamlExpr.EIdent(name);
		}

		final callArguments:Array<OcamlExpr> = [];
		if (receiverValue != null)
			callArguments.push(required(decision, receiverValue, "receiver"));
		for (index in 0...argumentValues.length)
			callArguments.push(required(decision, argumentValues[index], 'argument $index'));
		if (decision.kind == OcamlBytesAccessKind.GetData)
			callArguments.push(OcamlExpr.EConst(OcamlConst.CUnit));
		final runtimeArguments = switch (decision.kind) {
			case GetInt64:
				callArguments.concat([
					OcamlExpr.EField(OcamlExpr.EIdent(OcamlInt64RepresentationContract.TARGET_MODULE_NAME), "___int64_create")
				]);
			case SetInt64:
				final value = required(decision, argumentValues[1], "Int64 argument");
				final typedValue = OcamlExpr.EAnnot(value, OcamlTypeExpr.TIdent(OcamlInt64RepresentationContract.QUALIFIED_CARRIER_TYPE_ID));
				[
					required(decision, receiverValue, "receiver"),
					required(decision, argumentValues[0], "position argument"),
					OcamlExpr.EField(typedValue, "low"),
					OcamlExpr.EField(typedValue, "high")
				];
			case _:
				callArguments;
		}
		var out = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxBytes"), decision.runtimeOperation), runtimeArguments);
		for (offset in 0...converted.length) {
			final binding = converted[converted.length - 1 - offset];
			out = OcamlExpr.ELet(binding.name, binding.value, out, false);
		}
		for (offset in 0...evaluated.length) {
			final binding = evaluated[evaluated.length - 1 - offset];
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
