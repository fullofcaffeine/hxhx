package reflaxe.ocaml.ast;

#if (macro || reflaxe_runtime || eval)
import reflaxe.ocaml.lowered.OcamlCallableViewContract.OcamlCallableViewLocalDecision;
import reflaxe.ocaml.runtimegen.OcamlFinalRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirement;

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
	return OcamlCallableValueSyntax.build({
		operation: reflaxe.ocaml.lowered.OcamlCallableViewContract.operation(input.decision),
		value: input.value,
		fresh: input.fresh,
		profile: input.profile,
		requirements: input.requirements,
		finalRuntimeUses: input.finalRuntimeUses
	});
}
#end
