package reflaxe.ocaml.runtimegen;

#if (macro || reflaxe_runtime || eval)
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;

/** Where the compiler learned that runtime support is required. **/
enum abstract OcamlRuntimeRequirementSourceKind(String) from String to String {
	final HaxeExpression = "haxe-expression";
	final CompilerInfrastructure = "compiler-infrastructure";
	final Configuration = "configuration";
	final RawBoundary = "raw-boundary";
}

/** Which target decision made direct OCaml insufficient for this operation. **/
enum abstract OcamlRuntimeRequirementCause(String) from String to String {
	final LoweringDecision = "lowering-decision";
	final RepresentationDecision = "representation-decision";
	final CompilerInfrastructure = "compiler-infrastructure";
	final ExplicitConfiguration = "explicit-configuration";
	final RawBoundary = "raw-boundary";
}

/**
	One explanation of why generated code needs an OCaml compatibility helper.

	For example, Haxe `Int` addition requires defined 32-bit overflow behavior.
	The requirement records that source behavior and points to `HxInt`; the runtime
	source manifest separately identifies and verifies the `HxInt.ml` bytes.
**/
typedef OcamlRuntimeRequirement = {
	final id:String;
	final sourceKind:OcamlRuntimeRequirementSourceKind;
	final sourceId:String;
	final source:OcamlLoweredSourceSpan;
	final semanticCapability:String;
	final cause:OcamlRuntimeRequirementCause;
	final decisionId:String;
	final subjectTypeId:String;
	final implementationFeature:String;
	final rootModules:Array<String>;
	final profileEligibility:Array<String>;
	final explanation:String;
}
#end
