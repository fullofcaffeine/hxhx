package reflaxe.ocaml.lowered;

import reflaxe.ocaml.lowered.OcamlCallableReturnContract;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;

/** Facts that join an early transfer to the callback conversion owned by its final function. */
typedef OcamlCallableReturnControlJoin = {
	final binding:OcamlFunctionPlanBinding;
	final source:OcamlLoweredSourceSpan;
	final returnId:Null<String>;
	final returnRevision:Null<String>;
	final semanticTypeId:String;
	final carrierTypeId:String;
	final representationId:String;
};

/** A callback is prepared before boxing; the signal carries that exact view without changing its identity. */
final PROOF_ID = "prepared-callable-view-return-control-v1";

/** A well-formed reference alone cannot authorize a callback transfer from another source or body. */
function requireJoin(join:OcamlCallableReturnControlJoin, returns:Array<OcamlCallableReturnDecision>):OcamlCallableReturnDecision {
	final matches = returns.filter(value -> value.id == join.returnId && value.revision == join.returnRevision);
	if (matches.length != 1)
		throw "reflaxe.ocaml [callback-return-control:missing-return]: control requires one exact prepared callback return";
	final returned = matches[0];
	requireBinding(returned, join.binding);
	final layout = operation(returned).outputLayout;
	if (returned.source.file != join.source.file
		|| returned.source.min < join.source.min
		|| returned.source.max > join.source.max
		|| layout.semanticTypeId != join.semanticTypeId
		|| layout.carrierTypeId != join.carrierTypeId
		|| join.representationId != "representation:" + layout.semanticTypeId + ":internal-value")
		throw "reflaxe.ocaml [callback-return-control:foreign-return]: control differs from its callback source or result";
	return returned;
}
