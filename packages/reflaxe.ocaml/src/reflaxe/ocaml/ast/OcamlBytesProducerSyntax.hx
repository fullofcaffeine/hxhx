package reflaxe.ocaml.ast;

#if (macro || reflaxe_runtime)
import haxe.macro.Type.TypedExpr;
import reflaxe.ocaml.lowered.OcamlBytesProducerModel.OcamlBytesProducerContract;
import reflaxe.ocaml.lowered.OcamlBytesProducerModel.OcamlBytesProducerDecision;
import reflaxe.ocaml.lowered.OcamlBytesProducerModel.OcamlBytesProducerKind;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseAuthority;

/** Generated expression plus only the private identifier added by this producer. */
typedef OcamlBytesProducerMaterialization = {
	final expression:OcamlExpr;
	final runtimeReferences:Array<OcamlExpr>;
}

/**
	Constructs OCaml syntax from one already-validated Bytes producer decision.

	The helper does not classify Haxe calls, choose runtime dependencies, or rely
	on OCaml's function-argument order. It first binds every runtime argument in
	the Haxe source order recorded by the planner. Only then does it consume the
	exact checked `HxBytes` identifier and construct the final call.
**/
class OcamlBytesProducerSyntax {
	/** Materializes runtime arguments and then constructs the authorized call. */
	public static function build(decision:OcamlBytesProducerDecision, arguments:Array<TypedExpr>, buildArgument:TypedExpr->OcamlExpr,
			freshName:String->String, runtimeAuthority:OcamlRuntimeUseAuthority):OcamlBytesProducerMaterialization {
		OcamlBytesProducerContract.requireDecision(decision);
		if (runtimeAuthority == null)
			throw 'reflaxe.ocaml [ocaml-bytes:missing-producer-runtime-authority]: producer "${decision.id}" cannot construct its private runtime identifier';
		if (arguments.length != decision.argumentCount)
			throw 'reflaxe.ocaml [ocaml-bytes:syntax-arity-mismatch]: producer "${decision.id}" expected ${decision.argumentCount} arguments but received ${arguments.length}';

		final materialized:Array<{name:String, value:OcamlExpr}> = [];
		final argumentValues:Array<Null<OcamlExpr>> = [for (_ in 0...decision.argumentCount) null];
		for (index in decision.argumentEvaluationOrder) {
			if (index < 0 || index >= arguments.length || argumentValues[index] != null)
				throw 'reflaxe.ocaml [ocaml-bytes:producer-syntax-schedule-mismatch]: producer "${decision.id}" has an invalid argument step $index';
			if (decision.argumentRuntimeUse[index]) {
				final name = freshName("bytes_producer_arg_" + index);
				materialized.push({name: name, value: buildArgument(arguments[index])});
				argumentValues[index] = OcamlExpr.EIdent(name);
			} else {
				argumentValues[index] = OcamlExpr.EConst(OcamlConst.CUnit);
			}
		}
		for (index in 0...argumentValues.length)
			if (argumentValues[index] == null)
				throw 'reflaxe.ocaml [ocaml-bytes:producer-syntax-schedule-mismatch]: producer "${decision.id}" did not account for argument $index';

		final runtimeArguments = [
			for (index in 0...argumentValues.length)
				if (decision.argumentRuntimeUse[index]) requiredArgument(decision, argumentValues[index], index)
		];
		final callArguments = switch (decision.kind) {
			case Constructor:
				requireArgumentCount(decision, runtimeArguments, 2);
			case Alloc:
				requireArgumentCount(decision, runtimeArguments, 1);
			case OfString:
				requireArgumentCount(decision, runtimeArguments, 1).concat([OcamlExpr.EConst(OcamlConst.CUnit)]);
			case OfData:
				requireArgumentCount(decision, runtimeArguments, 1).concat([OcamlExpr.EConst(OcamlConst.CUnit)]);
			case OfHex:
				requireArgumentCount(decision, runtimeArguments, 1);
		}
		final runtimeReference = runtimeIdentifier(decision, runtimeAuthority);
		var out = OcamlExpr.EApp(runtimeReference, callArguments);
		for (offset in 0...materialized.length) {
			final binding = materialized[materialized.length - 1 - offset];
			out = OcamlExpr.ELet(binding.name, binding.value, out, false);
		}
		return {expression: out, runtimeReferences: [runtimeReference]};
	}

	static function requiredArgument(decision:OcamlBytesProducerDecision, argument:Null<OcamlExpr>, index:Int):OcamlExpr {
		if (argument == null)
			throw 'reflaxe.ocaml [ocaml-bytes:producer-syntax-schedule-mismatch]: producer "${decision.id}" has an unmaterialized argument $index';
		return argument;
	}

	static function requireArgumentCount(decision:OcamlBytesProducerDecision, arguments:Array<OcamlExpr>, expected:Int):Array<OcamlExpr> {
		if (arguments.length != expected)
			throw 'reflaxe.ocaml [ocaml-bytes:syntax-arity-mismatch]: producer "${decision.id}" expected $expected runtime arguments but received ${arguments.length}';
		return arguments;
	}

	static function runtimeIdentifier(decision:OcamlBytesProducerDecision, authority:OcamlRuntimeUseAuthority):OcamlExpr {
		final matches = decision.runtimeUseOccurrences.filter(use -> use.role == "produce-bytes");
		final exactSymbol = "HxBytes." + OcamlBytesProducerContract.runtimeOperation(decision.kind);
		if (matches.length != 1 || matches[0].exactSymbol != exactSymbol)
			throw 'reflaxe.ocaml [ocaml-bytes:wrong-producer-runtime-use]: producer "${decision.id}" has no exact produce-bytes/$exactSymbol occurrence';
		final use = matches[0];
		return OcamlExpr.ERuntimeIdent(authority.expressionIdentifier(use.id, use.planRevision, use.exactSymbol));
	}
}
#end
