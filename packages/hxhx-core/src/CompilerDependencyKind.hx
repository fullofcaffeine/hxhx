/**
	Why one compiler fact can require another fact to be checked again.

	A public-interface dependency uses a declaration or type signature that callers
	can see. Inline-implementation and constant-value dependencies also consume
	provider implementation: a caller may contain the selected function body or
	field initializer value. Module resolution records which module an import or
	type lookup selected. Static initialization records resolved facts consumed
	while a static field is initialized; provider implementation changes can alter
	initialization behavior or ordering even when its public signature is stable.
	Conditional compilation currently describes a direct configuration input
	rather than a module-to-module edge. The remaining kinds reserve explicit names
	for later macro, feature, and whole-program observations instead of encoding
	those meanings as loosely related strings.

	Private declarations do not appear in the public-interface revision. A
	compiler-selected helper or an access-granted private call therefore consumes
	the implementation revision, which includes private signatures and source.
	This deliberately also invalidates those consumers after private body edits.
**/
enum CompilerDependencyKind {
	ModuleResolution;
	PublicInterface;
	PrivateDeclaration;
	InlineImplementation;
	ConstantValue;
	ConditionalCompilation;
	GeneratedDeclaration;
	StaticInitialization;
	FeatureSelection;
	TargetNeutralProgram;
}
