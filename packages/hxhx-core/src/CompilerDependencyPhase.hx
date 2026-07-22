/**
	Compiler phase that proved one dependency fact.

	A phase answers where the fact became authoritative. Module resolution selects
	the source module behind an import or base type. Shared typing selects semantic
	types and callable declarations. Keeping this separate from dependency kind
	lets reports name both where a fact came from and how it affects invalidation.
**/
enum CompilerDependencyPhase {
	ModuleResolution;
	SharedTyping;
}
