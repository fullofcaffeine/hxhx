package reflaxe.ocaml.runtimegen;

#if (macro || reflaxe_runtime || eval)
import haxe.crypto.Sha256;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;

/** The target-syntax position in which one private runtime name may appear. */
enum abstract OcamlRuntimeUseDomain(String) from String to String {
	final ExpressionIdentifier = "expression-identifier";
	final TypeIdentifier = "type-identifier";
	final PatternConstructor = "pattern-constructor";
	final GeneratedText = "generated-text";
	final RawBoundary = "raw-boundary";
}

/**
	One planned appearance of a private compatibility-runtime name.

	A runtime requirement says that a program needs a helper module. This value
	is narrower: it says which exact generated identifier may satisfy that need,
	where it may appear, and how many times it must occur for one sealed plan.
**/
typedef OcamlRuntimeUseOccurrence = {
	final id:String;
	final planRevision:String;
	final ownerId:String;
	final requirementId:String;
	final domain:OcamlRuntimeUseDomain;
	final exactSymbol:String;
	final role:String;
	final order:Int;
	final source:OcamlLoweredSourceSpan;
	final profileEligibility:Array<String>;
	final cardinality:Int;
}

/** Plain audit record produced when a checked runtime identifier is created. */
typedef OcamlRuntimeUseReceipt = {
	final id:String;
	final planRevision:String;
	final domain:OcamlRuntimeUseDomain;
	final exactSymbol:String;
}

/**
	A restricted identifier accepted by the OCaml target AST.

	Callers cannot construct this token directly. The request-local authority
	first checks it against a sealed occurrence and its exact runtime requirement.
	The token carries provenance only; it does not tell the printer how to lower
	Haxe behavior or allow the printer to choose another symbol.
**/
@:allow(reflaxe.ocaml.runtimegen.OcamlRuntimeUseAuthority)
class OcamlRuntimeReference {
	public final id:String;
	public final planRevision:String;
	public final domain:OcamlRuntimeUseDomain;
	public final exactSymbol:String;

	private function new(id:String, planRevision:String, domain:OcamlRuntimeUseDomain, exactSymbol:String) {
		this.id = id;
		this.planRevision = planRevision;
		this.domain = domain;
		this.exactSymbol = exactSymbol;
	}
}

/** Shared deterministic identity rules for runtime-use plans. */
class OcamlRuntimeUseModel {
	/** Binds runtime-use identities to the exact function body and target pipeline. */
	public static function planRevision(binding:OcamlFunctionPlanBinding):String {
		return "sha256:" + Sha256.encode([
			"ocaml-runtime-use-plan-v1",
			binding.functionId,
			binding.programRevision,
			binding.bodyRevision,
			binding.pipelineRevision
		].map(value -> value.length + ":" + value).join("|"));
	}
}
#end
