package reflaxe.ocaml.runtimegen;

#if (macro || reflaxe_runtime || eval)
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;

/** Where the compiler learned that runtime support is required. **/
enum abstract OcamlRuntimeRequirementSourceKind(String) from String to String {
	final HaxeExpression = "haxe-expression";
	final RepresentationDecision = "representation-decision";
	final CompilerInfrastructure = "compiler-infrastructure";
	final Configuration = "configuration";
	final NativeBoundary = "native-boundary";
	final RawBoundary = "raw-boundary";
}

/** Which target decision made direct OCaml insufficient for this operation. **/
enum abstract OcamlRuntimeRequirementCause(String) from String to String {
	final LoweringDecision = "lowering-decision";
	final RepresentationDecision = "representation-decision";
	final CompilerInfrastructure = "compiler-infrastructure";
	final ExplicitConfiguration = "explicit-configuration";
	final NativeBoundary = "native-boundary";
	final RawBoundary = "raw-boundary";
}

/** What kind of program or compiler entity needs the runtime support. **/
enum abstract OcamlRuntimeRequirementSubjectKind(String) from String to String {
	final HaxeType = "haxe-type";
	final GeneratedModule = "generated-module";
	final CompilerPolicy = "compiler-policy";
	final NativeBoundary = "native-boundary";
	final RawBoundary = "raw-boundary";
}

/** Stable identity of the type, generated module, policy, or boundary being supported. **/
typedef OcamlRuntimeRequirementSubject = {
	final kind:OcamlRuntimeRequirementSubjectKind;
	final id:String;
}

/**
	One explanation of why generated code or compiler packaging needs an OCaml
	compatibility helper.

	For example, Haxe `Int` addition requires defined 32-bit overflow behavior.
	The requirement records that behavior and points to `HxInt`; the runtime source
	manifest separately identifies and verifies the `HxInt.ml` bytes. Compiler-made
	modules use the same record shape so their runtime dependencies are not hidden in
	generated strings.
**/
typedef OcamlRuntimeRequirement = {
	final id:String;
	final sourceKind:OcamlRuntimeRequirementSourceKind;
	final sourceId:String;
	final source:OcamlLoweredSourceSpan;
	final semanticCapability:String;
	final cause:OcamlRuntimeRequirementCause;
	final decisionId:String;
	final subject:OcamlRuntimeRequirementSubject;
	final implementationFeature:String;
	final rootModules:Array<String>;
	final profileEligibility:Array<String>;
	final explanation:String;
}
#end
