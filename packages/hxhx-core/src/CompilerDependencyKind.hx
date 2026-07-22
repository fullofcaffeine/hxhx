/**
	Why one module depends on another module's compiler facts.

	A public-interface dependency uses a declaration or type signature that callers
	can see. Inline-implementation and constant-value dependencies also consume
	provider implementation: a caller may contain the selected function body or
	field initializer value. Module resolution records which module an import or
	type lookup selected. The remaining kinds reserve explicit names for later
	macro, initialization, feature, and whole-program observations instead of
	encoding those meanings as loosely related strings.
**/
enum CompilerDependencyKind {
	ModuleResolution;
	PublicInterface;
	InlineImplementation;
	ConstantValue;
	GeneratedDeclaration;
	StaticInitialization;
	FeatureSelection;
	TargetNeutralProgram;
}
