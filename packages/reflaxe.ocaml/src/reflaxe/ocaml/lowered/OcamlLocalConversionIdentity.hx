package reflaxe.ocaml.lowered;

import haxe.crypto.Sha256;
import reflaxe.ocaml.lowered.OcamlLocalConversionModel.OcamlLocalConversionRole;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;

/** Stable occurrence identity shared by compiler plans and offline report inspection. */
function occurrenceId(binding:OcamlFunctionPlanBinding, localId:String, role:OcamlLocalConversionRole, source:OcamlLoweredSourceSpan):String {
	return "local-conversion:" + Sha256.encode([
		binding.functionId,
		binding.programRevision,
		binding.bodyRevision,
		binding.pipelineRevision,
		localId,
		(role : String),
		source.file,
		Std.string(source.min),
		Std.string(source.max)
	].join("\n")).substr(0, 32);
}
