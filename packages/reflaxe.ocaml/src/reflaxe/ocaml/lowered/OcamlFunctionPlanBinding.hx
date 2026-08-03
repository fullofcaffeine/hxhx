package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime || eval)
/**
	Exact function/body context shared by planning and syntax construction.

	This small value type lives outside the plan registry so focused planners can
	build and validate occurrence identities without importing Reflaxe compiler
	objects or the registry's mutable request state.
**/
typedef OcamlFunctionPlanBinding = {
	final functionId:String;
	final programRevision:String;
	final bodyRevision:String;
	final pipelineRevision:String;
}
#end
