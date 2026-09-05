package reflaxe.ocaml.runtimegen;

#if (macro || reflaxe_runtime || eval)
import haxe.crypto.Sha256;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
#end

/** The target-syntax position in which one private runtime name may appear. */
enum abstract OcamlRuntimeUseDomain(String) from String to String {
	final ExpressionIdentifier = "expression-identifier";
	final TypeIdentifier = "type-identifier";
	final PatternConstructor = "pattern-constructor";
	final GeneratedText = "generated-text";
	final RawBoundary = "raw-boundary";
}

/**
	A restricted identifier accepted by the OCaml target AST.

	The target AST can be compiled into either compiler host, so this inert token
	type must always be available. Only the guarded compiler-side authorities can
	construct it after checking a sealed runtime-use plan.
**/
@:allow(reflaxe.ocaml.runtimegen.OcamlRuntimeUseAuthority)
@:allow(reflaxe.ocaml.runtimegen.OcamlFinalRuntimeUseAuthority)
class OcamlRuntimeReference {
	public final id:String;
	public final planRevision:String;
	public final ownerId:String;
	public final domain:OcamlRuntimeUseDomain;
	public final exactSymbol:String;

	private function new(id:String, planRevision:String, ownerId:String, domain:OcamlRuntimeUseDomain, exactSymbol:String) {
		this.id = id;
		this.planRevision = planRevision;
		this.ownerId = ownerId;
		this.domain = domain;
		this.exactSymbol = exactSymbol;
	}
}

#if (macro || reflaxe_runtime || eval)
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
	final ownerId:String;
	final domain:OcamlRuntimeUseDomain;
	final exactSymbol:String;
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
