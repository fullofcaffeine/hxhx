package backend.cpp;

/** A represented allocation retains its shared declaration identity and native descriptor. */
typedef CppManagedNominalAllocation = {
	final identity:String;
	final symbol:String;
}

/**
	Select runtime membership in Haxe from the complete shared nominal graph.
	The generated check compares admitted descriptor addresses after validating
	the physical payload. Native code never reconstructs interface inheritance.
	Runtime tests erase generic arguments; assignment and dispatch keep them.
	A loaded declaration without a represented allocation is not a candidate.
 */
function condition(graph:TypedBackendClassGraph, target:String, allocations:Array<CppManagedNominalAllocation>, value:String):String {
	final matches = new Array<String>();
	for (allocation in allocations)
		if (graph.requireAssignableTypes(allocation.identity).filter(node -> node.classIdentity == target).length != 0)
			matches.push("&" + value + ".asManaged().as<hxhx::managed::InstancePayload>()->descriptor() == &" + allocation.symbol);
	if (matches.length == 0)
		return "false";
	return value
		+ ".kind() == ValueKind::Managed && "
		+ value
		+ ".asManaged().hasLayout<hxhx::managed::InstancePayload>() && ("
		+ matches.join(" || ")
		+ ")";
}
