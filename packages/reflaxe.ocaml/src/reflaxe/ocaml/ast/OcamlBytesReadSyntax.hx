package reflaxe.ocaml.ast;

#if (macro || reflaxe_runtime)
import haxe.macro.Type.TypedExpr;
import reflaxe.ocaml.lowered.OcamlBytesReadModel.OcamlBytesReadContract;
import reflaxe.ocaml.lowered.OcamlBytesReadModel.OcamlBytesReadDecision;
import reflaxe.ocaml.lowered.OcamlBytesReadModel.OcamlBytesReadKind;
import reflaxe.ocaml.lowered.OcamlBytesReadModel.OcamlBytesReadReceiverConversion;

/**
	Constructs OCaml syntax from one already-validated Bytes read decision.

	The helper materializes the receiver first, performs the sealed receiver
	conversion, and then materializes each runtime argument in Haxe source order.
	A checked nullable receiver therefore throws before argument side effects,
	matching Haxe 4.3.7. This helper does not classify declarations, choose
	carriers, or invent runtime dependencies.
**/
class OcamlBytesReadSyntax {
	public static function build(decision:OcamlBytesReadDecision, receiver:TypedExpr, arguments:Array<TypedExpr>, buildExpression:TypedExpr->OcamlExpr,
			freshName:String->String):OcamlExpr {
		OcamlBytesReadContract.requireDecision(decision);
		if (arguments.length != decision.argumentCount)
			throw 'reflaxe.ocaml [ocaml-bytes:read-syntax-arity-mismatch]: read "${decision.id}" expected ${decision.argumentCount} arguments but received ${arguments.length}';
		if (!decision.hasReceiver)
			throw 'reflaxe.ocaml [ocaml-bytes:read-syntax-receiver-mismatch]: read "${decision.id}" received the wrong receiver shape';

		final materialized:Array<{name:String, value:OcamlExpr}> = [];
		var receiverValue:Null<OcamlExpr> = null;
		final argumentValues:Array<Null<OcamlExpr>> = [for (_ in 0...decision.argumentCount) null];
		for (slot in decision.evaluationOrder) {
			if (slot == -1) {
				if (receiverValue != null)
					throw 'reflaxe.ocaml [ocaml-bytes:read-syntax-schedule-mismatch]: read "${decision.id}" has an invalid receiver step';
				final inputName = freshName(decision.receiverConversion == OcamlBytesReadReceiverConversion.Identity ? "bytes_receiver" : "bytes_receiver_input");
				materialized.push({name: inputName, value: buildExpression(receiver)});
				final input = OcamlExpr.EIdent(inputName);
				switch (decision.receiverConversion) {
					case Identity:
						receiverValue = input;
					case RequireNonNullBytes:
						final receiverName = freshName("bytes_receiver");
						materialized.push({name: receiverName, value: requireNonNullBytes(input)});
						receiverValue = OcamlExpr.EIdent(receiverName);
				}
			} else {
				if (slot < 0 || slot >= arguments.length || argumentValues[slot] != null)
					throw 'reflaxe.ocaml [ocaml-bytes:read-syntax-schedule-mismatch]: read "${decision.id}" has an invalid argument step $slot';
				if (decision.argumentRuntimeUse[slot]) {
					final name = freshName("bytes_arg_" + slot);
					materialized.push({name: name, value: buildExpression(arguments[slot])});
					argumentValues[slot] = OcamlExpr.EIdent(name);
				} else {
					argumentValues[slot] = OcamlExpr.EConst(OcamlConst.CUnit);
				}
			}
		}
		if (decision.hasReceiver && receiverValue == null)
			throw 'reflaxe.ocaml [ocaml-bytes:read-syntax-schedule-mismatch]: read "${decision.id}" did not materialize its receiver';
		for (index in 0...argumentValues.length)
			if (argumentValues[index] == null)
				throw 'reflaxe.ocaml [ocaml-bytes:read-syntax-schedule-mismatch]: read "${decision.id}" did not account for argument $index';

		final receiverArgument = receiverValue;
		final runtimeArguments = [
			for (index in 0...argumentValues.length)
				if (decision.argumentRuntimeUse[index]) argumentValues[index]
		];
		final call = switch (decision.kind) {
			case Length:
				hxBytesCall("length", [requiredReceiver(decision, receiverArgument)]);
			case Sub:
				hxBytesCall("sub", [requiredReceiver(decision, receiverArgument)].concat(requiredArguments(decision, runtimeArguments, 2)));
			case Compare:
				hxBytesCall("compare", [requiredReceiver(decision, receiverArgument)].concat(requiredArguments(decision, runtimeArguments, 1)));
			case GetString:
				hxBytesCall("getString",
					[requiredReceiver(decision,
						receiverArgument)].concat(requiredArguments(decision, runtimeArguments, 2)).concat([OcamlExpr.EConst(OcamlConst.CUnit)]));
			case ToString:
				hxBytesCall("toString", [requiredReceiver(decision, receiverArgument), OcamlExpr.EConst(OcamlConst.CUnit)]);
			case ToHex:
				hxBytesCall("toHex", [requiredReceiver(decision, receiverArgument), OcamlExpr.EConst(OcamlConst.CUnit)]);
		}
		var out = call;
		for (offset in 0...materialized.length) {
			final binding = materialized[materialized.length - 1 - offset];
			out = OcamlExpr.ELet(binding.name, binding.value, out, false);
		}
		return out;
	}

	static function requiredReceiver(decision:OcamlBytesReadDecision, receiver:Null<OcamlExpr>):OcamlExpr {
		if (receiver == null)
			throw 'reflaxe.ocaml [ocaml-bytes:read-syntax-receiver-mismatch]: read "${decision.id}" did not provide its receiver';
		return receiver;
	}

	static function requiredArguments(decision:OcamlBytesReadDecision, arguments:Array<Null<OcamlExpr>>, expected:Int):Array<OcamlExpr> {
		if (arguments.length != expected)
			throw 'reflaxe.ocaml [ocaml-bytes:read-syntax-arity-mismatch]: read "${decision.id}" expected $expected runtime arguments but received ${arguments.length}';
		return [
			for (argument in arguments) {
				if (argument == null) throw 'reflaxe.ocaml [ocaml-bytes:read-syntax-schedule-mismatch]: read "${decision.id}" has an unmaterialized argument';
				argument;
			}
		];
	}

	static function hxBytesCall(field:String, arguments:Array<OcamlExpr>):OcamlExpr {
		return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxBytes"), field), arguments);
	}

	static function requireNonNullBytes(input:OcamlExpr):OcamlExpr {
		final represented = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [input]);
		final isNull = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "is_null"), [represented]);
		final throwNullAccess = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_throw_typed"), [
			OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [OcamlExpr.EConst(OcamlConst.CString("Null Access"))]),
			OcamlExpr.EList([
				OcamlExpr.EConst(OcamlConst.CString("String")),
				OcamlExpr.EConst(OcamlConst.CString("Dynamic"))
			])
		]);
		return OcamlExpr.EIf(isNull, throwNullAccess, input);
	}
}
#end
