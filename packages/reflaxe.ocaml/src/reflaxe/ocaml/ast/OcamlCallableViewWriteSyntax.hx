package reflaxe.ocaml.ast;

#if (macro || reflaxe_runtime || eval)
import reflaxe.ocaml.lowered.OcamlCallableViewContract.OcamlCallableViewLocalDecision;
import reflaxe.ocaml.lowered.OcamlCallableViewContract.requireDecision;
import reflaxe.ocaml.lowered.OcamlCallableViewRuntime.occurrences;
import reflaxe.ocaml.runtimegen.OcamlFinalRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirement;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel;

/** Syntax inputs for an already validated callback write, without access to host compiler objects. */
typedef OcamlCallableViewWriteSyntaxInput = {
	final decision:OcamlCallableViewLocalDecision;
	final value:OcamlExpr;
	final fresh:String->String;
	final profile:String;
	final requirements:Array<OcamlRuntimeRequirement>;
	final finalRuntimeUses:OcamlFinalRuntimeUseAuthority;
};

/**
	Builds one callback write from its selected identity and conversion plan.

	The caller validates the source expression and function binding before handing
	over syntax. This module evaluates that expression once, preserves an existing
	identity or creates the selected producer identity, and adapts the invocation.
	Each private runtime helper must match the write's recorded occurrence. The
	completed expression is reconciled before it can enter the enclosing body.
**/
function build(input:OcamlCallableViewWriteSyntaxInput):OcamlExpr {
	final decision = input.decision;
	requireDecision(decision);
	final inputName = input.fresh("callback_input");
	final value:OcamlExpr = EIdent(inputName);
	final produced = switch (decision.input) {
		case ExistingView(_): value;
		case RawOrigin(kind): OcamlCallableViewSyntax.produce(kind, value, input.fresh);
	};
	final uses = occurrences(decision);
	final revision = OcamlRuntimeUseModel.planRevision(decision.binding);
	final authority = new OcamlRuntimeUseAuthority(revision, input.profile, input.requirements, uses, input.finalRuntimeUses);
	function runtime(role:String, symbol:String):OcamlExpr {
		final selected = uses.filter(use -> use.role == role && use.exactSymbol == symbol);
		if (selected.length != 1)
			throw "reflaxe.ocaml [ocaml-callable-local:missing-runtime-use]: callback adapter lost its exact runtime helper";
		return ERuntimeIdent(authority.expressionIdentifier(selected[0].id, revision, symbol));
	}
	final converted = OcamlGenericCallEmitter.convertView(decision.conversion, produced, "callback-write", input.fresh, runtime);
	authority.reconcileExpression(converted);
	return ELet(inputName, input.value, converted, false);
}
#end
