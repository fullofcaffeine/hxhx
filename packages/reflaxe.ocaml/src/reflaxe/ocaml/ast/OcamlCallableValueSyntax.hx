package reflaxe.ocaml.ast;

#if (macro || reflaxe_runtime || eval)
import reflaxe.ocaml.lowered.OcamlCallableValueOperation;
import reflaxe.ocaml.lowered.OcamlCallableViewRuntime.valueOccurrences;
import reflaxe.ocaml.runtimegen.OcamlFinalRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirement;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel;

/** Syntax receives a validated value operation after its source contract checks ownership. */
typedef OcamlCallableValueSyntaxInput = {
	final operation:OcamlCallableValueOperation;
	final value:OcamlExpr;
	final fresh:String->String;
	final profile:String;
	final requirements:Array<OcamlRuntimeRequirement>;
	final finalRuntimeUses:OcamlFinalRuntimeUseAuthority;
};

/**
	Evaluate a callback once, preserve or create its selected identity, then adapt invocation.

	The containing write or return contract validates the typed source and exact
	storage or declaration boundary before this function runs. Runtime helpers
	belong to that occurrence and cannot borrow another conversion's permission.
**/
function build(input:OcamlCallableValueSyntaxInput):OcamlExpr {
	final operation = input.operation;
	requireOperation(operation);
	final inputName = input.fresh("callback_input");
	final value:OcamlExpr = EIdent(inputName);
	final produced = operation.origin == null ? value : OcamlCallableViewSyntax.produce(operation.origin, value, input.fresh);
	final uses = valueOccurrences(operation);
	final revision = OcamlRuntimeUseModel.planRevision(operation.binding);
	final authority = new OcamlRuntimeUseAuthority(revision, input.profile, input.requirements, uses, input.finalRuntimeUses);
	function runtime(role:String, symbol:String):OcamlExpr {
		final selected = uses.filter(use -> use.role == role && use.exactSymbol == symbol);
		if (selected.length != 1)
			throw "reflaxe.ocaml [ocaml-callable-value:missing-runtime-use]: callback adapter lost its exact runtime helper";
		return ERuntimeIdent(authority.expressionIdentifier(selected[0].id, revision, symbol));
	}
	final converted = OcamlGenericCallEmitter.convertView(operation.conversion, produced, operation.role, input.fresh, runtime);
	authority.reconcileExpression(converted);
	return ELet(inputName, input.value, converted, false);
}
#end
