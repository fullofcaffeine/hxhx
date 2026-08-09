package reflaxe.ocaml.ast;

#if (macro || reflaxe_runtime)
import haxe.macro.Type.TypedExpr;
import reflaxe.ocaml.lowered.OcamlBytesMutationModel.OcamlBytesMutationArgumentConversion;
import reflaxe.ocaml.lowered.OcamlBytesMutationModel.OcamlBytesMutationContract;
import reflaxe.ocaml.lowered.OcamlBytesMutationModel.OcamlBytesMutationDecision;
import reflaxe.ocaml.lowered.OcamlBytesMutationModel.OcamlBytesMutationKind;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseAuthority;

/**
	Returns both the generated mutation and its compiler-owned helper identifiers.

	The caller checks the identifier list against the mutation decision before
	printing. Keeping the list separate avoids claiming helper calls that belong
	to nested receiver or argument expressions.
**/
typedef OcamlBytesMutationMaterialization = {
	final expression:OcamlExpr;
	final runtimeReferences:Array<OcamlExpr>;
}

/**
	Constructs OCaml syntax from one already-validated Bytes mutation decision.

	The helper materializes the receiver first and every argument once in Haxe
	source order. It cannot classify declarations or choose mutation semantics.
**/
class OcamlBytesMutationSyntax {
	public static function build(decision:OcamlBytesMutationDecision, receiver:TypedExpr, arguments:Array<TypedExpr>, buildExpression:TypedExpr->OcamlExpr,
			freshName:String->String, runtimeAuthority:OcamlRuntimeUseAuthority):OcamlBytesMutationMaterialization {
		OcamlBytesMutationContract.requireDecision(decision);
		if (runtimeAuthority == null)
			throw 'reflaxe.ocaml [ocaml-bytes:missing-mutation-runtime-authority]: mutation "${decision.id}" cannot construct private runtime identifiers';
		if (arguments.length != decision.argumentCount)
			throw 'reflaxe.ocaml [ocaml-bytes:mutation-syntax-arity-mismatch]: mutation "${decision.id}" expected ${decision.argumentCount} arguments but received ${arguments.length}';

		final materialized:Array<{name:String, value:OcamlExpr}> = [];
		final runtimeReferences:Array<OcamlExpr> = [];
		var receiverValue:Null<OcamlExpr> = null;
		final argumentValues:Array<Null<OcamlExpr>> = [for (_ in 0...decision.argumentCount) null];
		for (slot in decision.evaluationOrder) {
			if (slot == -1) {
				if (receiverValue != null)
					throw 'reflaxe.ocaml [ocaml-bytes:mutation-syntax-schedule-mismatch]: mutation "${decision.id}" has an invalid receiver step';
				final name = freshName("bytes_destination");
				materialized.push({name: name, value: buildExpression(receiver)});
				receiverValue = OcamlExpr.EIdent(name);
			} else {
				if (slot < 0 || slot >= arguments.length || argumentValues[slot] != null)
					throw 'reflaxe.ocaml [ocaml-bytes:mutation-syntax-schedule-mismatch]: mutation "${decision.id}" has an invalid argument step $slot';
				final name = freshName("bytes_mutation_arg_" + slot);
				final input = buildExpression(arguments[slot]);
				final converted = switch (decision.argumentConversions[slot]) {
					case Identity:
						input;
					case RequireNonNullInt:
						final runtimeReference = runtimeIdentifier(decision, runtimeAuthority, 'unwrap-argument:$slot', "HxRuntime.nullable_int_unwrap");
						runtimeReferences.push(runtimeReference);
						OcamlExpr.EApp(runtimeReference, [input]);
				}
				materialized.push({name: name, value: converted});
				argumentValues[slot] = OcamlExpr.EIdent(name);
			}
		}
		if (receiverValue == null)
			throw 'reflaxe.ocaml [ocaml-bytes:mutation-syntax-schedule-mismatch]: mutation "${decision.id}" did not materialize its receiver';
		for (index in 0...argumentValues.length)
			if (argumentValues[index] == null)
				throw 'reflaxe.ocaml [ocaml-bytes:mutation-syntax-schedule-mismatch]: mutation "${decision.id}" did not materialize argument $index';

		final callArguments = [required(decision, receiverValue, "receiver")].concat([
			for (index in 0...argumentValues.length)
				required(decision, argumentValues[index], 'argument $index')
		]);
		final field = switch (decision.kind) {
			case Fill: "fill";
			case Blit: "blit";
		}
		final callReference = runtimeIdentifier(decision, runtimeAuthority, "mutate-bytes", "HxBytes." + field);
		runtimeReferences.push(callReference);
		var out = OcamlExpr.EApp(callReference, callArguments);
		for (offset in 0...materialized.length) {
			final binding = materialized[materialized.length - 1 - offset];
			out = OcamlExpr.ELet(binding.name, binding.value, out, false);
		}
		return {expression: out, runtimeReferences: runtimeReferences};
	}

	static function runtimeIdentifier(decision:OcamlBytesMutationDecision, authority:OcamlRuntimeUseAuthority, role:String, exactSymbol:String):OcamlExpr {
		final matches = decision.runtimeUseOccurrences.filter(use -> use.role == role);
		if (matches.length != 1 || matches[0].exactSymbol != exactSymbol)
			throw 'reflaxe.ocaml [ocaml-bytes:wrong-mutation-runtime-use]: mutation "${decision.id}" has no exact $role/$exactSymbol occurrence';
		final use = matches[0];
		return OcamlExpr.ERuntimeIdent(authority.expressionIdentifier(use.id, use.planRevision, use.exactSymbol));
	}

	static function required(decision:OcamlBytesMutationDecision, value:Null<OcamlExpr>, label:String):OcamlExpr {
		if (value == null)
			throw 'reflaxe.ocaml [ocaml-bytes:mutation-syntax-schedule-mismatch]: mutation "${decision.id}" has no $label';
		return value;
	}
}
#end
