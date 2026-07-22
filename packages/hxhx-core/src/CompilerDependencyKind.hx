/**
	Why one module depends on another module's compiler facts.

	A public-interface dependency uses a declaration or type signature that callers
	can see. An inline-implementation dependency also consumes the called function's
	body, so a body-only edit can matter. Module resolution records which module an
	import or type lookup selected. The remaining kinds reserve explicit names for
	later macro, initialization, feature, and whole-program observations instead of
	encoding those meanings as loosely related strings.
**/
enum CompilerDependencyKind {
	ModuleResolution;
	PublicInterface;
	InlineImplementation;
	GeneratedDeclaration;
	StaticInitialization;
	FeatureSelection;
	TargetNeutralProgram;
}
