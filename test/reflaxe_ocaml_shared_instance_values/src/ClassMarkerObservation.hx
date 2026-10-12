import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirement;

/** Compare every requirement field without depending on a host's object-key enumeration order. */
function describeRequirements(requirements:Array<OcamlRuntimeRequirement>):String {
	return haxe.Json.stringify([
		for (requirement in requirements) [
			requirement.id,
			requirement.sourceKind,
			requirement.sourceId,
			requirement.source.file,
			Std.string(requirement.source.min),
			Std.string(requirement.source.max),
			requirement.semanticCapability,
			requirement.cause,
			requirement.decisionId,
			requirement.subject.kind,
			requirement.subject.id,
			requirement.implementationFeature,
			haxe.Json.stringify(requirement.rootModules),
			haxe.Json.stringify(requirement.profileEligibility),
			requirement.explanation
		]
	]);
}
